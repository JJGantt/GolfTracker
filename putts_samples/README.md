# putts_samples — Putt Detection Algorithm

## What this directory is
Recorded device motion CSVs from actual putting strokes on an Apple Watch.
The algorithm here is the **putt-specific** detector that mirrors `SwingDetectionManager.swift` (smart detect mode, putter club selected).

## Algorithm: `detect.py`
**The canonical reference implementation for the putt state machine.**
All other detection directories import `parse_csv`, `_deg`, `_rad`, and orientation constants from this file.

State machine:
```
idle → accumulating → qualified → inBackstroke → inForwardStroke → detected
```

- **Setup** (`idle → accumulating → qualified`): pitch in [-25°, 0°], roll in [85°, 135°], rotMag ≤ 0.15 rad/s for ≥ 0.3s
- **BS entry** (`qualified → inBackstroke`): rotMag exceeds ceiling AND **rotY > 0 and dominant** over rotX and rotZ
- **BS tracking**: rotY peak (max rotY seen)
- **FS entry** (`inBackstroke → inForwardStroke`): rotY ≤ FORWARD_STROKE_THRESHOLD (-0.05 rad/s)
- **Detection** (`inForwardStroke → detected`): rotY returns to ≥ 0; evaluate FS/BS rotY peak ratio [0.5, 10.0], rotY must dominate over rotX/rotZ, |rotZ FS peak| < 1.5

Key axis: **rotY** is the primary detection axis (wrist rotation around forearm axis during putting motion).

## Other files
- `analyze_impact.py` — Post-detection analysis: finds ball-contact transient in raw Z accel (800 Hz) data around each detected putt. Uses `detect.py` for detections.
- `visualize.py` — Interactive Plotly HTML visualization of putt detections on stitched CSVs.

## Bug context (see iregular_samples/README.md)
The re-setup bug (false BS entry from wrist shake during setup) may also apply here if a wrist shake during setup produces a rotY-dominant spike, causing BS peak to be contaminated. The threshold for this is higher in putts (ceiling = 0.15, so any wrist shake breaking the ceiling AND being rotY-dominant triggers it), but the shorter BS duration allows quick self-correction via ratio check failure.
