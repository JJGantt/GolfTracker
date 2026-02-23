"""
Visualize full-swing detection events for all motion_test CSVs in this directory.
Stitches all recordings into a single timeline (1-second gap between files).
Outputs one interactive HTML file.

Layout (3 subplots, shared x-axis — no raw accel since we don't have 800 Hz data):
  1. RotX / RotY / RotZ / RotMag
  2. Pitch / Roll  (°)
  3. UserAccel X/Y/Z / UserAccelMag

State machine:
  idle → accumulating → qualified
  Leave setup: rotMag > ceiling (no axis check) → inBackstroke
  inBackstroke: track peak rotMag; wait for rotZ < -ceiling → inBackstrokeTop
  inBackstrokeTop: continue tracking peak rotMag; wait for rotZ ≥ 0
    → bs top: record bs_peak_rot_mag, transition to inForwardStroke
  inForwardStroke: track rotMag peak; when ≥ ratio_min × bs_peak and fallen back → ratio check
  postImpact: wait for rotX > 0, then rotX ≤ 0 → detected

Usage:
    python3 visualize.py          # stitches all motion_test_*.csv → stitched.html
"""

import os, sys, glob, math
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# ── Import shared helpers + orientation constants from putts_samples ─────────
_HERE  = os.path.dirname(os.path.abspath(__file__))
_PUTTS = os.path.join(_HERE, '..', 'putts_samples')
sys.path.insert(0, os.path.abspath(_PUTTS))

from detect import (
    parse_csv, _deg, _rad,
    PUTT_PITCH_MIN_DEG, PUTT_PITCH_MAX_DEG,
    PUTT_ROLL_MIN_DEG,  PUTT_ROLL_MAX_DEG,
    SAMPLE_RATE_HZ,
)

# ── Detection parameters ──────────────────────────────────────────────────────
SWING_SETUP_ROT_MAG_CEILING  = 1.00  # max rotMag during setup; also -threshold for rotZ
SWING_MIN_DURATION_S         = 0.20  # min setup quiet duration (s)
SWING_BS_MIN_DURATION_S      = 0.50  # min time from leaving setup to BS top
SWING_FS_ROTMAG_RATIO_MIN    = 2.0   # min FS rotMag peak / BS rotMag peak
SWING_FS_ROTMAG_RATIO_MAX    = 8.0   # max FS rotMag peak / BS rotMag peak

# ── Colours ───────────────────────────────────────────────────────────────────
C_SETUP      = 'green'
C_BS         = 'royalblue'
C_FS         = 'orange'
C_POSTIMPACT = 'mediumpurple'
C_DETECT     = 'crimson'
C_INVALID    = 'tomato'
C_SEP        = 'slategray'

GAP_S = 1.0   # synthetic gap between stitched files (seconds)


# ── Instrumented detection ────────────────────────────────────────────────────

