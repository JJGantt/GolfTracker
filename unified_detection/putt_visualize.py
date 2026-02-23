"""
Unified putt detection — event-based approach.

Detects 3 event types INDEPENDENTLY (no state machine gating):
  1. Setup events   — stable orientation windows
  2. Backswing tops — rotMag valleys with rotZ directional gate
  3. Forward force  — prominent rotMag peaks with rotZ/rotX directional gates

Starting point: same logic as swing_visualize.py, to be tuned for putt signals.

Produces 1 HTML file:
  - putts.html

Usage:
    python unified_detection/putt_visualize.py     # from project root
"""

import os, sys, glob, math
import numpy as np
from scipy.signal import find_peaks
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# ── Import shared helpers from putts_samples ─────────────────────────────────
_HERE  = os.path.dirname(os.path.abspath(__file__))
_ROOT  = os.path.dirname(_HERE)
_PUTTS = os.path.join(_ROOT, 'putts_samples')
sys.path.insert(0, os.path.abspath(_PUTTS))

from detect import (
    parse_csv, _deg, _rad,
    PUTT_PITCH_MIN_DEG, PUTT_PITCH_MAX_DEG,
    PUTT_ROLL_MIN_DEG,  PUTT_ROLL_MAX_DEG,
    SAMPLE_RATE_HZ,
)

# ── Parameters ───────────────────────────────────────────────────────────────

# Setup detection
SETUP_PITCH_MIN_DEG = PUTT_PITCH_MIN_DEG   # -25
SETUP_PITCH_MAX_DEG = PUTT_PITCH_MAX_DEG   #   0
SETUP_ROLL_MIN_DEG  = PUTT_ROLL_MIN_DEG    #  85
SETUP_ROLL_MAX_DEG  = PUTT_ROLL_MAX_DEG    # 135
SETUP_MIN_DURATION_S = 0.20                 # min stable time to qualify
SETUP_ROT_MAG_CEILING = 1.00               # max rotMag during setup
SETUP_SPIKE_TOLERANCE_S = 0.06             # allow brief exceedances up to this duration

# Backswing top detection
BS_TOP_ROTMAG_MIN_ELEVATION = 0.5   # rotMag must have been at least this high before the valley
BS_TOP_VALLEY_MAX_ROTMAG    = 1.5   # valley rotMag must be below this
BS_TOP_MIN_DISTANCE_SAMPLES = 15    # min samples between detected valleys
BS_TOP_AREA_WINDOW_S        = 0.20  # window (seconds) before/after valley for area-under-curve

# Forward swing force detection
FS_ROTMAG_MIN_THRESHOLD = 2.0   # minimum rotMag to even consider as a peak
FS_MIN_PROMINENCE        = 1.0   # scipy prominence — peak must stand out this much
FS_MIN_DISTANCE_SAMPLES  = 15    # min samples between peaks
FS_AREA_WINDOW_S         = 0.20  # seconds before/after peak for area-under-curve

# Colours
C_SETUP   = 'green'
C_BS_TOP  = 'royalblue'
C_FS_PEAK = 'crimson'
C_SEP     = 'slategray'

GAP_S = 1.0  # synthetic gap between stitched files


# ═════════════════════════════════════════════════════════════════════════════
#  EVENT DETECTORS
# ═════════════════════════════════════════════════════════════════════════════

