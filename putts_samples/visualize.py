"""
Visualize putt detection events for each motion_test CSV.
Outputs an interactive HTML file per recording — zoom, pan, toggle traces in browser.

Layout (3 subplots, shared x-axis):
  1. RotY  — main putt signal, with all detection annotations
  2. RotX / RotZ — secondary rotation (separate panel so RotY stays readable)
  3. Pitch / Roll — orientation with valid-range bands

Usage:
    python3 visualize.py              # all motion_test_*.csv → HTML files in same dir
    python3 visualize.py <file.csv>   # single file
"""

import os, sys, glob, re, math
import plotly.graph_objects as go
from plotly.subplots import make_subplots

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from detect import (
    parse_csv, _deg, _rad, _std, _mean,
    PUTT_MIN_DURATION_S,
    PUTT_SETUP_ROT_MAG_CEILING,
    PUTT_PITCH_MIN_DEG, PUTT_PITCH_MAX_DEG, PUTT_ROLL_MIN_DEG, PUTT_ROLL_MAX_DEG,
    PUTT_FORWARD_STROKE_THRESHOLD,
    PUTT_MIN_FS_BS_RATIO, PUTT_MAX_FS_BS_RATIO,
    PUTT_ROT_Z_CEILING,
    run_impact_detection,
    get_stable_windows,
    join_detections,
    IMPACT_BASELINE_MIN, IMPACT_BASELINE_MAX,
    IMPACT_STABILITY_WINDOW_MS,
)

C_SETUP   = 'green'
C_BS      = 'royalblue'
C_FS      = 'orange'
C_DETECT  = 'crimson'
C_INVALID = 'tomato'
C_RESET   = 'gray'


# ── instrumented detection (mirrors detect.py exactly) ──────────────────────