def run_instrumented(rows):
    """
    State machine:
      idle → accumulating → qualified
      Leave setup: rotMag > ceiling (no axis check) → inBackstroke
      inBackstroke: track peak rotMag; wait for rotZ < -ceiling → inBackstrokeTop
      inBackstrokeTop: continue tracking peak rotMag; wait for rotZ ≥ 0
        → bs_top: bs_peak_rot_mag = max rotMag seen from setup exit to now
        → inForwardStroke
      inForwardStroke: track rotMag peak; when peaked ≥ ratio_min × bs_peak
                       and fallen back to ≤ bs_peak → ratio check → postImpact
      postImpact: wait for rotX > 0, then rotX ≤ 0 → detected
    """
    pitch_min_rad = _rad(PUTT_PITCH_MIN_DEG)
    pitch_max_rad = _rad(PUTT_PITCH_MAX_DEG)
    roll_min_rad  = _rad(PUTT_ROLL_MIN_DEG)
    roll_max_rad  = _rad(PUTT_ROLL_MAX_DEG)

    state             = 'idle'
    stable_start_time = None

    bs_exit_setup_t    = None  # time we left setup (for BS duration check)
    bs_peak_rot_mag    = 0.0   # max rotMag from setup exit → bs top
    bs_peak_rot_mag_t  = None  # time of that peak
    fs_peak_rot_mag    = 0.0
    fs_peak_rot_mag_t  = None
    rot_x_was_positive = False

    events = []

    def evt(kind, t, **kw):
        events.append({'kind': kind, 't': t, **kw})

    def reset_to_idle(t, reason=''):
        nonlocal state, stable_start_time
        nonlocal bs_exit_setup_t, bs_peak_rot_mag, bs_peak_rot_mag_t
        nonlocal fs_peak_rot_mag, fs_peak_rot_mag_t, rot_x_was_positive
        state              = 'idle'
        stable_start_time  = None
        bs_exit_setup_t    = None
        bs_peak_rot_mag    = 0.0
        bs_peak_rot_mag_t  = None
        fs_peak_rot_mag    = 0.0
        fs_peak_rot_mag_t  = None
        rot_x_was_positive = False
        evt('reset', t, reason=reason)

    for row in rows:
        t       = row['sensor_time']
        rot_x   = row['rot_x']; rot_y = row['rot_y']; rot_z = row['rot_z']
        pitch   = row['pitch']; roll  = row['roll']
        rot_mag = math.sqrt(rot_x**2 + rot_y**2 + rot_z**2)

        in_bounds     = (pitch_min_rad <= pitch <= pitch_max_rad and
                         roll_min_rad  <= roll  <= roll_max_rad)
        under_ceiling = rot_mag <= SWING_SETUP_ROT_MAG_CEILING

        # ── idle ──────────────────────────────────────────────────────────────
        if state == 'idle':
            if in_bounds and under_ceiling:
                stable_start_time = t
                state = 'accumulating'
                evt('setup_start', t)

        # ── accumulating ──────────────────────────────────────────────────────
        elif state == 'accumulating':
            if not in_bounds:
                reset_to_idle(t, 'out_of_range'); continue
            if not under_ceiling:
                reset_to_idle(t, 'rotmag'); continue
            if t - stable_start_time >= SWING_MIN_DURATION_S:
                state = 'qualified'
                evt('qualified', t, duration=t - stable_start_time)

        # ── qualified ─────────────────────────────────────────────────────────
        elif state == 'qualified':
            if not in_bounds:
                reset_to_idle(t, 'out_of_bounds'); continue
            if not under_ceiling:
                # Leave setup when rotMag passes ceiling — no axis check
                bs_exit_setup_t   = t
                bs_peak_rot_mag   = rot_mag
                bs_peak_rot_mag_t = t
                state = 'inBackstroke'
                evt('bs_exit_setup', t, rot_mag=rot_mag)

        # ── inBackstroke ──────────────────────────────────────────────────────
        elif state == 'inBackstroke':
            # Always watching for setup — if stable conditions return, treat it as a
            # new setup and let the normal idle→accumulating→qualified flow handle it.
            if in_bounds and under_ceiling:
                reset_to_idle(t, 'setup_in_backstroke'); continue
            if rot_mag > bs_peak_rot_mag:
                bs_peak_rot_mag   = rot_mag
                bs_peak_rot_mag_t = t
            # Wait for rotZ to pass below -ceiling
            if rot_z < -SWING_SETUP_ROT_MAG_CEILING:
                state = 'inBackstrokeTop'
                evt('bs_rot_z_neg', t, rot_z=rot_z)

        # ── inBackstrokeTop ───────────────────────────────────────────────────
        elif state == 'inBackstrokeTop':
            if in_bounds and under_ceiling:
                reset_to_idle(t, 'setup_in_backstroke_top'); continue
            if rot_mag > bs_peak_rot_mag:
                bs_peak_rot_mag   = rot_mag
                bs_peak_rot_mag_t = t
            # Wait for rotZ to cross 0 from negative → top of backswing
            if rot_z >= 0:
                bs_duration = t - bs_exit_setup_t if bs_exit_setup_t is not None else 0
                dur_ok = bs_duration >= SWING_BS_MIN_DURATION_S
                evt('bs_top', t, bs_peak_rot_mag=bs_peak_rot_mag,
                    bs_peak_t=bs_peak_rot_mag_t, bs_duration=bs_duration, dur_ok=dur_ok)
                evt('bs_peak', bs_peak_rot_mag_t,
                    rot_mag=bs_peak_rot_mag, dur_ok=dur_ok)
                if dur_ok:
                    fs_peak_rot_mag   = rot_mag
                    fs_peak_rot_mag_t = t
                    state = 'inForwardStroke'
                else:
                    reset_to_idle(t, 'bs_too_short'); continue

        # ── inForwardStroke ───────────────────────────────────────────────────
        elif state == 'inForwardStroke':
            if in_bounds and under_ceiling:
                reset_to_idle(t, 'setup_in_forward_stroke'); continue
            if rot_mag > fs_peak_rot_mag:
                fs_peak_rot_mag   = rot_mag
                fs_peak_rot_mag_t = t

            if (fs_peak_rot_mag >= bs_peak_rot_mag * SWING_FS_ROTMAG_RATIO_MIN and
                    rot_mag <= bs_peak_rot_mag):
                ratio    = fs_peak_rot_mag / bs_peak_rot_mag
                ratio_ok = SWING_FS_ROTMAG_RATIO_MIN <= ratio <= SWING_FS_ROTMAG_RATIO_MAX
                evt('fs_peak_rotmag', fs_peak_rot_mag_t,
                    rot_mag=fs_peak_rot_mag, bs_rot_mag=bs_peak_rot_mag,
                    ratio=ratio, ratio_ok=ratio_ok)
                if ratio_ok:
                    rot_x_was_positive = rot_x > 0
                    state = 'postImpact'
                    evt('post_impact_start', t)
                else:
                    reset_to_idle(t, 'rotmag_ratio_failed'); continue

        # ── postImpact ────────────────────────────────────────────────────────
        elif state == 'postImpact':
            if in_bounds and under_ceiling:
                reset_to_idle(t, 'setup_in_post_impact'); continue
            if rot_x > 0:
                rot_x_was_positive = True
            if rot_x_was_positive and rot_x <= 0:
                evt('detected', t)
                reset_to_idle(t, 'detected')

    return events


