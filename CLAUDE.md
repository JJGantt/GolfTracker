# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GolfTracker is a native SwiftUI golf tracking application for iOS and Apple Watch. The app provides real-time GPS-based distance tracking, stroke recording, satellite imagery support, and motion detection for swing analysis.

**Key Technologies:**
- SwiftUI for UI across both platforms
- MapKit for maps and satellite imagery
- CoreLocation for GPS tracking
- CoreMotion for swing detection (Watch)
- WatchConnectivity for iPhone-Watch sync
- HealthKit for workout tracking (Watch)

## Build Commands

### Building the iOS App
```bash
# Build for simulator
xcodebuild -project GolfTracker.xcodeproj -scheme GolfTracker -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for device
xcodebuild -project GolfTracker.xcodeproj -scheme GolfTracker -destination 'generic/platform=iOS' build
```

### Building the Watch App
```bash
# Build Watch app for simulator
xcodebuild -project GolfTracker.xcodeproj -scheme "GolfWatch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build
```

### Opening in Xcode
```bash
open GolfTracker.xcodeproj
```

## Architecture

### Two-Target Structure

The project contains two main targets that share data models but have separate UI implementations:

1. **GolfTracker** (iOS) - Full-featured iPhone app with course management, round history, and detailed shot tracking
2. **GolfWatch Watch App** (watchOS) - Companion app for on-course tracking with motion detection

### Data Synchronization Architecture

The iPhone and Watch apps communicate bidirectionally via **WatchConnectivity**:

- **iPhone → Watch**: Round data (including course and hole information), satellite images
- **Watch → iPhone**: Recorded strokes, motion data CSV files, round updates
- **Bidirectional**: Hole navigation sync, target marker sync, hole creation/editing

**Critical Implementation Detail**: Both platforms maintain their own `DataStore` instances:
- iOS: `DataStore` in `GolfTracker/Services/DataStore.swift`
- watchOS: `WatchDataStore` in `GolfWatch Watch App/Services/WatchDataStore.swift`

When modifying data sync, update both the sending logic in `WatchConnectivityManager` and the receiving callbacks in both DataStore implementations.

### State Management Pattern

All major features use `ObservableObject` classes as single sources of truth:
- `DataStore` / `WatchDataStore` - Course and round data
- `LocationManager` - GPS tracking (singleton)
- `WatchConnectivityManager` - iPhone-Watch communication (singleton)
- `SwingDetectionManager` - Motion detection (singleton, Watch only)
- `WorkoutManager` - HealthKit workout tracking (singleton, Watch only)
- `StatsEngine` - Round/player statistics (iOS only)

### Core Data Models

All data models are defined in `GolfTracker/Models/Models.swift` and are shared between iOS and watchOS targets:

- **Course**: Contains holes, optional rating/slope/city metadata
- **Hole**: Number, coordinates, par (3/4/5)
- **Round**: References a course, contains strokes, targets, completion status, current hole index
- **Stroke**: GPS coordinate, club, timestamp, optional trajectory heading, optional landing position, penalty flag, optional peak acceleration
- **Target**: Hole-specific GPS markers for distance reference
**Important**: When adding new fields to models, ensure they are `Codable` as they're serialized for JSON persistence and WatchConnectivity transfer.

### Motion Detection System

The swing detection system (Watch only) uses CoreMotion at 50Hz to analyze:
- User acceleration (gravity removed)
- Gyroscope rotation rate
- Gravity vector
- Device attitude (pitch, roll, yaw)

**Detection Algorithm** (`SwingDetectionManager.swift`):
- Monitors acceleration magnitude against configurable threshold (default: 2.5G)
- Triggers swing event when acceleration exceeds threshold for configurable duration (default: 0.1s)
- Enforces 0.5s debounce period between swings
- Captures peak acceleration and GPS location at swing moment
- Provides haptic and audio feedback

**Recording Mode**: Can record full 14-channel motion data to CSV for analysis, transferred to iPhone via WatchConnectivity and saved to documents directory.

## Key Implementation Patterns

### Distance Calculations

All distance and bearing calculations use the helper functions in `GolfTracker/Helpers/MapCalculations.swift`:
- `distance(from:to:)` - Returns distance in meters
- `bearing(from:to:)` - Returns bearing in degrees (0-360)
- Formatted output converts meters to yards for display