def run_instrumented(rows):
    """Mirrors run_putt_detection in detect.py exactly, but emits events for visualization."""
    pitch_min_rad = _rad(PUTT_PITCH_MIN_DEG)
    pitch_max_rad = _rad(PUTT_PITCH_MAX_DEG)
    roll_min_rad  = _rad(PUTT_ROLL_MIN_DEG)
    roll_max_rad  = _rad(PUTT_ROLL_MAX_DEG)

    state             = 'idle'  # idle | accumulating | qualified | inBackstroke | inForwardStroke
    stable_start_time = None
    bs_peak_rot_y = bs_peak_rot_x = bs_peak_rot_z = 0.0
    bs_peak_t     = None
    fs_peak_rot_y = fs_peak_rot_x = fs_peak_rot_z = 0.0
    fs_peak_t     = None
    setup_start_t = None
    events = []

    def evt(kind, t, **kw):
        events.append({'kind': kind, 't': t, **kw})

    def reset_to_idle(t, reason=''):
        nonlocal state, stable_start_time, setup_start_t
        nonlocal bs_peak_rot_y, bs_peak_rot_x, bs_peak_rot_z, bs_peak_t
        nonlocal fs_peak_rot_y, fs_peak_rot_x, fs_peak_rot_z, fs_peak_t
        state             = 'idle'
        stable_start_time = None
        bs_peak_rot_y = bs_peak_rot_x = bs_peak_rot_z = 0.0; bs_peak_t = None
        fs_peak_rot_y = fs_peak_rot_x = fs_peak_rot_z = 0.0; fs_peak_t = None
        evt('reset', t, reason=reason)

    for row in rows:
        t     = row['sensor_time']
        rot_x = row['rot_x']; rot_y = row['rot_y']; rot_z = row['rot_z']
        pitch = row['pitch']; roll  = row['roll']

        rot_mag       = math.sqrt(rot_x**2 + rot_y**2 + rot_z**2)
        in_bounds     = (pitch_min_rad <= pitch <= pitch_max_rad and
                         roll_min_rad  <= roll  <= roll_max_rad)
        under_ceiling = rot_mag <= PUTT_SETUP_ROT_MAG_CEILING

        if state == 'idle':
            if in_bounds and under_ceiling:
                stable_start_time = t; setup_start_t = t
                state = 'accumulating'
                evt('setup_start', t)

        elif state == 'accumulating':
            if not in_bounds:
                reset_to_idle(t, 'out_of_range'); continue
            if not under_ceiling:
                reset_to_idle(t, 'rotmag'); continue
            if t - stable_start_time >= PUTT_MIN_DURATION_S:
                state = 'qualified'
                evt('qualified', t, duration=t - stable_start_time, setup_start=setup_start_t)

        elif state == 'qualified':
            if not in_bounds:
                reset_to_idle(t, 'out_of_bounds'); continue
            if not under_ceiling:
                rot_y_dom = rot_y > 0 and abs(rot_y) > abs(rot_x) and abs(rot_y) > abs(rot_z)
                if rot_y_dom:
                    bs_peak_rot_y = rot_y; bs_peak_rot_x = rot_x; bs_peak_rot_z = rot_z; bs_peak_t = t
                    state = 'inBackstroke'
                    evt('bs_start', t, rot_y=rot_y)
                else:
                    reset_to_idle(t, 'roty_not_dominant'); continue

        elif state == 'inBackstroke':
            if rot_y > bs_peak_rot_y:
                bs_peak_rot_y = rot_y; bs_peak_rot_x = rot_x; bs_peak_rot_z = rot_z; bs_peak_t = t
            if rot_y <= PUTT_FORWARD_STROKE_THRESHOLD:
                evt('bs_peak', bs_peak_t, rot_y=bs_peak_rot_y, rot_x=bs_peak_rot_x, rot_z=bs_peak_rot_z)
                fs_peak_rot_y = fs_peak_rot_x = fs_peak_rot_z = 0.0; fs_peak_t = None
                state = 'inForwardStroke'
                evt('fs_start', t, rot_y=rot_y)

        elif state == 'inForwardStroke':
            if rot_y < fs_peak_rot_y:
                fs_peak_rot_y = rot_y; fs_peak_rot_x = rot_x; fs_peak_rot_z = rot_z; fs_peak_t = t
            if rot_y >= 0:
                fs_peak = abs(fs_peak_rot_y); bs_peak = abs(bs_peak_rot_y)
                if bs_peak == 0:
                    reset_to_idle(t, 'zero_bs_peak'); continue
                ratio     = fs_peak / bs_peak
                rot_y_dom = fs_peak > abs(fs_peak_rot_x) and fs_peak > abs(fs_peak_rot_z)
                rz_ok     = abs(fs_peak_rot_z) < PUTT_ROT_Z_CEILING
                rat_ok    = PUTT_MIN_FS_BS_RATIO <= ratio <= PUTT_MAX_FS_BS_RATIO
                if fs_peak_t is not None:
                    evt('fs_peak', fs_peak_t, rot_y=fs_peak_rot_y, rot_x=fs_peak_rot_x,
                        rot_z=fs_peak_rot_z, ratio=ratio, rat_ok=rat_ok, rot_y_dom=rot_y_dom, rz_ok=rz_ok)
                if rot_y_dom and rz_ok and rat_ok:
                    evt('detected', t, ratio=ratio, bs_peak=bs_peak, fs_peak=fs_peak)
                    reset_to_idle(t, 'detected')
                else:
                    reset_to_idle(t, 'fs_ended_no_detect')
                continue

    return events


# ── raw accel helpers ────────────────────────────────────────────────────────

