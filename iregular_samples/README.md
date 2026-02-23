# iregular_samples — Irregular / Variable-Strength Stroke Algorithm

## What this directory is
Recorded device motion CSVs of actual golf strokes at varying strengths (chip shots, punch shots, half swings, etc.) — NOT putts, NOT full swings. These are strokes where swing speed is unpredictable, which is why this algorithm is distinct from the full-swing one.

## Algorithm: `visualize.py` (`run_instrumented`)
**A standalone algorithm, NOT the putt algorithm.** Does NOT use rotY as the primary axis.

State machine:
```
idle → accumulating → qualified → inBackstroke → inBackstrokeTop → inForwardStroke → postImpact → detected
```

- **Setup** (`idle → accumulating → qualified`): same orientation bounds as putts (pitch [-25°, 0°], roll [85°, 135°]), but **ceiling = 1.0 rad/s** (much higher than putts' 0.15), duration ≥ 0.2s
- **BS entry** (`qualified → inBackstroke`): rotMag > 1.0 — **no axis dominance check** (unlike putts and full swings)
- **BS tracking**: rotMag peak (not rotY peak)
- **inBackstrokeTop entry**: rotZ < -1.0 (rotZ goes strongly negative = top of backswing)
- **FS entry** (`inBackstrokeTop → inForwardStroke`): rotZ returns to ≥ 0 from below; BS duration check (≥ 0.5s from setup exit to here, else reset)
- **FS tracking**: rotMag peak
- **postImpact entry**: FS rotMag peak ≥ 2× BS rotMag peak AND rotMag has fallen back to ≤ BS level; ratio must be in [2.0, 8.0]
- **Detection** (`postImpact → detected`): rotX goes positive, then crosses ≤ 0

Key axis: **rotZ** gates the BS top; **rotMag** is the primary magnitude signal; **rotX** confirms follow-through.

## Known bug (what brought you here)
**False BS entry from wrist shake during setup.** When the wrist shakes while in setup, rotMag can exceed the ceiling (1.0 rad/s) and transition to `inBackstroke` prematurely. The algorithm then waits for rotZ < -1.0 as the "real" BS top marker. Two failure modes:
1. rotZ never goes that negative from the shake → stuck in `inBackstroke`, `bs_peak_rot_mag` keeps accumulating from both the shake and the real BS → inflated bsPeak → ratio too low → missed detection
2. rotZ does go below -1.0 from the shake → enters `inBackstrokeTop`, rotZ returns to 0 → BS top triggered with potentially wrong timing → real putt measures from the false start

Fix needed: if stable setup conditions (inBounds && rotMag ≤ ceiling) re-appear for ≥ SWING_MIN_DURATION_S (0.2s) while in `inBackstroke` or `inForwardStroke`, restart detection from `qualified` and reset all BS/FS tracking.