### Map Camera Behavior

The live play map (`HolePlayView.swift`) uses auto-rotating camera behavior:
- Hole marker always appears at top of screen
- User location always appears at bottom
- Map rotates based on bearing from user to hole
- Zoom adjusts dynamically based on distance to hole

This is implemented using `MapCameraPosition.camera()` with computed center point, bearing, and distance.

### Stroke Recording Flow

When recording a stroke (on either iPhone or Watch):
1. Capture current GPS location
2. Get current hole from active round
3. Create Stroke object with auto-incremented stroke number
4. Calculate distance to hole at stroke moment
5. Add stroke to round's stroke array
6. Sync stroke to other device via WatchConnectivity
7. Save to persistent storage (JSON)

**Important**: Stroke numbers are auto-incremented per hole. When adding strokes, always filter existing strokes by current hole number to get the next stroke number.

### Hole Navigation Synchronization

The `currentHoleIndex` field in Round is synchronized bidirectionally:
- When user advances to next hole on iPhone, Watch receives update via WatchConnectivity
- When user advances on Watch, iPhone receives update
- Both apps use this index to display the current hole

When implementing hole navigation features, always sync the hole index change via `WatchConnectivityManager.sendRound()`.

## Common Workflows

### Adding a New Club Type

1. Add new case to `Club` enum in `Models.swift`
2. Update the Digital Crown club picker on Watch in `ActiveRoundView.swift` (club selection logic)
3. Update the club picker on iPhone in `HolePlayView.swift`
4. Both enums are automatically Codable, so no serialization changes needed

### Adding a New Stroke Attribute

1. Add field to `Stroke` struct in `Models.swift`
2. Ensure field is Codable (primitive types or Codable conforming types)
3. Update `StrokeDetailsView.swift` to display new attribute
4. Update stroke creation logic in both `HolePlayView.swift` (iOS) and `ActiveRoundView.swift` (Watch)
5. Data will automatically sync via WatchConnectivity and persist via JSON

### Modifying WatchConnectivity Messages

1. Update the sending logic in `WatchConnectivityManager.swift` (either `sendRound`, `sendStrokes`, or add new method)
2. Update the receiving callback in both:
   - `DataStore.setupWatchConnectivity()` (iOS)
   - `WatchDataStore.setupConnectivity()` (Watch)
3. Test both directions (iPhone → Watch and Watch → iPhone)
4. Ensure data is properly encoded/decoded with `JSONEncoder`/`JSONDecoder`

## File Organization