def detect_setups(rows):
    """
    Find setup windows: orientation in range AND rotMag under ceiling.
    Tolerates brief spikes (up to SETUP_SPIKE_TOLERANCE_S) without resetting.

    Returns list of dicts: {start_t, end_t, duration}
    """
    pitch_min = _rad(SETUP_PITCH_MIN_DEG)
    pitch_max = _rad(SETUP_PITCH_MAX_DEG)
    roll_min  = _rad(SETUP_ROLL_MIN_DEG)
    roll_max  = _rad(SETUP_ROLL_MAX_DEG)

    setups = []
    stable_start = None
    spike_start  = None  # when a brief exceedance began

    for row in rows:
        t     = row['sensor_time']
        rot_x = row['rot_x']; rot_y = row['rot_y']; rot_z = row['rot_z']
        pitch = row['pitch']; roll  = row['roll']
        rot_mag = math.sqrt(rot_x**2 + rot_y**2 + rot_z**2)

        in_bounds     = (pitch_min <= pitch <= pitch_max and
                         roll_min  <= roll  <= roll_max)
        under_ceiling = rot_mag <= SETUP_ROT_MAG_CEILING

        if in_bounds and under_ceiling:
            # Good sample — reset spike tracker
            spike_start = None
            if stable_start is None:
                stable_start = t
        elif in_bounds and not under_ceiling:
            # Orientation is fine but rotMag exceeded — start or continue spike
            if stable_start is not None:
                if spike_start is None:
                    spike_start = t
                elif t - spike_start > SETUP_SPIKE_TOLERANCE_S:
                    # Spike too long, end the setup window
                    duration = spike_start - stable_start
                    if duration >= SETUP_MIN_DURATION_S:
                        setups.append({'start_t': stable_start, 'end_t': spike_start, 'duration': duration})
                    stable_start = None
                    spike_start = None
            # If no stable_start, we're not in a setup — ignore
        else:
            # Out of orientation bounds — end any current setup
            if stable_start is not None:
                end_t = spike_start if spike_start is not None else t
                duration = end_t - stable_start
                if duration >= SETUP_MIN_DURATION_S:
                    setups.append({'start_t': stable_start, 'end_t': end_t, 'duration': duration})
                stable_start = None
                spike_start = None

    # Close any open setup at end of data
    if stable_start is not None:
        end_t = spike_start if spike_start is not None else rows[-1]['sensor_time']
        duration = end_t - stable_start
        if duration >= SETUP_MIN_DURATION_S:
            setups.append({'start_t': stable_start, 'end_t': end_t, 'duration': duration})

    return setups


def detect_backswing_tops(rows):
    """
    Find backswing top events: moments where rotMag reaches a local minimum
    (valley) after having been elevated.

    For each valley, computes the area under the curve (sum of values) for each
    rotation axis in a window before and after the valley.  This captures both
    direction (sign) and commitment (magnitude) of the motion on each side.

    Returns list of dicts:
        t, rot_mag, rot_x, rot_y, rot_z,
        area_before_{x,y,z}, area_after_{x,y,z}
    """
    if len(rows) < 3:
        return []

    times   = np.array([r['sensor_time'] for r in rows])
    rot_x   = np.array([r['rot_x'] for r in rows])
    rot_y   = np.array([r['rot_y'] for r in rows])
    rot_z   = np.array([r['rot_z'] for r in rows])
    rot_mag = np.sqrt(rot_x**2 + rot_y**2 + rot_z**2)

    # Find valleys in rotMag = peaks in -rotMag
    inverted = -rot_mag
    valley_indices, valley_props = find_peaks(
        inverted,
        distance=BS_TOP_MIN_DISTANCE_SAMPLES,
        prominence=0.15,  # valley must be at least 0.15 rad/s below surrounding peaks
    )

    events = []

    for idx in valley_indices:
        rm = rot_mag[idx]
        if rm > BS_TOP_VALLEY_MAX_ROTMAG:
            continue

        t_valley = times[idx]

        # Area under curve: use time-based window before and after valley
        before_mask = (times >= t_valley - BS_TOP_AREA_WINDOW_S) & (times < t_valley)
        after_mask  = (times > t_valley) & (times <= t_valley + BS_TOP_AREA_WINDOW_S)

        # Estimate local sample_dt from neighbors
        if idx > 0 and idx < len(times) - 1:
            local_dt = (times[idx + 1] - times[idx - 1]) / 2.0
        else:
            local_dt = 1.0 / SAMPLE_RATE_HZ

        areas = {}
        for axis_name, axis_arr in [('x', rot_x), ('y', rot_y), ('z', rot_z)]:
            areas[f'before_{axis_name}'] = float(np.sum(axis_arr[before_mask]) * local_dt)
            areas[f'after_{axis_name}']  = float(np.sum(axis_arr[after_mask]) * local_dt)

        # Directional gate: rotZ area must be below -0.1 before and above +0.1 after
        if areas['before_z'] >= -0.1 or areas['after_z'] <= 0.1:
            continue

        events.append({
            't': times[idx],
            'rot_mag': rm,
            'rot_x': float(rot_x[idx]),
            'rot_y': float(rot_y[idx]),
            'rot_z': float(rot_z[idx]),
            **{f'area_{k}': v for k, v in areas.items()},
        })

    return events