# ── Stitch files ──────────────────────────────────────────────────────────────

def stitch_files(paths):
    all_rows    = []
    separators  = []
    file_ranges = []
    t_offset    = 0.0
    sample_dt   = 1.0 / SAMPLE_RATE_HZ

    for path in paths:
        rows, _ = parse_csv(path)
        if not rows:
            continue
        stem = os.path.basename(path).replace('.csv', '')
        for i, row in enumerate(rows):
            row['sensor_time'] = t_offset + i * sample_dt
        t_start = rows[0]['sensor_time']
        t_end   = rows[-1]['sensor_time']
        if all_rows:
            separators.append((all_rows[-1]['sensor_time'], t_start, stem))
        file_ranges.append((t_start, t_end, stem))
        all_rows.extend(rows)
        t_offset = t_end + GAP_S

    return all_rows, separators, file_ranges


# ── Main plot ─────────────────────────────────────────────────────────────────

def plot_stitched(paths, out_path):
    all_rows, separators, file_ranges = stitch_files(paths)
    events = run_instrumented(all_rows)

    t0      = all_rows[0]['sensor_time']
    trel    = [r['sensor_time'] - t0 for r in all_rows]
    rot_x   = [r['rot_x']  for r in all_rows]
    rot_y   = [r['rot_y']  for r in all_rows]
    rot_z   = [r['rot_z']  for r in all_rows]
    rot_mag = [math.sqrt(r['rot_x']**2 + r['rot_y']**2 + r['rot_z']**2) for r in all_rows]
    ua_x    = [r['ua_x']   for r in all_rows]
    ua_y    = [r['ua_y']   for r in all_rows]
    ua_z    = [r['ua_z']   for r in all_rows]
    ua_mag  = [r['ua_mag'] for r in all_rows]
    pitch   = [_deg(r['pitch']) for r in all_rows]
    roll    = [_deg(r['roll'])  for r in all_rows]

    detected_count = sum(1 for e in events if e['kind'] == 'detected')
    attempt_count  = sum(1 for e in events if e['kind'] == 'qualified')
    title = (f"Irregular Samples (stitched, {len(paths)} files)  —  "
             f"{detected_count} detections / {attempt_count} setups qualified  "
             f"|  ceiling={SWING_SETUP_ROT_MAG_CEILING} setupDur={SWING_MIN_DURATION_S}s  "
             f"bsDur≥{SWING_BS_MIN_DURATION_S}s  ratio [{SWING_FS_ROTMAG_RATIO_MIN}–{SWING_FS_ROTMAG_RATIO_MAX}]")

    fig = make_subplots(
        rows=3, cols=1, shared_xaxes=True, vertical_spacing=0.05,
        subplot_titles=('RotX / RotY / RotZ / RotMag', 'Pitch / Roll  (°)', 'UserAccel X/Y/Z  (G)'),
        row_heights=[0.45, 0.25, 0.30],
    )

    # ── Signal traces ─────────────────────────────────────────────────────────
    fig.add_trace(go.Scatter(x=trel, y=rot_y, name='RotY',
                             line=dict(color='cornflowerblue', width=1), opacity=0.6,
                             hovertemplate='t=%{x:.3f}s<br>RotY=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=rot_z, name='RotZ',
                             line=dict(color='rosybrown', width=1.5),
                             hovertemplate='t=%{x:.3f}s<br>RotZ=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=rot_x, name='RotX',
                             line=dict(color='royalblue', width=1), opacity=0.6,
                             hovertemplate='t=%{x:.3f}s<br>RotX=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=rot_mag, name='RotMag',
                             line=dict(color='black', width=1.8),
                             hovertemplate='t=%{x:.3f}s<br>RotMag=%{y:.3f}'), row=1, col=1)

    fig.add_trace(go.Scatter(x=trel, y=pitch, name='Pitch',
                             line=dict(color='seagreen', width=1.2),
                             hovertemplate='t=%{x:.3f}s<br>Pitch=%{y:.1f}°'), row=2, col=1)
    fig.add_trace(go.Scatter(x=trel, y=roll, name='Roll',
                             line=dict(color='darkorchid', width=1.2),
                             hovertemplate='t=%{x:.3f}s<br>Roll=%{y:.1f}°'), row=2, col=1)

    fig.add_trace(go.Scatter(x=trel, y=ua_x, name='UserAccelX',
                             line=dict(color='coral', width=1), opacity=0.45,
                             hovertemplate='t=%{x:.3f}s<br>UserAccelX=%{y:.3f}'), row=3, col=1)
    fig.add_trace(go.Scatter(x=trel, y=ua_y, name='UserAccelY',
                             line=dict(color='mediumseagreen', width=1), opacity=0.45,
                             hovertemplate='t=%{x:.3f}s<br>UserAccelY=%{y:.3f}'), row=3, col=1)
    fig.add_trace(go.Scatter(x=trel, y=ua_z, name='UserAccelZ',
                             line=dict(color='mediumslateblue', width=1), opacity=0.45,
                             hovertemplate='t=%{x:.3f}s<br>UserAccelZ=%{y:.3f}'), row=3, col=1)
    fig.add_trace(go.Scatter(x=trel, y=ua_mag, name='UserAccelMag',
                             line=dict(color='black', width=1.8),
                             hovertemplate='t=%{x:.3f}s<br>UserAccelMag=%{y:.3f}'), row=3, col=1)

    # ── Reference lines (row 1) ───────────────────────────────────────────────
    fig.add_hline(y=0, line=dict(color='black', width=1, dash='solid'), row=1, col=1)
    fig.add_hline(y=SWING_SETUP_ROT_MAG_CEILING,
                  line=dict(color=C_SETUP, width=1, dash='dot'),
                  annotation_text=f'setup ceiling {SWING_SETUP_ROT_MAG_CEILING}',
                  annotation_font_size=9, annotation_font_color=C_SETUP, row=1, col=1)
    fig.add_hline(y=-SWING_SETUP_ROT_MAG_CEILING,
                  line=dict(color='rosybrown', width=1, dash='dot'),
                  annotation_text=f'rotZ threshold -{SWING_SETUP_ROT_MAG_CEILING}',
                  annotation_font_size=9, annotation_font_color='rosybrown', row=1, col=1)

    # ── Orientation bands (row 2) ─────────────────────────────────────────────
    fig.add_hrect(y0=PUTT_PITCH_MIN_DEG, y1=PUTT_PITCH_MAX_DEG,
                  fillcolor='seagreen', opacity=0.08, line_width=0, row=2, col=1)
    fig.add_hrect(y0=PUTT_ROLL_MIN_DEG, y1=PUTT_ROLL_MAX_DEG,
                  fillcolor='darkorchid', opacity=0.06, line_width=0, row=2, col=1)

    annotations = []

    def vline(x, color, dash, width, rows=(1, 2, 3)):
        for row_n in rows:
            yref = 'y' if row_n == 1 else f'y{row_n}'
            fig.add_shape(type='line', x0=x, x1=x, xref='x', yref=yref,
                          line=dict(color=color, width=width, dash=dash),
                          layer='above', row=row_n, col=1)

    def ann(x, y, text, color, row, ax=0, ay=-30, size=9):
        yref = 'y' if row == 1 else f'y{row}'
        annotations.append(dict(x=x, y=y, xref='x', yref=yref, text=text,
                                font=dict(color=color, size=size), showarrow=True,
                                arrowcolor=color, arrowwidth=1, arrowsize=0.8,
                                ax=ax, ay=ay, bgcolor='white', bordercolor=color,
                                borderwidth=1, opacity=0.9))

    # ── File shading + labels ─────────────────────────────────────────────────
    for i, (fs_t, fe_t, stem) in enumerate(file_ranges):
        shade = 'rgba(200,200,200,0.10)' if i % 2 == 0 else 'rgba(220,220,255,0.10)'
        fig.add_vrect(x0=fs_t - t0, x1=fe_t - t0, fillcolor=shade,
                      line_width=0, layer='below', row='all', col=1)
        mid = (fs_t + fe_t) / 2.0 - t0
        annotations.append(dict(
            x=mid, y=1.0, xref='x', yref='paper',
            text=f'<b>{stem}</b>', font=dict(color=C_SEP, size=9),
            showarrow=False, yanchor='bottom', xanchor='center',
            bgcolor='rgba(255,255,255,0.7)', bordercolor=C_SEP,
            borderwidth=1, opacity=0.85,
        ))

    for sep_start, sep_end, _ in separators:
        fig.add_vrect(x0=sep_start - t0, x1=sep_end - t0,
                      fillcolor='rgba(150,150,150,0.15)', line_width=0,
                      layer='below', row='all', col=1)

    # ── Attempt grouping ──────────────────────────────────────────────────────
    cur_attempt  = []
    all_attempts = []
    for e in events:
        cur_attempt.append(e)
        if e['kind'] == 'reset':
            if any(x['kind'] == 'qualified' for x in cur_attempt):
                all_attempts.append(cur_attempt)
            cur_attempt = []
    if cur_attempt and any(x['kind'] == 'qualified' for x in cur_attempt):
        all_attempts.append(cur_attempt)

    for attempt in all_attempts:
        is_detected = any(e['kind'] == 'detected' for e in attempt)
        ev = {}
        for e in attempt:
            ev.setdefault(e['kind'], []).append(e)

        r = lambda e: e['t'] - t0

        # Setup span (setup_start → bs_exit_setup or reset)
        if ev.get('setup_start') and ev.get('qualified'):
            s     = r(ev['setup_start'][0])
            end_e = (ev.get('bs_exit_setup') or ev.get('reset') or [attempt[-1]])[0]
            fig.add_vrect(x0=s, x1=r(end_e), fillcolor=C_SETUP, opacity=0.15,
                          line_width=0, layer='below', row='all', col=1)
            annotations.append(dict(
                x=r(ev['qualified'][0]), y=1, xref='x', yref='y domain',
                text='SETUP', font=dict(color=C_SETUP, size=9, family='monospace'),
                showarrow=False, yanchor='top', bgcolor='white',
                bordercolor=C_SETUP, borderwidth=1, opacity=0.9))

        # BS exit setup
        for e in ev.get('bs_exit_setup', []):
            vline(r(e), C_BS, 'dot', 1, rows=(1,))

        # rotZ hits -threshold
        for e in ev.get('bs_rot_z_neg', []):
            vline(r(e), 'rosybrown', 'dot', 1, rows=(1,))

        # BS peak rotMag (annotated at its actual position in time)
        for e in ev.get('bs_peak', []):
            x     = r(e)
            dur_ok = e.get('dur_ok', True)
            c     = C_BS if dur_ok else C_INVALID
            vline(x, c, 'dash', 1.2, rows=(1,))
            ann(x, e['rot_mag'], f"BS peak<br>{e['rot_mag']:.2f}", c, 1, ay=-45)

        # BS top (rotZ crosses 0) — just a line, duration pass/fail shown via colour
        for e in ev.get('bs_top', []):
            x      = r(e)
            dur_ok = e.get('dur_ok', True)
            c      = C_BS if dur_ok else C_INVALID
            vline(x, c, 'solid', 1.5, rows=(1,))
            ann(x, 0, f"BS top<br>dur={e['bs_duration']:.2f}s {'✓' if dur_ok else '✗'}", c, 1, ay=30)

        # FS rotMag peak
        for e in ev.get('fs_peak_rotmag', []):
            x        = r(e)
            ratio_ok = e.get('ratio_ok', False)
            c        = C_FS if ratio_ok else C_INVALID
            label    = (f"FS rotMag peak<br>{e['rot_mag']:.2f}<br>"
                        f"ratio={e['ratio']:.2f} {'OK' if ratio_ok else 'FAIL'}")
            vline(x, c, 'dash', 1.2, rows=(1,))
            ann(x, e['rot_mag'], label, c, 1, ay=-40)

        # Post-impact start
        for e in ev.get('post_impact_start', []):
            vline(r(e), C_POSTIMPACT, 'dot', 1, rows=(1,))

        # Detection
        for e in ev.get('detected', []):
            x = r(e)
            vline(x, C_DETECT, 'solid', 2.5)
            ann(x, 2.0, 'STROKE', C_DETECT, 1, ay=-30)

    # ── Legend ────────────────────────────────────────────────────────────────
    legend_traces = [
        ('Setup window',         C_SETUP,      'solid', 8,   True),
        ('STROKE detected',      C_DETECT,     'solid', 3,   False),
        ('BS exit setup',        C_BS,         'dot',   1.5, False),
        ('rotZ hits -threshold', 'rosybrown',  'dot',   1.5, False),
        ('BS peak rotMag',       C_BS,         'dash',  1.5, False),
        ('BS top (rotZ→0)',      C_BS,         'solid', 1.5, False),
        ('FS rotMag peak',       C_FS,         'dash',  1.5, False),
        ('Post-impact start',    C_POSTIMPACT, 'dot',   1.5, False),
        ('Condition fail',       C_INVALID,    'solid', 1.5, False),
    ]
    for label, c, dash, width, filled in legend_traces:
        if filled:
            fig.add_trace(go.Scatter(x=[None], y=[None], mode='markers',
                                     marker=dict(symbol='square', size=12, color=c, opacity=0.4),
                                     name=label, showlegend=True), row=1, col=1)
        else:
            fig.add_trace(go.Scatter(x=[None], y=[None], mode='lines',
                                     line=dict(color=c, width=width, dash=dash),
                                     name=label, showlegend=True), row=1, col=1)

    fig.update_layout(
        title=dict(text=title, font=dict(size=12)),
        height=900,
        hovermode='x unified',
        annotations=list(fig.layout.annotations) + annotations,
        legend=dict(orientation='h', yanchor='bottom', y=1.02, xanchor='left', x=0, font=dict(size=10)),
        margin=dict(l=60, r=40, t=120, b=50),
    )
    fig.update_xaxes(title_text='Time (s)', row=3, col=1)
    fig.update_yaxes(title_text='rad/s', row=1, col=1)
    fig.update_yaxes(title_text='°',     row=2, col=1)
    fig.update_yaxes(title_text='G',     row=3, col=1)
    fig.update_xaxes(showspikes=True, spikemode='across', spikesnap='cursor',
                     showticklabels=True, tickmode='auto', nticks=30)

    fig.write_html(out_path, include_plotlyjs='cdn')
    print(f'  Saved: {out_path}')


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    files = sorted(glob.glob(os.path.join(script_dir, 'motion_test_*.csv')))
    if not files:
        print('No motion_test_*.csv files found.')
        return
    print(f'Stitching {len(files)} file(s)...')
    for f in files:
        print(f'  {os.path.basename(f)}')
    out = os.path.join(script_dir, 'stitched.html')
    plot_stitched(files, out)
    print('Done.')


if __name__ == '__main__':
    main()
