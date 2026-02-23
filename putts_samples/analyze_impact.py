"""
Impact moment analysis for putting data.

For each detected putt, aligns raw accelerometer data with the detection
timestamp and looks for the club-ball impact signature in the raw Z axis.

Strategy:
  - Detection fires at the END of the forward stroke (rotY crosses back to 0).
  - The actual ball contact happens at or near the PEAK forward-stroke velocity,
    which is typically 100–400ms BEFORE the detection timestamp.
  - Impact produces a brief transient spike in raw acceleration (especially
    along the axis perpendicular to wrist motion, usually Z or Y depending on
    watch orientation).

Usage:
    python3 analyze_impact.py
    python3 analyze_impact.py --verbose   # prints raw window data too
"""

import math, os, sys, glob, re

# ── re-use detection from detect.py ────────────────────────────────────────
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from detect import parse_csv, run_putt_detection, SAMPLE_RATE_HZ

VERBOSE = '--verbose' in sys.argv or '-v' in sys.argv

# Window around detection time to search for impact (seconds)
LOOK_BACK_S  = 0.8   # how far before detection to start looking
LOOK_AHEAD_S = 0.1   # small window after detection (follow-through)

# Minimum spike magnitude to be considered a candidate impact
SPIKE_THRESHOLD = 0.15  # in g (raw accel units, gravity included)

# Smoothing window for derivative (samples)
DERIV_WINDOW = 3


def parse_raw_accel(path):
    """Return list of dicts: {t, x, y, z, mag}"""
    rows = []
    with open(path) as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if line.strip().startswith('SensorTime'):
            headers = [h.strip() for h in line.strip().split(',')]
            def ci(name): return headers.index(name)
            tc = ci('SensorTime')
            xc = ci('RawAccelX')
            yc = ci('RawAccelY')
            zc = ci('RawAccelZ')
            mc = ci('RawAccelMag')
            for l in lines[i+1:]:
                p = l.strip().split(',')
                if len(p) < 5: continue
                rows.append({'t': float(p[tc]), 'x': float(p[xc]),
                             'y': float(p[yc]), 'z': float(p[zc]),
                             'm': float(p[mc])})
            break
    return rows


def find_raw_accel_file(script_dir, motion_path):
    """
    Given a motion_test_XXXXXXX.csv path, find the matching raw_accel file.
    They're numbered by Unix timestamp so pick the raw_accel file whose
    time range overlaps the motion file's sensor-time range.
    """
    # First try exact number match (might differ by 1)
    m = re.search(r'motion_test_(\d+)', motion_path)
    if not m:
        return None
    stem = m.group(1)

    # Try exact and ±1
    for candidate in glob.glob(os.path.join(script_dir, 'raw_accel_*.csv')):
        rc = re.search(r'raw_accel_(\d+)', candidate)
        if rc and abs(int(rc.group(1)) - int(stem)) <= 2:
            return candidate
    return None


def derivative(values, dt):
    """Simple central-difference derivative."""
    n = len(values)
    d = [0.0] * n
    for i in range(1, n - 1):
        d[i] = (values[i + 1] - values[i - 1]) / (2 * dt)
    d[0]  = d[1]
    d[-1] = d[-2]
    return d


def smooth(values, window=3):
    out = list(values)
    half = window // 2
    for i in range(half, len(values) - half):
        out[i] = sum(values[i-half:i+half+1]) / window
    return out


def find_impact_candidates(raw_rows, detect_time):
    """
    Within [detect_time - LOOK_BACK_S, detect_time + LOOK_AHEAD_S] look for
    sharp transients (high |dZ/dt|) that likely indicate club-ball contact.
    Returns list of (t, z, dz_dt, mag) candidates sorted by |dz_dt|.
    """
    window = [r for r in raw_rows
              if detect_time - LOOK_BACK_S <= r['t'] <= detect_time + LOOK_AHEAD_S]
    if len(window) < 4:
        return []

    zvals = [r['z'] for r in window]
    mvals = [r['m'] for r in window]
    ts    = [r['t'] for r in window]
    dt    = (ts[-1] - ts[0]) / (len(ts) - 1) if len(ts) > 1 else 0.01

    # Smooth then differentiate
    zsmooth = smooth(zvals, DERIV_WINDOW)
    msmooth = smooth(mvals, DERIV_WINDOW)
    dzdt    = derivative(zsmooth, dt)
    dmdt    = derivative(msmooth, dt)

    # Find local peaks in |dz/dt| that exceed threshold
    candidates = []
    for i in range(1, len(window) - 1):
        if abs(dzdt[i]) > abs(dzdt[i-1]) and abs(dzdt[i]) > abs(dzdt[i+1]):
            if abs(zsmooth[i] - zsmooth[max(0,i-3)]) >= SPIKE_THRESHOLD:
                candidates.append({
                    't':     ts[i],
                    'z':     zvals[i],
                    'z_sm':  zsmooth[i],
                    'dzdt':  dzdt[i],
                    'mag':   mvals[i],
                    'dt_from_detect': ts[i] - detect_time,
                    'idx_in_window':  i,
                })

    candidates.sort(key=lambda c: abs(c['dzdt']), reverse=True)
    return candidates, window, zsmooth, dzdt


