"""
Putt detection algorithm simulator — mirrors SwingDetectionManager.swift exactly.
Run on device motion CSVs from the sample_putts directory.

Usage:
    python3 detect.py                  # runs all samples
    python3 detect.py path/to/file.csv # run single file
"""

import math
import os
import sys
import glob
from datetime import datetime

# ═══════════════════════════════════════════════════════════════════════════════
#  PARAMETERS  (match SwingDetectionManager.swift defaults exactly)
# ═══════════════════════════════════════════════════════════════════════════════

SAMPLE_RATE_HZ                = 50.0   # CoreMotion device motion update rate
PUTT_MIN_DURATION_S           = 0.3    # Min rotMag-quiet duration to qualify setup (s)
PUTT_SETUP_ROT_MAG_CEILING    = 0.15   # Max instantaneous rotMag during setup (rad/s)
PUTT_PITCH_MIN_DEG            = -25.0  # Setup pitch range min (deg)
PUTT_PITCH_MAX_DEG            = 0.0    # Setup pitch range max (deg)
PUTT_ROLL_MIN_DEG             = 85.0   # Setup roll range min (deg)
PUTT_ROLL_MAX_DEG             = 135.0  # Setup roll range max (deg)
PUTT_FORWARD_STROKE_THRESHOLD = -0.05  # RotY must cross this (from positive) to enter forward stroke
PUTT_MIN_FS_BS_RATIO          = 0.5    # Min forward/backstroke peak RotY ratio
PUTT_MAX_FS_BS_RATIO          = 10.0   # Max forward/backstroke peak RotY ratio
PUTT_ROT_Z_CEILING            = 1.5    # Max |RotZ| at peaks (rad/s)

# ─── Impact detection parameters (raw Z accelerometer @ 800 Hz) ───────────────

IMPACT_STABILITY_WINDOW_MS = 75.0  # larger rolling window used to determine stability (ms)
IMPACT_BASELINE_WINDOW_MS  = 10.0  # smaller window at end of stable period for baseline mean (ms)
IMPACT_STABLE_STD_THRESH   = 0.025 # max Z std across the full stability window
IMPACT_BASELINE_MIN        = 0.20  # min plausible baseline Z (rejects bad orientations)
IMPACT_BASELINE_MAX        = 0.65  # max plausible baseline Z
IMPACT_BUMP_THRESH         = 0.050 # min rise above baseline to detect contact moment
IMPACT_TROUGH_THRESH     = 0.150  # min drop below baseline to confirm deceleration
IMPACT_PEAK_THRESH       = 0.120  # min rise above baseline to confirm rebound
IMPACT_MAX_IMPULSE_MS    = 150.0  # max ms from bump to settle before resetting
IMPACT_SETTLE_WINDOW_MS  = 15.0   # ms window used to confirm re-stabilization
IMPACT_SETTLE_STD_THRESH = 0.030  # max Z std to confirm settled

# ═══════════════════════════════════════════════════════════════════════════════


def _deg(r):
    return r * 180.0 / math.pi


def _rad(d):
    return d * math.pi / 180.0


def _std(values):
    n = len(values)
    if n < 2:
        return 0.0
    mean = sum(values) / n
    return math.sqrt(sum((v - mean) ** 2 for v in values) / (n - 1))


def _mean(values):
    return sum(values) / len(values) if values else 0.0


# ─── CSV PARSING ──────────────────────────────────────────────────────────────