```
GolfTracker/                              # iOS app target
├── App/GolfTrackerApp.swift              # iOS app entry point
├── Models/
│   ├── Models.swift                      # Shared data models (iOS + Watch)
│   └── PlayerStats.swift                 # Player statistics models
├── Views/
│   ├── ContentView.swift                 # Main tab view
│   ├── Home/                             # Home & club management
│   │   ├── HomeView.swift
│   │   ├── ClubManagementView.swift
│   │   ├── ClubEditorView.swift
│   │   ├── ClubSetEditorView.swift
│   │   └── TypeEditorView.swift
│   ├── Courses/                          # Course management screens
│   ├── Rounds/                           # Round history screens
│   ├── Play/                             # Active play interface
│   │   ├── HolePlayView.swift            # Main play screen
│   │   ├── HoleMapView.swift             # Interactive map component
│   │   ├── HoleOverlayControls.swift     # Distance/hole overlays
│   │   ├── FloatingButtonsView.swift     # Action buttons overlay
│   │   ├── StrokeDetailsView.swift       # Stroke info sheet
│   │   ├── InRoundScorecardView.swift    # Live scorecard
│   │   └── Components/                   # Edit modes, modifiers
│   ├── Stats/StatsView.swift             # Statistics dashboard
│   ├── Shared/MapAnnotations.swift       # Custom map markers
│   └── Test/TestFilesView.swift          # Motion data file viewer
├── Services/
│   ├── DataStore.swift                   # iOS data persistence + sync callbacks
│   ├── LocationManager.swift             # GPS tracking
│   ├── StatsEngine.swift                 # Statistics calculations
│   └── WatchConnectivityManager.swift    # iPhone-Watch communication
└── Helpers/MapCalculations.swift         # Distance/bearing utilities

GolfWatch Watch App/                      # watchOS app target
├── GolfWatchApp.swift                    # Watch app entry point
├── ContentView.swift                     # Main Watch view
├── Views/
│   ├── WatchHomeView.swift               # Watch home screen
│   ├── ActiveRoundView.swift             # Main Watch play interface
│   ├── AccelTestView.swift               # Motion testing interface
│   ├── OptionsView.swift                 # Settings menu
│   ├── AddHoleNavigationView.swift       # Add hole flow
│   ├── EditHoleView.swift                # Edit hole screen
│   ├── ClubRecommendSettingsView.swift   # Club prediction settings
│   ├── PredictGreenSettingsView.swift    # Green prediction settings
│   └── ViewSettingsView.swift            # View preferences
├── Services/
│   ├── WatchDataStore.swift              # Watch data persistence + sync
│   ├── SwingDetectionManager.swift       # CoreMotion swing detection
│   ├── SwingAlgorithmProtocol.swift      # Detection algorithm protocol
│   ├── UnifiedDetector.swift             # Unified stroke detector
│   ├── FullSwingDetector.swift           # Full swing detection
│   ├── PuttDetector.swift                # Putt detection
│   ├── PartialDetector.swift             # Partial swing detection
│   ├── EventBasedDetector.swift          # Event-based detection
│   ├── IncrementalPeakDetector.swift     # Streaming peak detection
│   ├── RollingMotionBuffer.swift         # Motion data buffer
│   ├── DetectionEvents.swift             # Event structs
│   └── WorkoutManager.swift              # HealthKit workout tracking
└── Helpers/WatchOS10Compatibility.swift  # OS compatibility helpers

docs/                                     # Design docs (gitignored planning files)
swing_detection/                          # Python analysis tools (gitignored)
```

## Platform-Specific Notes

### iOS (iPhone)
- Supports both portrait orientations only
- Background location tracking enabled for active rounds
- Can run completely standalone (Watch is optional)
- Manages satellite image downloads and transfers to Watch

### watchOS (Apple Watch)
- Minimum watchOS 26.0 (verify in project settings)
- Can operate standalone if round data is synced
- Motion detection only available on Watch (iPhone has no accelerometer access)
- UI optimized for Digital Crown interaction (club selection, scrolling)
- Uses haptic feedback extensively for action confirmation

## Permissions

Required permissions are declared in Info.plist files:

**iOS**:
- `NSLocationWhenInUseUsageDescription` - Distance calculations during rounds
- `NSLocationAlwaysAndWhenInUseUsageDescription` - Background tracking
- Background mode: `location`

**watchOS**:
- Location permissions - Inherited from iOS companion
- HealthKit - Workout tracking (heart rate, calories, distance)
- Motion - CoreMotion for swing detection

## Development Notes

### Data Persistence

Both apps use JSON file storage in documents directory:
- iOS: `courses.json`, `rounds.json`
- Watch: `currentRound` and `pendingStrokes` stored in UserDefaults, then synced

**Important**: There is no automatic cloud sync. Data lives locally on each device and syncs via WatchConnectivity when paired and in range.

### Testing Motion Detection

Use `AccelTestView.swift` (Watch):
1. Toggle swing detection on/off
2. Adjust acceleration threshold and time requirement
3. View real-time acceleration values
4. Record full motion sessions
5. Transfer CSV data to iPhone for analysis

Recorded data appears in "Tests" tab on iPhone in `TestFilesView.swift`.

### Coordinate System Notes

- All coordinates use `CLLocationCoordinate2D` (latitude/longitude in degrees)
- Distances are calculated in meters, displayed in yards (multiply by 1.09361)
- Bearings are in degrees clockwise from true north (0-360)
- Heading/trajectory is captured from device compass at moment of shot

### Adding New Holes During Round

Both iPhone and Watch support adding holes during an active round:
- New hole defaults to current GPS location
- Par defaults to 4 (user can select 3/4/5)
- Hole is added to both the Course (persistent) and current Round (active)
- Changes sync immediately to paired device

This is important for courses that haven't been pre-mapped.