def detect_forward_swing_force(rows):
    """
    Find forward swing force peaks: prominent local maxima in rotMag.

    For each peak, computes the area under the curve for each rotation axis
    in a window before and after the peak.

    Returns list of dicts:
        t, rot_mag, rot_x, rot_y, rot_z,
        area_before_{x,y,z}, area_after_{x,y,z}
    """
    if len(rows) < 3:
        return []

    times   = np.array([r['sensor_time'] for r in rows])
    rot_x   = np.array([r['rot_x'] for r in rows])
    rot_y   = np.array([r['rot_y'] for r in rows])
    rot_z   = np.array([r['rot_z'] for r in rows])
    rot_mag = np.sqrt(rot_x**2 + rot_y**2 + rot_z**2)

    peak_indices, peak_props = find_peaks(
        rot_mag,
        prominence=FS_MIN_PROMINENCE,
        distance=FS_MIN_DISTANCE_SAMPLES,
    )

    events = []
    for idx in peak_indices:
        t_peak = times[idx]
        before_mask = (times >= t_peak - FS_AREA_WINDOW_S) & (times < t_peak)
        after_mask  = (times > t_peak) & (times <= t_peak + FS_AREA_WINDOW_S)

        if idx > 0 and idx < len(times) - 1:
            local_dt = (times[idx + 1] - times[idx - 1]) / 2.0
        else:
            local_dt = 1.0 / SAMPLE_RATE_HZ

        areas = {}
        for axis_name, axis_arr in [('x', rot_x), ('y', rot_y), ('z', rot_z)]:
            areas[f'before_{axis_name}'] = float(np.sum(axis_arr[before_mask]) * local_dt)
            areas[f'after_{axis_name}']  = float(np.sum(axis_arr[after_mask]) * local_dt)

        # Directional gate: rotZ positive before / negative after, rotX negative before
        if areas['before_z'] <= 0.1 or areas['after_z'] >= -0.1:
            continue
        if areas['before_x'] >= -0.1:
            continue

        events.append({
            't': times[idx],
            'rot_mag': float(rot_mag[idx]),
            'rot_x': float(rot_x[idx]),
            'rot_y': float(rot_y[idx]),
            'rot_z': float(rot_z[idx]),
            **{f'area_{k}': v for k, v in areas.items()},
        })

    return events


# ═════════════════════════════════════════════════════════════════════════════
#  STITCHING
# ═════════════════════════════════════════════════════════════════════════════