def print_window(window, zsmooth, dzdt, impact_t=None, detect_t=None):
    """Print a compact table of the raw accel window."""
    print(f"    {'SensorTime':>14}  {'RawZ':>8}  {'Z_smooth':>9}  {'dZ/dt':>8}  {'Mag':>7}  note")
    for i, r in enumerate(window):
        note = ''
        if impact_t is not None and abs(r['t'] - impact_t) < 0.006:
            note = '  ← IMPACT'
        if detect_t is not None and abs(r['t'] - detect_t) < 0.006:
            note += '  ← DETECT'
        print(f"    {r['t']:14.4f}  {r['z']:8.4f}  {zsmooth[i]:9.4f}  {dzdt[i]:8.3f}  {r['m']:7.4f}{note}")


def process_pair(motion_path, raw_path):
    tag = os.path.basename(motion_path)
    print(f"\n{'═'*70}")
    print(f"  {tag}")
    print(f"{'═'*70}")

    # Parse motion and run detection
    rows, old_fmt = parse_csv(motion_path)
    detections, _log = run_putt_detection(rows)

    if not detections:
        print("  ❌ No putts detected by algorithm")
        return

    # Parse raw accel
    if raw_path is None:
        print("  ⚠ No matching raw_accel file found")
        return

    raw_rows = parse_raw_accel(raw_path)
    print(f"  Raw accel: {len(raw_rows)} samples  "
          f"t=[{raw_rows[0]['t']:.2f},{raw_rows[-1]['t']:.2f}]  "
          f"rate≈{1/((raw_rows[-1]['t']-raw_rows[0]['t'])/(len(raw_rows)-1)):.0f}Hz")

    for di, det_t in enumerate(detections):
        print(f"\n  ── Putt #{di+1}  detected at t={det_t:.4f}s ──")
        result = find_impact_candidates(raw_rows, det_t)
        if not result:
            print("    (not enough raw samples in window)")
            continue

        candidates, window, zsmooth, dzdt = result
        print(f"    Search window: [{det_t-LOOK_BACK_S:.3f}, {det_t+LOOK_AHEAD_S:.3f}]  "
              f"({len(window)} raw samples)")

        if candidates:
            best = candidates[0]
            rel  = best['dt_from_detect']
            print(f"\n    🎯 Best impact candidate:")
            print(f"       t = {best['t']:.4f}s  ({rel:+.3f}s from detection)")
            print(f"       RawZ = {best['z']:.4f}g   Z_smooth = {best['z_sm']:.4f}g")
            print(f"       dZ/dt = {best['dzdt']:.3f}g/s   RawMag = {best['mag']:.4f}g")

            if len(candidates) > 1:
                print(f"\n    Other candidates (sorted by |dZ/dt|):")
                for c in candidates[1:4]:
                    print(f"       t={c['t']:.4f}s  ({c['dt_from_detect']:+.3f}s)  "
                          f"RawZ={c['z']:.4f}  dZ/dt={c['dzdt']:.3f}")

            if VERBOSE:
                print(f"\n    Raw window data:")
                print_window(window, zsmooth, dzdt,
                             impact_t=best['t'], detect_t=det_t)
        else:
            print("    ⚠ No clear impact spike found (threshold may need tuning)")
            # Still print top 3 by |dz/dt|
            ts    = [r['t'] for r in window]
            zvals = [r['z'] for r in window]
            dt    = (ts[-1]-ts[0])/(len(ts)-1) if len(ts)>1 else 0.01
            zsmooth2 = smooth(zvals, DERIV_WINDOW)
            dzdt2    = derivative(zsmooth2, dt)
            ranked = sorted(range(len(window)),
                            key=lambda i: abs(dzdt2[i]), reverse=True)[:3]
            print(f"    Top 3 dZ/dt peaks in window:")
            for i in ranked:
                print(f"       t={ts[i]:.4f}s  ({ts[i]-det_t:+.3f}s)  "
                      f"RawZ={zvals[i]:.4f}  dZ/dt={dzdt2[i]:.3f}")
            if VERBOSE:
                print(f"\n    Raw window data:")
                print_window(window, zsmooth2, dzdt2, detect_t=det_t)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    motion_files = sorted(glob.glob(os.path.join(script_dir, 'motion_test_*.csv')))

    print(f"Impact analysis for {len(motion_files)} motion file(s)")
    print(f"Look-back: {LOOK_BACK_S}s before detection  |  spike threshold: {SPIKE_THRESHOLD}g")

    for mf in motion_files:
        rf = find_raw_accel_file(script_dir, mf)
        process_pair(mf, rf)

    print()


if __name__ == '__main__':
    main()