def find_raw_accel_path(motion_path):
    """Find the matching raw accel CSV for a given motion CSV."""
    dir_path = os.path.dirname(motion_path)
    base = os.path.basename(motion_path)

    # putt_event_TSTAMP.csv  →  putt_event_raw_TSTAMP.csv
    # putt_fail_TSTAMP.csv   →  putt_fail_raw_TSTAMP.csv
    m = re.search(r'^(putt_(?:event|fail))_(\d+)\.csv$', base)
    if m:
        prefix, ts = m.group(1), m.group(2)
        explicit = os.path.join(dir_path, f'{prefix}_raw_{ts}.csv')
        if os.path.exists(explicit):
            return explicit
        # fall back to closest-timestamp raw file in same dir
        candidates = glob.glob(os.path.join(dir_path, f'{prefix}_raw_*.csv'))
        if candidates:
            def ts_of(p):
                m2 = re.search(r'_raw_(\d+)', os.path.basename(p))
                return int(m2.group(1)) if m2 else 0
            return min(candidates, key=lambda p: abs(ts_of(p) - int(ts)))
        return None

    # legacy: motion_test_TSTAMP.csv  →  raw_accel_TSTAMP.csv
    m = re.search(r'motion_test_(\d+)', base)
    if not m:
        return None
    motion_ts = int(m.group(1))
    candidates = glob.glob(os.path.join(dir_path, 'raw_accel_*.csv'))
    if not candidates:
        return None
    def ts_of(p):
        m2 = re.search(r'raw_accel_(\d+)', os.path.basename(p))
        return int(m2.group(1)) if m2 else 0
    return min(candidates, key=lambda p: abs(ts_of(p) - motion_ts))


def parse_raw_accel_csv(path):
    rows = []
    with open(path, 'r') as f:
        lines = f.readlines()
    col_line_idx = next((i for i, l in enumerate(lines) if l.strip().startswith('SensorTime')), None)
    if col_line_idx is None:
        return rows
    headers = [h.strip() for h in lines[col_line_idx].strip().split(',')]
    ti = headers.index('SensorTime')
    xi = headers.index('RawAccelX')
    yi = headers.index('RawAccelY')
    zi = headers.index('RawAccelZ')
    for line in lines[col_line_idx + 1:]:
        line = line.strip()
        if not line:
            continue
        p = line.split(',')
        rows.append({'t': float(p[ti]), 'x': float(p[xi]), 'y': float(p[yi]), 'z': float(p[zi])})
    return rows


# ── plotting ────────────────────────────────────────────────────────────────

