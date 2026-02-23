# full_swing_samples — Full Swing Algorithm

## What this directory is
Recorded device motion CSVs of full golf swings (driver, irons at full speed). These are high-energy swings where rotX (forearm roll through impact) is the dominant and most reliable signal.

## Algorithm: `visualize.py` (`run_instrumented`)
**A standalone algorithm, NOT the putt algorithm.** Primary axis is **rotX**, not rotY.

State machine:
```
idle → accumulating → qualified → inBackstroke → inForwardStroke → postImpact → detected
```

- **Setup** (`idle → accumulating → qualified`): same orientation bounds (pitch [-25°, 0°], roll [85°, 135°]), ceiling = 1.0 rad/s, duration ≥ 0.2s
- **BS entry** (`qualified → inBackstroke`): rotMag > ceiling AND **rotX > 0 and dominant** over rotY and rotZ
- **BS tracking**: rotX peak (and rotMag at that point)
- **BS validity** (checked at `inBackstroke → inForwardStroke` when rotX crosses 0): rotX peak ≥ 3.0 rad/s, rotY < 0.2 × rotX, rotZ < 0.2 × rotX (rotX must be dominant at peak)
- **FS tracking**: rotMag peak
- **postImpact entry**: FS rotMag peak ≥ 2× BS rotMag AND fallen back to ≤ BS rotMag; ratio in [2.0, 8.0]
- **Detection** (`postImpact → detected`): rotX goes positive, then crosses ≤ 0

Key axis: **rotX** gates setup exit and BS validity; **rotMag** is the FS/BS magnitude comparison; **rotX** also confirms follow-through.

## Differences from iregular_samples
| | iregular | full_swing |
|---|---|---|
| BS entry axis check | none (rotMag only) | rotX must be dominant |
| BS top trigger | rotZ < −1.0 then ≥ 0 | rotX crosses 0 |
| BS duration check | yes (≥ 0.5s) | no |
| BS peak tracked | rotMag | rotX (+ validity checks) |

## Imports
`visualize.py` imports `parse_csv`, `_deg`, `_rad`, and orientation constants from `../putts_samples/detect.py`. Do not move or rename `detect.py`.