def parse_csv(path):
    """
    Parse a device motion CSV.  Handles two timestamp formats:
      - Old: 'YYYY-MM-DD HH:MM:SS.mmm'  (wall-clock Date() — UNRELIABLE due to
            CoreMotion burst delivery; replaced with index-based time at SAMPLE_RATE_HZ)
      - New: float seconds               (data.timestamp sensor time, used as-is)
    Returns (rows, old_format) where rows is a list of row dicts with keys:
      sensor_time, rot_x, rot_y, rot_z, pitch, roll, ua_mag
    """
    rows = []
    with open(path, 'r') as f:
        lines = f.readlines()

    # Skip metadata header lines until we hit the column-name line
    col_line_idx = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('Timestamp') or stripped.startswith('SensorTime'):
            col_line_idx = i
            break

    if col_line_idx is None:
        raise ValueError(f"Could not find column header in {path}")

    headers = [h.strip() for h in lines[col_line_idx].strip().split(',')]
    old_format = 'Timestamp' in headers  # wall-clock Date() format

    # Map column names to indices
    def col(name):
        return headers.index(name)

    ts_col    = col('Timestamp') if old_format else col('SensorTime')
    roty_col  = col('RotationY')
    rotx_col  = col('RotationX')
    rotz_col  = col('RotationZ')
    pitch_col = col('Pitch')
    roll_col  = col('Roll')
    uamag_col = col('UserAccelMag') if 'UserAccelMag' in headers else None
    uax_col   = col('UserAccelX')   if 'UserAccelX'   in headers else None
    uay_col   = col('UserAccelY')   if 'UserAccelY'   in headers else None
    uaz_col   = col('UserAccelZ')   if 'UserAccelZ'   in headers else None

    for line in lines[col_line_idx + 1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split(',')
        if len(parts) < max(ts_col, roty_col, pitch_col, roll_col) + 1:
            continue

        ts_raw = parts[ts_col].strip()
        if old_format:
            t = 0.0  # will be replaced below with index-based time
        else:
            t = float(ts_raw)

        rows.append({
            'sensor_time': t,
            'rot_x':  float(parts[rotx_col]),
            'rot_y':  float(parts[roty_col]),
            'rot_z':  float(parts[rotz_col]),
            'pitch':  float(parts[pitch_col]),
            'roll':   float(parts[roll_col]),
            'ua_mag': float(parts[uamag_col]) if uamag_col is not None else 0.0,
            'ua_x':   float(parts[uax_col])   if uax_col   is not None else 0.0,
            'ua_y':   float(parts[uay_col])   if uay_col   is not None else 0.0,
            'ua_z':   float(parts[uaz_col])   if uaz_col   is not None else 0.0,
        })

    if old_format:
        # Wall-clock timestamps are unreliable — CoreMotion burst delivery means many
        # samples share nearly identical wall-clock times even though they represent
        # real sensor data spaced 1/SAMPLE_RATE_HZ apart.  Replace with index-based
        # time, which matches what the fixed Swift algorithm sees from data.timestamp.
        sample_dt = 1.0 / SAMPLE_RATE_HZ
        for i, row in enumerate(rows):
            row['sensor_time'] = i * sample_dt

    return rows, old_format


# ─── DETECTION ALGORITHM ──────────────────────────────────────────────────────

def run_putt_detection(rows, verbose=False):
    """
    Putt detection: single linear state machine.
      idle → accumulating → qualified → inBackstroke → inForwardStroke → evaluate
    Setup qualifies when rotMag stays under ceiling (in pitch/roll bounds) for min duration.
    Setup window extends until rotMag leaves the ceiling, at which point rotY dominance is
    checked. Backstroke tracked to peak, forward stroke entered at FORWARD_STROKE_THRESHOLD,
    evaluated when rotY returns to 0.
    """
    pitch_min_rad = _rad(PUTT_PITCH_MIN_DEG)
    pitch_max_rad = _rad(PUTT_PITCH_MAX_DEG)
    roll_min_rad  = _rad(PUTT_ROLL_MIN_DEG)
    roll_max_rad  = _rad(PUTT_ROLL_MAX_DEG)

    state             = 'idle'  # idle | accumulating | qualified | inBackstroke | inForwardStroke
    stable_start_time = None
    bs_peak_rot_y = bs_peak_rot_x = bs_peak_rot_z = 0.0
    fs_peak_rot_y = fs_peak_rot_x = fs_peak_rot_z = 0.0

    detections = []
    log        = []

    def diag(msg, t):
        log.append(f"[{t:10.4f}] {msg}")

    def reset_to_idle(t, outcome='reset'):
        nonlocal state, stable_start_time
        nonlocal bs_peak_rot_y, bs_peak_rot_x, bs_peak_rot_z
        nonlocal fs_peak_rot_y, fs_peak_rot_x, fs_peak_rot_z
        state             = 'idle'
        stable_start_time = None
        bs_peak_rot_y = bs_peak_rot_x = bs_peak_rot_z = 0.0
        fs_peak_rot_y = fs_peak_rot_x = fs_peak_rot_z = 0.0

    for row in rows:
        t     = row['sensor_time']
        rot_x = row['rot_x']
        rot_y = row['rot_y']
        rot_z = row['rot_z']
        pitch = row['pitch']
        roll  = row['roll']

        rot_mag       = math.sqrt(rot_x**2 + rot_y**2 + rot_z**2)
        in_bounds     = (pitch_min_rad <= pitch <= pitch_max_rad and
                         roll_min_rad  <= roll  <= roll_max_rad)
        under_ceiling = rot_mag <= PUTT_SETUP_ROT_MAG_CEILING

        if state == 'idle':
            if in_bounds and under_ceiling:
                stable_start_time = t
                state = 'accumulating'
                diag(f"SETUP: pitch={_deg(pitch):.1f}° roll={_deg(roll):.1f}° → accumulating", t)

        elif state == 'accumulating':
            if not in_bounds:
                diag(f"ACCUM: out of range pitch={_deg(pitch):.1f}° roll={_deg(roll):.1f}° → idle", t)
                reset_to_idle(t)
                continue
            if not under_ceiling:
                diag(f"ACCUM: rotMag={rot_mag:.3f} left ceiling → idle", t)
                reset_to_idle(t)
                continue
            if t - stable_start_time >= PUTT_MIN_DURATION_S:
                state = 'qualified'
                diag(f"QUALIFIED: after {t - stable_start_time:.2f}s pitch={_deg(pitch):.1f}° roll={_deg(roll):.1f}°", t)

        elif state == 'qualified':
            if not in_bounds:
                diag(f"QUALIFIED: out of bounds → idle", t)
                reset_to_idle(t)
                continue
            if not under_ceiling:
                rot_y_dom = rot_y > 0 and abs(rot_y) > abs(rot_x) and abs(rot_y) > abs(rot_z)
                diag(f"QUALIFIED: rotMag={rot_mag:.3f} left ceiling rotY={rot_y:.3f} rotX={rot_x:.3f} rotZ={rot_z:.3f} rotYDom={rot_y_dom}", t)
                if rot_y_dom:
                    bs_peak_rot_y = rot_y
                    bs_peak_rot_x = rot_x
                    bs_peak_rot_z = rot_z
                    state = 'inBackstroke'
                    diag(f"→ BACKSTROKE", t)
                else:
                    diag(f"→ rotY not dominant → idle", t)
                    reset_to_idle(t)

        elif state == 'inBackstroke':
            if in_bounds and under_ceiling:
                diag(f"BACKSTROKE: setup detected → idle", t)
                reset_to_idle(t); continue
            if rot_y > bs_peak_rot_y:
                bs_peak_rot_y = rot_y
                bs_peak_rot_x = rot_x
                bs_peak_rot_z = rot_z
            if rot_y <= PUTT_FORWARD_STROKE_THRESHOLD:
                diag(f"BACKSTROKE→FS: bsPeak rotY={bs_peak_rot_y:.3f} rotX={bs_peak_rot_x:.3f} rotZ={bs_peak_rot_z:.3f}", t)
                fs_peak_rot_y = fs_peak_rot_x = fs_peak_rot_z = 0.0
                state = 'inForwardStroke'

        elif state == 'inForwardStroke':
            if in_bounds and under_ceiling:
                diag(f"FORWARD: setup detected → idle", t)
                reset_to_idle(t); continue
            if rot_y < fs_peak_rot_y:
                fs_peak_rot_y = rot_y
                fs_peak_rot_x = rot_x
                fs_peak_rot_z = rot_z
            if rot_y >= 0:
                fs_peak   = abs(fs_peak_rot_y)
                bs_peak   = abs(bs_peak_rot_y)
                if bs_peak == 0:
                    reset_to_idle(t)
                    continue
                ratio     = fs_peak / bs_peak
                rot_y_dom = fs_peak > abs(fs_peak_rot_x) and fs_peak > abs(fs_peak_rot_z)
                rz_ok     = abs(fs_peak_rot_z) < PUTT_ROT_Z_CEILING
                rat_ok    = PUTT_MIN_FS_BS_RATIO <= ratio <= PUTT_MAX_FS_BS_RATIO
                diag(f"FORWARD: rotY≥0. fsPeak={fs_peak:.3f} bsPeak={bs_peak:.3f} ratio={ratio:.2f} "
                     f"rotYDom={rot_y_dom} rzOk={rz_ok} ratOk={rat_ok}", t)
                if rot_y_dom and rz_ok and rat_ok:
                    diag(f"DETECTED: ratio={ratio:.2f}", t)
                    detections.append(t)
                    reset_to_idle(t, outcome='detected')
                else:
                    diag(f"FORWARD: failed → idle", t)
                    reset_to_idle(t)
                continue

    return detections, log


# ─── IMPACT DETECTION ─────────────────────────────────────────────────────────

def get_stable_windows(raw_rows):
    """
    Return list of (start_t, end_t) intervals where the raw Z signal is stable.
    Stability = std of full IMPACT_STABILITY_WINDOW_MS is under threshold AND
    baseline mean (last IMPACT_BASELINE_WINDOW_MS of that window) is in valid range.
    Mirrors the exact stability check used in run_impact_detection.
    """
    if len(raw_rows) < 4:
        return []
    sample_dt    = (raw_rows[-1]['t'] - raw_rows[0]['t']) / (len(raw_rows) - 1)
    stability_n  = max(4, round(IMPACT_STABILITY_WINDOW_MS / 1000.0 / sample_dt))
    baseline_n   = max(2, round(IMPACT_BASELINE_WINDOW_MS  / 1000.0 / sample_dt))

    windows      = []
    stability_buf = []
    in_stable    = False
    stable_start = None

    for row in raw_rows:
        t = row['t']
        z = row['z']
        stability_buf.append(z)
        if len(stability_buf) > stability_n:
            stability_buf.pop(0)
        if len(stability_buf) == stability_n:
            history    = stability_buf[:-1]  # exclude current sample
            m          = _mean(history[-baseline_n:])
            is_stable  = (_std(history) < IMPACT_STABLE_STD_THRESH and
                          IMPACT_BASELINE_MIN <= m <= IMPACT_BASELINE_MAX)
            if is_stable and not in_stable:
                stable_start = t
                in_stable    = True
            elif not is_stable and in_stable:
                windows.append((stable_start, t))
                in_stable = False

    if in_stable and stable_start is not None:
        windows.append((stable_start, raw_rows[-1]['t']))

    return windows


def run_impact_detection(raw_rows):
    """
    Detect ball contact events in raw Z accelerometer data (800 Hz).

    Shape required (in order):
      stable → bump (contact, wrist briefly accelerates) → trough (deceleration)
             → peak (rebound) → stable

    Returns list of dicts:
      t          – contact timestamp (= bump_t)
      bump_t     – when Z first rises above baseline + BUMP_THRESH
      trough_t   – when Z drops below baseline - TROUGH_THRESH
      peak_t     – when Z rises above baseline + PEAK_THRESH
      settle_t   – when signal re-stabilises after peak
      baseline   – frozen rolling mean at moment of contact
    """
    if len(raw_rows) < 4:
        return []

    sample_dt    = (raw_rows[-1]['t'] - raw_rows[0]['t']) / (len(raw_rows) - 1)
    stability_n  = max(4, round(IMPACT_STABILITY_WINDOW_MS / 1000.0 / sample_dt))
    baseline_n   = max(2, round(IMPACT_BASELINE_WINDOW_MS  / 1000.0 / sample_dt))
    settle_n     = max(4, round(IMPACT_SETTLE_WINDOW_MS    / 1000.0 / sample_dt))
    max_imp_n    = round(IMPACT_MAX_IMPULSE_MS / 1000.0 / sample_dt)

    state        = 'stable'
    baseline     = 0.0
    bump_t       = None
    trough_t     = None
    peak_t       = None
    seq_start_n  = 0
    stability_buf = []
    settle_buf   = []
    detections   = []

    for idx, row in enumerate(raw_rows):
        t = row['t']
        z = row['z']

        if state == 'stable':
            stability_buf.append(z)
            if len(stability_buf) > stability_n:
                stability_buf.pop(0)
            if len(stability_buf) == stability_n:
                # exclude current sample so the bump itself doesn't inflate std/mean
                history = stability_buf[:-1]
                if _std(history) < IMPACT_STABLE_STD_THRESH:
                    m = _mean(history[-baseline_n:])  # baseline from last small window only
                    if (IMPACT_BASELINE_MIN <= m <= IMPACT_BASELINE_MAX
                            and z > m + IMPACT_BUMP_THRESH):
                        baseline      = m
                        bump_t        = t
                        seq_start_n   = idx
                        state         = 'bump'
                        stability_buf = []

        elif state == 'bump':
            if idx - seq_start_n > max_imp_n:
                state = 'stable'; stability_buf = []; continue
            if z < baseline - IMPACT_TROUGH_THRESH:
                trough_t = t
                state    = 'trough'

        elif state == 'trough':
            if idx - seq_start_n > max_imp_n:
                state = 'stable'; stability_buf = []; continue
            if z > baseline + IMPACT_PEAK_THRESH:
                peak_t     = t
                state      = 'peak'
                settle_buf = [z]

        elif state == 'peak':
            settle_buf.append(z)
            if len(settle_buf) > settle_n:
                settle_buf.pop(0)
            if idx - seq_start_n > max_imp_n:
                state = 'stable'; stability_buf = []; continue
            if len(settle_buf) == settle_n and _std(settle_buf) < IMPACT_SETTLE_STD_THRESH:
                detections.append({
                    't':        bump_t,
                    'bump_t':   bump_t,
                    'trough_t': trough_t,
                    'peak_t':   peak_t,
                    'settle_t': t,
                    'baseline': baseline,
                })
                state         = 'stable'
                stability_buf = list(settle_buf)

    return detections


# ─── JOIN ─────────────────────────────────────────────────────────────────────

CONTACT_WINDOW_BEFORE_MS = 75.0   # how far before fs_peak bump_t can occur (ms)
CONTACT_WINDOW_AFTER_MS  = 25.0   # how far after  fs_peak bump_t can occur (ms)

def join_detections(putt_events, impact_events):
    """
    Confirm putts by requiring a raw-accel contact event near the FS peak.

    putt_events  – list of event dicts from run_instrumented() (needs 'fs_peak' entries)
    impact_events – list of dicts from run_impact_detection() (needs 'bump_t')

    Returns list of confirmed dicts, each with all fs_peak fields plus:
      contact_t  – the impact bump_t that confirmed this stroke
      offset_ms  – bump_t relative to fs_peak_t (negative = before peak)
    """
    window_before = CONTACT_WINDOW_BEFORE_MS / 1000.0
    window_after  = CONTACT_WINDOW_AFTER_MS  / 1000.0

    fs_peaks  = [e for e in putt_events if e['kind'] == 'fs_peak']
    confirmed = []

    for fsp in fs_peaks:
        fp_t = fsp['t']
        match = next(
            (imp for imp in impact_events
             if -window_before <= imp['bump_t'] - fp_t <= window_after),
            None
        )
        if match:
            confirmed.append({
                **fsp,
                'contact_t': match['bump_t'],
                'offset_ms': (match['bump_t'] - fp_t) * 1000,
            })

    return confirmed


# ─── MAIN ─────────────────────────────────────────────────────────────────────

def process_file(path, verbose=False):
    print(f"\n{'─'*60}")
    print(f"  {os.path.relpath(path)}")
    print(f"{'─'*60}")

    try:
        rows, old_format = parse_csv(path)
    except Exception as e:
        print(f"  ERROR parsing file: {e}")
        return

    duration = rows[-1]['sensor_time'] - rows[0]['sensor_time'] if len(rows) > 1 else 0
    fmt_note = "  ⚠ old wall-clock timestamps — using index-based time" if old_format else ""
    print(f"  Samples: {len(rows)}   Duration: {duration:.2f}s{fmt_note}")

    detections, log = run_putt_detection(rows, verbose=verbose)

    if detections:
        print(f"  ✅ DETECTED {len(detections)} putt(s) at t = {', '.join(f'{d:.3f}s' for d in detections)}")
    else:
        print(f"  ❌ No putts detected")

    if verbose:
        print()
        for entry in log:
            print(f"    {entry}")


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))

    verbose = '--verbose' in sys.argv or '-v' in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith('-')]

    if args:
        files = args
    else:
        # Find all motion_test CSVs in numbered subdirectories
        files = sorted(glob.glob(os.path.join(script_dir, '**/motion_test_*.csv'), recursive=True))
        files = [f for f in files if not any(p.startswith('_') for p in f.split(os.sep))]

    if not files:
        print("No motion_test CSV files found.")
        return

    print(f"\nRunning putt detection on {len(files)} file(s)...")
    print(f"Params: pitch [{PUTT_PITCH_MIN_DEG}°, {PUTT_PITCH_MAX_DEG}°]  "
          f"roll [{PUTT_ROLL_MIN_DEG}°, {PUTT_ROLL_MAX_DEG}°]  "
          f"minDuration {PUTT_MIN_DURATION_S}s  "
          f"setupRotMag ≤{PUTT_SETUP_ROT_MAG_CEILING} rad/s  "
          f"FST {PUTT_FORWARD_STROKE_THRESHOLD}  "
          f"ratio [{PUTT_MIN_FS_BS_RATIO}, {PUTT_MAX_FS_BS_RATIO}]")

    for f in files:
        process_file(f, verbose=verbose)

    print()


if __name__ == '__main__':
    main()