def plot_file(path, out_dir):
    rows, _ = parse_csv(path)
    events  = run_instrumented(rows)

    raw_path = find_raw_accel_path(path)
    raw_rows = parse_raw_accel_csv(raw_path) if raw_path else []
    impacts  = run_impact_detection(raw_rows) if raw_rows else []
    confirmed_putts = join_detections(events, impacts)
    confirmed_ts    = {round(c['contact_t'], 4) for c in confirmed_putts}

    ts    = [r['sensor_time'] for r in rows]
    t0    = ts[0]
    trel  = [t - t0 for t in ts]
    rot_y   = [r['rot_y'] for r in rows]
    rot_x   = [r['rot_x'] for r in rows]
    rot_z   = [r['rot_z'] for r in rows]
    rot_mag = [math.sqrt(r['rot_x']**2 + r['rot_y']**2 + r['rot_z']**2) for r in rows]
    ua_x   = [r['ua_x']   for r in rows]
    ua_y   = [r['ua_y']   for r in rows]
    ua_z   = [r['ua_z']   for r in rows]
    ua_mag = [r['ua_mag'] for r in rows]
    pitch = [_deg(r['pitch']) for r in rows]
    roll  = [_deg(r['roll'])  for r in rows]

    raw_trel = [r['t'] - t0 for r in raw_rows]
    raw_x    = [r['x'] for r in raw_rows]
    raw_y    = [r['y'] for r in raw_rows]
    raw_z    = [r['z'] for r in raw_rows]

    stem = os.path.basename(path).replace('.csv', '')

    # Count detections
    detected_count  = sum(1 for e in events if e['kind'] == 'detected')
    confirmed_count = len(confirmed_putts)
    attempt_count   = sum(1 for e in events if e['kind'] == 'qualified')
    title = (f"{stem}  —  {confirmed_count} confirmed strokes"
             f" / {detected_count} swing detections"
             f" / {attempt_count} qualified attempts")

    n_rows = 4 if raw_rows else 3
    if raw_rows:
        subplot_titles = ('RotY / RotX / RotZ', 'Pitch / Roll  (°)', 'UserAccel X/Y/Z  (G)', 'Raw Accel  (G)')
        row_heights    = [0.35, 0.20, 0.20, 0.25]
    else:
        subplot_titles = ('RotY / RotX / RotZ', 'Pitch / Roll  (°)', 'UserAccel X/Y/Z  (G)')
        row_heights    = [0.45, 0.25, 0.30]

    fig = make_subplots(
        rows=n_rows, cols=1, shared_xaxes=True, vertical_spacing=0.05,
        subplot_titles=subplot_titles,
        row_heights=row_heights,
    )

    # ── Signal traces ──────────────────────────────────────────────────────
    fig.add_trace(go.Scatter(x=trel, y=rot_x, name='RotX', line=dict(color='cornflowerblue', width=1),
                             opacity=0.6, hovertemplate='t=%{x:.3f}s<br>RotX=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=rot_z, name='RotZ', line=dict(color='rosybrown', width=1),
                             opacity=0.6, hovertemplate='t=%{x:.3f}s<br>RotZ=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=rot_y, name='RotY', line=dict(color='royalblue', width=1.5),
                             hovertemplate='t=%{x:.3f}s<br>RotY=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=rot_mag, name='RotMag', line=dict(color='black', width=1.8),
                             hovertemplate='t=%{x:.3f}s<br>RotMag=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=pitch, name='Pitch', line=dict(color='seagreen', width=1.2),
                             hovertemplate='t=%{x:.3f}s<br>Pitch=%{y:.1f}°'), row=2, col=1)
    fig.add_trace(go.Scatter(x=trel, y=roll,  name='Roll',  line=dict(color='darkorchid', width=1.2),
                             hovertemplate='t=%{x:.3f}s<br>Roll=%{y:.1f}°'), row=2, col=1)

    fig.add_trace(go.Scatter(x=trel, y=ua_x, name='UserAccelX', line=dict(color='coral', width=1),
                             opacity=0.45, hovertemplate='t=%{x:.3f}s<br>UserAccelX=%{y:.3f}'), row=3, col=1)
    fig.add_trace(go.Scatter(x=trel, y=ua_y, name='UserAccelY', line=dict(color='mediumseagreen', width=1),
                             opacity=0.45, hovertemplate='t=%{x:.3f}s<br>UserAccelY=%{y:.3f}'), row=3, col=1)
    fig.add_trace(go.Scatter(x=trel, y=ua_z, name='UserAccelZ', line=dict(color='mediumslateblue', width=1),
                             opacity=0.45, hovertemplate='t=%{x:.3f}s<br>UserAccelZ=%{y:.3f}'), row=3, col=1)
    fig.add_trace(go.Scatter(x=trel, y=ua_mag, name='UserAccelMag', line=dict(color='black', width=1.8),
                             hovertemplate='t=%{x:.3f}s<br>UserAccelMag=%{y:.3f}'), row=3, col=1)

    if raw_rows:
        fig.add_trace(go.Scatter(x=raw_trel, y=raw_x, name='RawX', line=dict(color='lightsalmon', width=1),
                                 opacity=0.35, hovertemplate='t=%{x:.3f}s<br>RawX=%{y:.3f}'), row=4, col=1)
        fig.add_trace(go.Scatter(x=raw_trel, y=raw_y, name='RawY', line=dict(color='mediumaquamarine', width=1),
                                 opacity=0.35, hovertemplate='t=%{x:.3f}s<br>RawY=%{y:.3f}'), row=4, col=1)
        fig.add_trace(go.Scatter(x=raw_trel, y=raw_z, name='RawZ', line=dict(color='darkorange', width=1.5),
                                 hovertemplate='t=%{x:.3f}s<br>RawZ=%{y:.3f}'), row=4, col=1)

    # ── Threshold reference lines (row 1) ─────────────────────────────────
    def hline(y, color, dash, label, row):
        fig.add_hline(y=y, line=dict(color=color, width=1, dash=dash),
                      annotation_text=label, annotation_font_size=9,
                      annotation_font_color=color, row=row, col=1)

    hline(0, 'black', 'solid', '', 1)
    hline(PUTT_FORWARD_STROKE_THRESHOLD, C_FS, 'dash', f'FS thresh {PUTT_FORWARD_STROKE_THRESHOLD}', 1)
    hline(PUTT_SETUP_ROT_MAG_CEILING,    C_SETUP, 'dot', f'rotMag ceiling {PUTT_SETUP_ROT_MAG_CEILING}', 1)

    # ── Valid orientation bands (row 2) ────────────────────────────────────
    fig.add_hrect(y0=PUTT_PITCH_MIN_DEG, y1=PUTT_PITCH_MAX_DEG,
                  fillcolor='seagreen', opacity=0.08, line_width=0, row=2, col=1)
    fig.add_hrect(y0=PUTT_ROLL_MIN_DEG, y1=PUTT_ROLL_MAX_DEG,
                  fillcolor='darkorchid', opacity=0.06, line_width=0, row=2, col=1)

    # ── Event annotations ─────────────────────────────────────────────────
    shapes = []
    annotations = []

    def vline(x, color, dash, width, rows=None):
        if rows is None:
            rows = (1, 2, 3) if raw_rows else (1, 2)
        for row_n in rows:
            fig.add_shape(type='line', x0=x, x1=x, xref='x',
                          yref=f'y{row_n if row_n>1 else ""}',
                          line=dict(color=color, width=width, dash=dash),
                          layer='above', row=row_n, col=1)

    def ann(x, y, text, color, row, ax=0, ay=-30, size=9):
        yref = 'y' if row == 1 else f'y{row}'
        annotations.append(dict(x=x, y=y, xref='x', yref=yref, text=text,
                                font=dict(color=color, size=size), showarrow=True,
                                arrowcolor=color, arrowwidth=1, arrowsize=0.8,
                                ax=ax, ay=ay, bgcolor='white', bordercolor=color,
                                borderwidth=1, opacity=0.9))

    # Group events by attempt (sequences ending in a reset)
    attempts = []
    cur = []
    for e in events:
        cur.append(e)
        if e['kind'] == 'reset':
            if any(x['kind'] == 'qualified' for x in cur):
                attempts.append(cur)
            cur = []
    if cur and any(x['kind'] == 'qualified' for x in cur):
        attempts.append(cur)

    for attempt in attempts:
        is_detected = any(e['kind'] == 'detected' for e in attempt)
        color = C_DETECT if is_detected else C_INVALID
        ev = {}
        for e in attempt:
            ev.setdefault(e['kind'], []).append(e)

        r = lambda e: e['t'] - t0

        # Setup span: shade from first stable sample all the way to backstroke start (or reset)
        # Only draw for attempts that actually reached qualified — filters out sub-threshold flickers
        if ev.get('setup_start') and ev.get('qualified'):
            s = r(ev['setup_start'][0])
            if ev.get('bs_start'):
                end_e = ev['bs_start'][0]
            elif ev.get('reset'):
                end_e = ev['reset'][-1]
            else:
                end_e = attempt[-1]
            e_end = r(end_e)
            fig.add_vrect(x0=s, x1=e_end, fillcolor=C_SETUP, opacity=0.15,
                          line_width=0, layer='below', row='all', col=1)
            # Label at the qualified moment so it's always visible regardless of band width
            q_x = r(ev['qualified'][0])
            annotations.append(dict(x=q_x, y=1, xref='x', yref='y domain',
                                    text='SETUP', font=dict(color=C_SETUP, size=9, family='monospace'),
                                    showarrow=False, yanchor='top', bgcolor='white',
                                    bordercolor=C_SETUP, borderwidth=1, opacity=0.9))

        # Detected (confirmed = swing + contact, unconfirmed = swing only)
        for e in ev.get('detected', []):
            x = r(e)
            # find matching confirmed putt by fs_peak proximity
            fp_events = ev.get('fs_peak', [])
            fp_t      = fp_events[0]['t'] if fp_events else None
            is_confirmed = any(
                abs(c['t'] - fp_t) < 0.001 for c in confirmed_putts
            ) if fp_t else False
            c_color = C_DETECT if is_confirmed else 'gray'
            c_label = 'STROKE' if is_confirmed else 'NO CONTACT'
            vline(x, c_color, 'solid', 2.5)
            ann(x, -1.5, f"{c_label}<br>ratio={e['ratio']:.2f}", c_color, 1, ay=40)

        # BS peak
        for e in ev.get('bs_peak', []):
            x = r(e)
            vline(x, C_BS, 'dot', 1, rows=(1,))
            ann(x, e['rot_y'], f"BS peak<br>{e['rot_y']:.2f}", C_BS, 1, ay=-35)

        # FS start
        for e in ev.get('fs_start', []):
            x = r(e)
            vline(x, C_FS, 'dot', 1, rows=(1,))

        # FS peak
        for e in ev.get('fs_peak', []):
            x = r(e)
            rat_ok = e.get('rat_ok', False)
            ratio  = e.get('ratio', 0)
            label  = f"FS peak<br>{e['rot_y']:.2f}<br>ratio={ratio:.2f} {'OK' if rat_ok else 'FAIL'}"
            vline(x, color, 'dash', 1.2, rows=(1,))
            ann(x, e['rot_y'], label, color, 1, ay=35)

        # BS invalid
        for e in ev.get('bs_invalid', []):
            x = r(e)
            note = 'rotX/Z dom' if not e.get('dominant') else 'rotZ too high'
            ann(x, 0.5, f"BS FAIL<br>{note}", C_INVALID, 1, ay=-25, size=8)


    # ── Impact detection annotations (raw Z row only) ─────────────────────────
    if raw_rows:
        raw_row = 4

        # valid baseline bounds
        fig.add_hrect(y0=IMPACT_BASELINE_MIN, y1=IMPACT_BASELINE_MAX,
                      fillcolor='limegreen', opacity=0.06, line_width=0,
                      row=raw_row, col=1)
        fig.add_hline(y=IMPACT_BASELINE_MIN, line=dict(color='limegreen', width=1, dash='dot'),
                      annotation_text=f'baseline min {IMPACT_BASELINE_MIN}',
                      annotation_font_size=8, annotation_font_color='limegreen',
                      row=raw_row, col=1)
        fig.add_hline(y=IMPACT_BASELINE_MAX, line=dict(color='limegreen', width=1, dash='dot'),
                      annotation_text=f'baseline max {IMPACT_BASELINE_MAX}',
                      annotation_font_size=8, annotation_font_color='limegreen',
                      row=raw_row, col=1)

        # stable windows
        stable_wins = get_stable_windows(raw_rows)
        for sw_start, sw_end in stable_wins:
            fig.add_vrect(x0=sw_start - t0, x1=sw_end - t0,
                          fillcolor='limegreen', opacity=0.12,
                          line_width=0, layer='below', row=raw_row, col=1)

        impacts = run_impact_detection(raw_rows)
        for imp in impacts:
            bt = imp['bump_t']   - t0
            tt = imp['trough_t'] - t0
            pt = imp['peak_t']   - t0
            st = imp['settle_t'] - t0
            bl = imp['baseline']
            # shade full impulse window
            fig.add_vrect(x0=bt, x1=st, fillcolor='crimson', opacity=0.10,
                          line_width=0, layer='below', row=raw_row, col=1)
            # contact (bump)
            vline(bt, 'limegreen',  'solid', 1.5, rows=(raw_row,))
            # trough
            vline(tt, 'steelblue',  'dash',  1.2, rows=(raw_row,))
            # peak
            vline(pt, 'darkorange', 'dash',  1.2, rows=(raw_row,))
            # settle
            vline(st, 'gray',       'dot',   1.0, rows=(raw_row,))
            # label at contact
            annotations.append(dict(
                x=bt, y=bl + 0.38, xref='x', yref=f'y{raw_row}',
                text=f'CONTACT<br>bl={bl:.3f}',
                font=dict(color='crimson', size=8, family='monospace'),
                showarrow=True, arrowcolor='crimson', arrowwidth=1,
                arrowsize=0.7, ax=0, ay=-28,
                bgcolor='white', bordercolor='crimson', borderwidth=1, opacity=0.9,
            ))

    # Legend entries for shapes (shapes don't appear in plotly legend automatically)
    legend_traces = [
        ('Setup window (stable + in range)', C_SETUP,   'solid',  8,   True),
        ('DETECTED',                          C_DETECT,  'solid',  3,   False),
        ('BS peak velocity',                  C_BS,      'dot',    1.5, False),
        ('BS → FS transition',                C_FS,      'dot',    1.5, False),
        ('FS peak',                           C_INVALID, 'dash',   1.5, False),
        ('BS invalid shape',                  C_INVALID, 'solid',  1,   False),
    ]
    for label, color, dash, width, filled in legend_traces:
        if filled:
            fig.add_trace(go.Scatter(
                x=[None], y=[None], mode='markers',
                marker=dict(symbol='square', size=12, color=color, opacity=0.4),
                name=label, showlegend=True), row=1, col=1)
        else:
            fig.add_trace(go.Scatter(
                x=[None], y=[None], mode='lines',
                line=dict(color=color, width=width, dash=dash),
                name=label, showlegend=True), row=1, col=1)

    fig.update_layout(
        title=dict(text=title, font=dict(size=13)),
        height=900,
        hovermode='x unified',
        annotations=list(fig.layout.annotations) + annotations,
        legend=dict(orientation='h', yanchor='bottom', y=1.02, xanchor='left', x=0, font=dict(size=10)),
        margin=dict(l=60, r=40, t=100, b=50),
    )
    fig.update_xaxes(title_text='Time (s)', row=n_rows, col=1)
    fig.update_yaxes(title_text='rad/s', row=1, col=1)
    fig.update_yaxes(title_text='°',     row=2, col=1)
    fig.update_yaxes(title_text='G',     row=3, col=1)
    if raw_rows:
        fig.update_yaxes(title_text='G', row=4, col=1)
    fig.update_xaxes(showspikes=True, spikemode='across', spikesnap='cursor',
                     showticklabels=True, tickmode='auto', nticks=20)

    out_path = os.path.join(out_dir, stem + '.html')
    fig.write_html(out_path, include_plotlyjs='cdn')
    print(f'  Saved: {out_path}')
    return out_path


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    if args:
        files = args
    else:
        files = (sorted(glob.glob(os.path.join(script_dir, 'motion_test_*.csv'))) +
                 sorted(glob.glob(os.path.join(script_dir, 'putt_event_*.csv'))) +
                 sorted(glob.glob(os.path.join(script_dir, 'putt_fail_*.csv'))))
    print(f'Generating interactive HTML for {len(files)} file(s)...')
    for f in files:
        plot_file(f, script_dir)
    print('Done.')


if __name__ == '__main__':
    main()