def _detect_sample_rate(rows):
    """Detect actual sample rate from sensor timestamps."""
    if len(rows) < 2:
        return SAMPLE_RATE_HZ
    # Use median of first 100 deltas to get robust estimate
    n = min(100, len(rows) - 1)
    deltas = [rows[i+1]['sensor_time'] - rows[i]['sensor_time'] for i in range(n)]
    deltas.sort()
    median_dt = deltas[n // 2]
    if median_dt > 0:
        return 1.0 / median_dt
    return SAMPLE_RATE_HZ


def stitch_files(paths):
    """Stitch multiple CSV files into one timeline with gaps between them.
    Preserves actual sample spacing from each file's timestamps."""
    all_rows    = []
    separators  = []
    file_ranges = []
    t_offset    = 0.0

    for path in paths:
        rows, old_format = parse_csv(path)
        if not rows:
            continue
        stem = os.path.basename(path).replace('.csv', '')

        if old_format:
            # Old format: parse_csv already set index-based times at SAMPLE_RATE_HZ
            # Shift to current offset
            base = rows[0]['sensor_time']
            for row in rows:
                row['sensor_time'] = t_offset + (row['sensor_time'] - base)
        else:
            # New format: real sensor timestamps — preserve actual spacing
            base = rows[0]['sensor_time']
            for row in rows:
                row['sensor_time'] = t_offset + (row['sensor_time'] - base)

        t_start = rows[0]['sensor_time']
        t_end   = rows[-1]['sensor_time']
        if all_rows:
            separators.append((all_rows[-1]['sensor_time'], t_start, stem))
        file_ranges.append((t_start, t_end, stem))
        all_rows.extend(rows)
        t_offset = t_end + GAP_S

    return all_rows, separators, file_ranges


# ═════════════════════════════════════════════════════════════════════════════
#  PLOTTING
# ═════════════════════════════════════════════════════════════════════════════

def plot_stitched(paths, out_path, sample_type_label):
    """Build a stitched Plotly HTML with all 3 independent event detectors annotated."""
    all_rows, separators, file_ranges = stitch_files(paths)
    if not all_rows:
        print(f'  No data for {sample_type_label}, skipping.')
        return

    # Run all 3 detectors independently
    setups    = detect_setups(all_rows)
    bs_tops   = detect_backswing_tops(all_rows)
    fs_peaks  = detect_forward_swing_force(all_rows)

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

    title = (f"<b>Unified Detection — {sample_type_label}</b>  ({len(paths)} files)  |  "
             f"{len(setups)} setups, {len(bs_tops)} BS tops, {len(fs_peaks)} FS peaks  |  "
             f"ceiling={SETUP_ROT_MAG_CEILING}")

    fig = make_subplots(
        rows=3, cols=1, shared_xaxes=True, vertical_spacing=0.05,
        subplot_titles=(
            'Rotation (rad/s) — RotX / RotY / RotZ / RotMag',
            'Orientation (deg) — Pitch / Roll',
            'User Acceleration (G) — X / Y / Z / Mag',
        ),
        row_heights=[0.45, 0.25, 0.30],
    )

    # ── Row 1: Rotation ──────────────────────────────────────────────────────
    fig.add_trace(go.Scatter(x=trel, y=rot_x, name='RotX',
                             line=dict(color='royalblue', width=1.2),
                             hovertemplate='t=%{x:.3f}s<br>RotX=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=rot_y, name='RotY',
                             line=dict(color='cornflowerblue', width=1.2),
                             hovertemplate='t=%{x:.3f}s<br>RotY=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=rot_z, name='RotZ',
                             line=dict(color='rosybrown', width=1.2),
                             hovertemplate='t=%{x:.3f}s<br>RotZ=%{y:.3f}'), row=1, col=1)
    fig.add_trace(go.Scatter(x=trel, y=rot_mag, name='RotMag',
                             line=dict(color='black', width=2),
                             hovertemplate='t=%{x:.3f}s<br>RotMag=%{y:.3f}'), row=1, col=1)

    # ── Row 2: Orientation ───────────────────────────────────────────────────
    fig.add_trace(go.Scatter(x=trel, y=pitch, name='Pitch',
                             line=dict(color='seagreen', width=1.2),
                             hovertemplate='t=%{x:.3f}s<br>Pitch=%{y:.1f}°'), row=2, col=1)
    fig.add_trace(go.Scatter(x=trel, y=roll, name='Roll',
                             line=dict(color='darkorchid', width=1.2),
                             hovertemplate='t=%{x:.3f}s<br>Roll=%{y:.1f}°'), row=2, col=1)

    # ── Row 3: User Acceleration ─────────────────────────────────────────────
    fig.add_trace(go.Scatter(x=trel, y=ua_x, name='UserAccelX',
                             line=dict(color='coral', width=1), opacity=0.5,
                             hovertemplate='t=%{x:.3f}s<br>UAx=%{y:.3f}'), row=3, col=1)
    fig.add_trace(go.Scatter(x=trel, y=ua_y, name='UserAccelY',
                             line=dict(color='mediumseagreen', width=1), opacity=0.5,
                             hovertemplate='t=%{x:.3f}s<br>UAy=%{y:.3f}'), row=3, col=1)
    fig.add_trace(go.Scatter(x=trel, y=ua_z, name='UserAccelZ',
                             line=dict(color='mediumslateblue', width=1), opacity=0.5,
                             hovertemplate='t=%{x:.3f}s<br>UAz=%{y:.3f}'), row=3, col=1)
    fig.add_trace(go.Scatter(x=trel, y=ua_mag, name='UserAccelMag',
                             line=dict(color='black', width=1.8),
                             hovertemplate='t=%{x:.3f}s<br>UAMag=%{y:.3f}'), row=3, col=1)

    # ── Reference lines ──────────────────────────────────────────────────────
    fig.add_hline(y=0, line=dict(color='black', width=0.5), row=1, col=1)
    fig.add_hline(y=SETUP_ROT_MAG_CEILING,
                  line=dict(color=C_SETUP, width=1, dash='dot'),
                  annotation_text=f'setup ceiling {SETUP_ROT_MAG_CEILING}',
                  annotation_font_size=9, annotation_font_color=C_SETUP,
                  row=1, col=1)
    fig.add_hline(y=FS_ROTMAG_MIN_THRESHOLD,
                  line=dict(color=C_FS_PEAK, width=1, dash='dot'),
                  annotation_text=f'FS min {FS_ROTMAG_MIN_THRESHOLD}',
                  annotation_font_size=9, annotation_font_color=C_FS_PEAK,
                  row=1, col=1)

    # ── Orientation valid-range bands (row 2) ────────────────────────────────
    fig.add_hrect(y0=SETUP_PITCH_MIN_DEG, y1=SETUP_PITCH_MAX_DEG,
                  fillcolor='seagreen', opacity=0.08, line_width=0, row=2, col=1)
    fig.add_hrect(y0=SETUP_ROLL_MIN_DEG, y1=SETUP_ROLL_MAX_DEG,
                  fillcolor='darkorchid', opacity=0.06, line_width=0, row=2, col=1)

    annotations = []

    def vline(x, color, dash, width, target_rows=(1,)):
        for row_n in target_rows:
            fig.add_shape(type='line', x0=x, x1=x, xref='x',
                          yref=f'y{row_n if row_n > 1 else ""}',
                          line=dict(color=color, width=width, dash=dash),
                          layer='above', row=row_n, col=1)

    def ann(x, y, text, color, row, ax=0, ay=-30, size=9):
        yref = 'y' if row == 1 else f'y{row}'
        annotations.append(dict(x=x, y=y, xref='x', yref=yref, text=text,
                                font=dict(color=color, size=size), showarrow=True,
                                arrowcolor=color, arrowwidth=1, arrowsize=0.8,
                                ax=ax, ay=ay, bgcolor='white', bordercolor=color,
                                borderwidth=1, opacity=0.9))

    # ── File shading + labels ────────────────────────────────────────────────
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

    # ── Annotate: Setup events (green bands on all rows) ─────────────────────
    for s in setups:
        x0 = s['start_t'] - t0
        x1 = s['end_t'] - t0
        fig.add_vrect(x0=x0, x1=x1, fillcolor=C_SETUP, opacity=0.15,
                      line_width=0, layer='below', row='all', col=1)
        # Label at midpoint on row 2 (orientation row)
        mid_x = (x0 + x1) / 2.0
        annotations.append(dict(
            x=mid_x, y=1, xref='x', yref='y2 domain',
            text=f'SETUP {s["duration"]:.2f}s',
            font=dict(color=C_SETUP, size=8, family='monospace'),
            showarrow=False, yanchor='top', bgcolor='white',
            bordercolor=C_SETUP, borderwidth=1, opacity=0.9))

    # ── Annotate: Backswing top events (vertical lines on row 1) ─────────────
    for i, bs in enumerate(bs_tops):
        x = bs['t'] - t0
        vline(x, C_BS_TOP, 'dash', 1.5, target_rows=(1,))
        label = (f"BS TOP  rotMag={bs['rot_mag']:.2f}<br>"
                 f"<b>Area before → after ({BS_TOP_AREA_WINDOW_S}s):</b><br>"
                 f"X: {bs['area_before_x']:+.3f} → {bs['area_after_x']:+.3f}<br>"
                 f"Y: {bs['area_before_y']:+.3f} → {bs['area_after_y']:+.3f}<br>"
                 f"Z: {bs['area_before_z']:+.3f} → {bs['area_after_z']:+.3f}")
        ay_val = -50 if i % 2 == 0 else -90
        ann(x, bs['rot_mag'], label, C_BS_TOP, 1, ay=ay_val, size=8)

    # ── Annotate: Forward swing force peaks (vertical lines on row 1) ────────
    for i, fs in enumerate(fs_peaks):
        x = fs['t'] - t0
        vline(x, C_FS_PEAK, 'solid', 2, target_rows=(1,))
        label = (f"FS PEAK  rotMag={fs['rot_mag']:.2f}<br>"
                 f"<b>Area before → after ({FS_AREA_WINDOW_S}s):</b><br>"
                 f"X: {fs['area_before_x']:+.3f} → {fs['area_after_x']:+.3f}<br>"
                 f"Y: {fs['area_before_y']:+.3f} → {fs['area_after_y']:+.3f}<br>"
                 f"Z: {fs['area_before_z']:+.3f} → {fs['area_after_z']:+.3f}")
        ay_val = 40 if i % 2 == 0 else 70
        ann(x, fs['rot_mag'], label, C_FS_PEAK, 1, ay=ay_val, size=8)

    # ── Legend entries ────────────────────────────────────────────────────────
    fig.add_trace(go.Scatter(
        x=[None], y=[None], mode='markers',
        marker=dict(symbol='square', size=12, color=C_SETUP, opacity=0.4),
        name='Setup window', showlegend=True), row=1, col=1)
    fig.add_trace(go.Scatter(
        x=[None], y=[None], mode='lines',
        line=dict(color=C_BS_TOP, width=1.5, dash='dash'),
        name='Backswing top', showlegend=True), row=1, col=1)
    fig.add_trace(go.Scatter(
        x=[None], y=[None], mode='lines',
        line=dict(color=C_FS_PEAK, width=2, dash='solid'),
        name='Forward swing force peak', showlegend=True), row=1, col=1)

    # ── Layout ───────────────────────────────────────────────────────────────
    fig.update_layout(
        title=dict(text=title, font=dict(size=13)),
        height=950,
        hovermode='x unified',
        annotations=list(fig.layout.annotations) + annotations,
        legend=dict(orientation='h', yanchor='bottom', y=1.02,
                    xanchor='left', x=0, font=dict(size=10)),
        margin=dict(l=60, r=40, t=120, b=50),
    )
    fig.update_xaxes(title_text='Time (s)', row=3, col=1)
    fig.update_yaxes(title_text='rad/s', row=1, col=1)
    fig.update_yaxes(title_text='deg',   row=2, col=1)
    fig.update_yaxes(title_text='G',     row=3, col=1)
    fig.update_xaxes(showspikes=True, spikemode='across', spikesnap='cursor',
                     showticklabels=True, tickmode='auto', nticks=30)

    fig.write_html(out_path, include_plotlyjs='cdn')
    print(f'  Saved: {out_path}')

    # Summary
    print(f'    Setups: {len(setups)}  |  BS tops: {len(bs_tops)}  |  FS peaks: {len(fs_peaks)}')


# ═════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════════════════════════════════════

def main():
    out_dir = _HERE

    putt_files = sorted(glob.glob(os.path.join(_ROOT, 'putts_samples', 'motion_test_*.csv')))

    print(f'Putt detection visualization')
    print(f'  Putt samples: {len(putt_files)}')
    print()

    if putt_files:
        print('Generating putts.html...')
        plot_stitched(putt_files, os.path.join(out_dir, 'putts.html'),
                      'Putt Samples')

    print('\nDone.')


if __name__ == '__main__':
    main()
