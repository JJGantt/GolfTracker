import SwiftUI
import MapKit

struct HolePlayView: View {
    @ObservedObject var store: DataStore
    let course: Course
    let resumingRound: Round?

    @StateObject private var locationManager = LocationManager()
    @State private var currentHoleIndex = 0
    @State private var position = MapCameraPosition.automatic
    @State private var showingEditMenu = false
    @State private var showingMoveHoleConfirmation = false
    @State private var showingAddTeeConfirmation = false
    @State private var showingEditYards = false
    @State private var showingEditPar = false
    @State private var yardsInput = ""
    @State private var parInput = ""
    @State private var activeRound: Round?
    @State private var showingClubSelection = false
    @State private var showingStrokeDetails = false
    @State private var selectedStrokeIndex: Int = 0
    @State private var isAddingHole = false
    @State private var temporaryHolePosition: CLLocationCoordinate2D?
    @State private var useStandardMap = false
    @State private var isMovingHoleManually = false
    @State private var isAddingTeeManually = false
    @State private var temporaryPosition: CLLocationCoordinate2D?
    @State private var showingCourseEditor = false
    @State private var isMovingStroke = false
    @State private var strokeToMove: Stroke?
    @State private var savedMapRegion: MKCoordinateRegion?
    @State private var longPressLocation: CGPoint?
    @State private var showingLongPressClubSelection = false
    @State private var isAddingPenaltyStroke = false
    @State private var trajectoryHeading: Double? = nil // nil means default to hole direction
    @State private var forceUserHoleView = false // Toggle between tee/hole and user/hole view
    @State private var isPlacingTarget = false
    @State private var isDeleting = false

    init(store: DataStore, course: Course, resumingRound: Round? = nil, startingHoleNumber: Int? = nil) {
        self.store = store
        self.course = course
        self.resumingRound = resumingRound
        if let holeNumber = startingHoleNumber {
            _currentHoleIndex = State(initialValue: holeNumber - 1)
        }
    }

    private var currentCourse: Course {
        store.courses.first { $0.id == course.id } ?? course
    }

    private var currentHole: Hole? {
        guard currentHoleIndex < currentCourse.holes.count else { return nil }
        return currentCourse.holes[currentHoleIndex]
    }

    private var currentRound: Round? {
        guard let activeRound = activeRound else { return nil }
        return store.rounds.first { $0.id == activeRound.id }
    }

    private var strokeCountForCurrentHole: Int {
        guard let round = currentRound,
              let hole = currentHole else { return 0 }
        return round.strokes.filter { $0.holeNumber == hole.number }.count
    }

    private var strokesForCurrentHole: [Stroke] {
        guard let round = currentRound,
              let hole = currentHole else { return [] }
        return round.strokes.filter { $0.holeNumber == hole.number }
    }

    private var mostRecentStroke: Stroke? {
        return strokesForCurrentHole.last
    }

    private var effectiveTrajectoryHeading: Double? {
        // If user has set a trajectory, use it; otherwise default to heading toward hole
        if let heading = trajectoryHeading {
            return heading
        }

        // Calculate heading toward hole from user location
        guard let userLocation = locationManager.location,
              let hole = currentHole else { return nil }

        let userCoord = userLocation.coordinate
        let holeCoord = hole.coordinate
        return calculateBearing(from: userCoord, to: holeCoord)
    }

    private var selectedStroke: Stroke? {
        guard selectedStrokeIndex < strokesForCurrentHole.count else { return nil }
        return strokesForCurrentHole[selectedStrokeIndex]
    }

    private var isCurrentHoleCompleted: Bool {
        guard let round = currentRound,
              let hole = currentHole else { return false }
        return round.isHoleCompleted(hole.number)
    }

    private var canUndo: Bool {
        guard activeRound != nil else { return false }

        // Can undo if there are strokes on current hole
        if !strokesForCurrentHole.isEmpty {
            return true
        }

        // Can undo if we just finished the previous hole (no strokes on current, previous is completed)
        if currentHoleIndex > 0,
           let round = currentRound {
            let previousHoleNumber = currentCourse.holes[currentHoleIndex - 1].number
            return round.isHoleCompleted(previousHoleNumber)
        }

        return false
    }

    private var targetCoordinatesBinding: Binding<[CLLocationCoordinate2D]> {
        Binding(
            get: {
                guard let round = self.currentRound,
                      let hole = self.currentHole else { return [] }
                return round.targets
                    .filter { $0.holeNumber == hole.number }
                    .map { $0.coordinate }
            },
            set: { newCoordinates in
                guard let round = self.activeRound,
                      let hole = self.currentHole else { return }

                // Remove old targets for this hole
                var updatedRound = self.store.rounds.first { $0.id == round.id } ?? round
                updatedRound.targets.removeAll { $0.holeNumber == hole.number }

                // Add new targets
                let newTargets = newCoordinates.map { Target(holeNumber: hole.number, coordinate: $0) }
                updatedRound.targets.append(contentsOf: newTargets)

                // Update in store
                if let index = self.store.rounds.firstIndex(where: { $0.id == round.id }) {
                    self.store.rounds[index] = updatedRound
                    self.store.saveRounds()

                    // Sync to Watch
                    WatchConnectivityManager.shared.sendRound(updatedRound)
                }
            }
        )
    }

    private func distanceToTarget(_ target: CLLocationCoordinate2D) -> Int? {
        guard let userLocation = locationManager.location else { return nil }

        let targetLocation = CLLocation(
            latitude: target.latitude,
            longitude: target.longitude
        )

        let distanceInMeters = userLocation.distance(from: targetLocation)
        return Int(distanceInMeters * 1.09361) // Convert to yards
    }

    // Calculate the rotation angle for the aim arrow
    private var aimArrowRotation: Double {
        guard let capturedHeading = trajectoryHeading,
              let userLocation = locationManager.location,
              let hole = currentHole else {
            return 0 // Arrow points up when not set
        }

        // Calculate bearing to hole
        let bearingToHole = calculateBearing(from: userLocation.coordinate, to: hole.coordinate)

        // Calculate offset: how much the aim direction differs from hole bearing
        let offset = (capturedHeading - bearingToHole + 360).truncatingRemainder(dividingBy: 360)

        // Convert to -180 to 180 range for cleaner display
        let normalizedOffset = offset > 180 ? offset - 360 : offset

        return normalizedOffset
    }

    private var floatingStrokeButton: some View {
        Image(systemName: "plus")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(width: 60, height: 60)
            .background(Color.green.opacity(0.95))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .opacity((locationManager.location == nil || activeRound == nil) ? 0.5 : 0.95)
    }

    private var floatingDetailsButton: some View {
        Image(systemName: "plus")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(width: 60, height: 60)
            .background(.yellow)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .opacity(strokesForCurrentHole.isEmpty ? 0.5 : 1.0)
    }

    private var mainContent: some View {
        ZStack {
            if isAddingHole {
                AddHoleMapView(
                    position: $position,
                    temporaryHolePosition: $temporaryHolePosition,
                    userLocation: locationManager.location,
                    heading: locationManager.heading,
                    useStandardMap: useStandardMap
                )
                AddHoleOverlay(
                    holeCount: currentCourse.holes.count,
                    temporaryHolePosition: $temporaryHolePosition,
                    isAddingHole: $isAddingHole,
                    saveTemporaryHole: saveTemporaryHole
                )
            } else if isMovingHoleManually {
                ManualPlacementMapView(
                    position: $position,
                    temporaryPosition: $temporaryPosition,
                    currentHole: currentHole,
                    userLocation: locationManager.location,
                    heading: locationManager.heading,
                    useStandardMap: useStandardMap,
                    isAddingTeeManually: false
                )
                MoveHoleManuallyOverlay(
                    currentHole: currentHole,
                    temporaryPosition: $temporaryPosition,
                    isMovingHoleManually: $isMovingHoleManually,
                    savedMapRegion: $savedMapRegion,
                    userLocation: locationManager.location,
                    store: store,
                    currentCourse: currentCourse,
                    restoreSavedMapRegion: restoreSavedMapRegion
                )
            } else if isAddingTeeManually {
                ManualPlacementMapView(
                    position: $position,
                    temporaryPosition: $temporaryPosition,
                    currentHole: currentHole,
                    userLocation: locationManager.location,
                    heading: locationManager.heading,
                    useStandardMap: useStandardMap,
                    isAddingTeeManually: true
                )
                AddTeeManuallyOverlay(
                    currentHole: currentHole,
                    temporaryPosition: $temporaryPosition,
                    isAddingTeeManually: $isAddingTeeManually,
                    savedMapRegion: $savedMapRegion,
                    userLocation: locationManager.location,
                    store: store,
                    currentCourse: currentCourse,
                    restoreSavedMapRegion: restoreSavedMapRegion
                )
            } else if isMovingStroke {
                StrokeMovementMapView(
                    position: $position,
                    temporaryPosition: $temporaryPosition,
                    currentHole: currentHole,
                    currentRound: currentRound,
                    strokeToMove: strokeToMove,
                    userLocation: locationManager.location,
                    heading: locationManager.heading,
                    useStandardMap: useStandardMap
                )
                MoveStrokeOverlay(
                    strokeToMove: strokeToMove,
                    activeRound: activeRound,
                    temporaryPosition: $temporaryPosition,
                    isMovingStroke: $isMovingStroke,
                    strokeToMoveBinding: $strokeToMove,
                    savedMapRegion: $savedMapRegion,
                    userLocation: locationManager.location,
                    store: store,
                    restoreSavedMapRegion: restoreSavedMapRegion
                )
            } else if isAddingPenaltyStroke {
                PenaltyStrokeMapView(
                    position: $position,
                    temporaryPosition: $temporaryPosition,
                    currentHole: currentHole,
                    currentRound: currentRound,
                    userLocation: locationManager.location,
                    heading: locationManager.heading,
                    useStandardMap: useStandardMap
                )
                AddPenaltyStrokeOverlay(
                    currentHole: currentHole,
                    activeRound: activeRound,
                    temporaryPosition: $temporaryPosition,
                    isAddingPenaltyStroke: $isAddingPenaltyStroke,
                    userLocation: locationManager.location,
                    store: store,
                    updateMapPosition: updateMapPosition
                )
            } else if let hole = currentHole {
                HoleMapView(
                    hole: hole,
                    currentRound: currentRound,
                    userLocation: locationManager.location,
                    heading: locationManager.heading,
                    useStandardMap: useStandardMap,
                    position: $position,
                    targetCoordinates: targetCoordinatesBinding,
                    isPlacingTarget: $isPlacingTarget,
                    isDeleting: $isDeleting,
                    distanceToTarget: distanceToTarget,
                    onHoleTap: {
                        saveCurrentMapRegion()
                        temporaryPosition = hole.coordinate
                        isMovingHoleManually = true
                    },
                    onTeeTap: {
                        saveCurrentMapRegion()
                        temporaryPosition = hole.teeCoordinate
                        isAddingTeeManually = true
                    },
                    onStrokeTap: { index in
                        selectedStrokeIndex = index
                        showingStrokeDetails = true
                    }
                )
                HoleOverlayControls(
                    hole: hole,
                    strokeCount: strokeCountForCurrentHole,
                    formattedDistance: locationManager.formattedDistance(to: hole.coordinate),
                    errorMessage: locationManager.errorMessage,
                    currentHoleIndex: currentHoleIndex,
                    totalHoles: currentCourse.holes.count,
                    onPrevious: previousHole,
                    onNext: nextHole,
                    onAddHole: startAddingNextHole
                )
                floatingButtons()
            } else {
                Color.clear
                    .onAppear {
                        isAddingHole = true
                    }
            }
        }
    }

    private var mapStyleButton: some View {
        Button(action: {
            useStandardMap.toggle()
        }) {
            Image(systemName: useStandardMap ? "map.fill" : "photo.fill")
        }
    }

    private var viewToggleButton: some View {
        Button(action: {
            forceUserHoleView.toggle()
            updateMapPosition()
        }) {
            Image(systemName: forceUserHoleView ? "figure.walk" : "flag.2.crossed.fill")
        }
        .disabled(currentHole == nil)
    }

    private var editMenuButton: some View {
        Button(action: {
            showingEditMenu = true
        }) {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(currentHole == nil)
    }

    var body: some View {
        mainContent
            .ignoresSafeArea(edges: .all)
            .navigationTitle(currentCourse.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    viewToggleButton
                    mapStyleButton
                    editMenuButton
                }
            }
            .modifier(NavigationModifier(showingCourseEditor: $showingCourseEditor, store: store, currentCourse: currentCourse))
            .modifier(EditMenuModifier(
                showingEditMenu: $showingEditMenu,
                showingMoveHoleConfirmation: $showingMoveHoleConfirmation,
                showingAddTeeConfirmation: $showingAddTeeConfirmation,
                showingEditYards: $showingEditYards,
                showingEditPar: $showingEditPar,
                showingCourseEditor: $showingCourseEditor,
                currentHole: currentHole,
                locationManager: locationManager,
                yardsInput: $yardsInput,
                parInput: $parInput,
                isCurrentHoleCompleted: isCurrentHoleCompleted,
                reopenHole: reopenCurrentHole
            ))
            .modifier(HoleEditingModifier(
                showingMoveHoleConfirmation: $showingMoveHoleConfirmation,
                showingAddTeeConfirmation: $showingAddTeeConfirmation,
                showingEditYards: $showingEditYards,
                showingEditPar: $showingEditPar,
                yardsInput: $yardsInput,
                parInput: $parInput,
                currentHole: currentHole,
                locationManager: locationManager,
                temporaryPosition: $temporaryPosition,
                isMovingHoleManually: $isMovingHoleManually,
                isAddingTeeManually: $isAddingTeeManually,
                store: store,
                currentCourse: currentCourse,
                moveCurrentHoleToUserLocation: moveCurrentHoleToUserLocation,
                addTeeMarkerAtCurrentLocation: addTeeMarkerAtCurrentLocation
            ))
            .modifier(ClubSelectionModifier(
                showingClubSelection: $showingClubSelection,
                showingLongPressClubSelection: $showingLongPressClubSelection,
                temporaryPosition: $temporaryPosition,
                recordStroke: recordStroke,
                recordLongPressStroke: recordLongPressStroke
            ))
            .modifier(StrokeDetailsModifier(
                showingStrokeDetails: $showingStrokeDetails,
                activeRound: activeRound,
                strokesForCurrentHole: strokesForCurrentHole,
                selectedStrokeIndex: $selectedStrokeIndex,
                isMovingStroke: $isMovingStroke,
                strokeToMove: $strokeToMove,
                temporaryPosition: $temporaryPosition,
                position: $position,
                savedMapRegion: $savedMapRegion,
                store: store
            ))
            .onAppear {
                locationManager.requestPermission()

            // Start round automatically or resume existing round
            if activeRound == nil {
                if let resumingRound = resumingRound {
                    activeRound = resumingRound
                } else {
                    activeRound = store.startRound(for: currentCourse)
                }
            }

            // Sync current hole index to watch on initial load
            if let round = activeRound {
                store.updateCurrentHoleIndex(for: round, newIndex: currentHoleIndex)
            }

            // Update map based on mode
            if isAddingHole {
                updateAddHoleMapPosition()
            } else {
                updateMapPosition()
            }
        }
        .onChange(of: currentHoleIndex) { _, _ in
            updateMapPosition()
        }
        .onChange(of: locationManager.location) { _, _ in
            // Don't auto-update map when adding hole - let user pan freely
        }
        .onChange(of: isAddingHole) { _, newValue in
            if newValue {
                updateAddHoleMapPosition()
            } else {
                updateMapPosition()
            }
        }
        .onChange(of: currentCourse.holes.count) { oldCount, newCount in
            // If holes count increased, it came from watch - close add hole screen if open
            if newCount > oldCount {
                print("📱 [HolePlayView] New hole detected from watch (count: \(oldCount) -> \(newCount))")
                if isAddingHole {
                    print("📱 [HolePlayView] Closing add hole screen, navigating to new hole")
                    isAddingHole = false
                    // Update to the new hole index
                    currentHoleIndex = newCount - 1
                }
            }
        }
        .onChange(of: currentHole) { oldHole, newHole in
            // If we're in add hole mode but now have a valid hole, close add hole screen
            // This handles watch navigation or watch creating a hole
            if isAddingHole && newHole != nil {
                print("📱 [HolePlayView] Valid hole now exists, closing add hole screen")
                isAddingHole = false
            }
        }
        // --- Begin new onChange blocks for edit modes ---
        .onChange(of: isMovingHoleManually) { _, newValue in
            if newValue {
                // Entering hole-move mode: show full hole view
                saveCurrentMapRegion()
            } else {
                // Exiting hole-move mode: return to regular user/hole view
                updateMapPosition()
            }
        }
        .onChange(of: isAddingTeeManually) { _, newValue in
            if newValue {
                // Entering tee-add mode: show full hole view
                saveCurrentMapRegion()
            } else {
                // Exiting tee-add mode: return to regular user/hole view
                updateMapPosition()
            }
        }
        .onChange(of: isMovingStroke) { _, newValue in
            if newValue {
                // Entering stroke-move mode: show full hole view
                saveCurrentMapRegion()
            } else {
                // Exiting stroke-move mode: return to regular user/hole view
                updateMapPosition()
            }
        }
        .onChange(of: isAddingPenaltyStroke) { _, newValue in
            if newValue {
                // Entering penalty stroke mode: already called saveCurrentMapRegion
            } else {
                // Exiting penalty stroke mode: return to regular user/hole view
                updateMapPosition()
            }
        }
        // --- End new onChange blocks for edit modes ---
        .onChange(of: currentRound?.currentHoleIndex) { _, newIndex in
            if let newIndex = newIndex, newIndex != currentHoleIndex {
                print("📱 [HolePlayView] Syncing hole index from Watch: \(newIndex)")
                currentHoleIndex = newIndex
            }
        }
    }

    private func previousHole() {
        guard let round = activeRound else { return }
        if currentHoleIndex > 0 {
            currentHoleIndex -= 1
            store.updateCurrentHoleIndex(for: round, newIndex: currentHoleIndex)
        }
    }

    private func nextHole() {
        guard let round = activeRound else { return }
        if currentHoleIndex < currentCourse.holes.count - 1 {
            currentHoleIndex += 1
            store.updateCurrentHoleIndex(for: round, newIndex: currentHoleIndex)
        }
    }

    private func finishCurrentHole() {
        guard let round = activeRound,
              let hole = currentHole else { return }

        // Mark hole as completed
        store.completeHole(in: round, holeNumber: hole.number)

        // Auto-advance to next hole if available, or start adding a new hole
        if currentHoleIndex < currentCourse.holes.count - 1 {
            currentHoleIndex += 1
            store.updateCurrentHoleIndex(for: round, newIndex: currentHoleIndex)
        } else {
            // No more holes, start adding a new one
            isAddingHole = true
        }
    }

    private func reopenCurrentHole() {
        guard let round = activeRound,
              let hole = currentHole else { return }

        // Remove hole from completed set
        store.reopenHole(in: round, holeNumber: hole.number)
    }

    private func captureAimDirection() {
        var heading: Double?

        // Try to get real heading first
        if let realHeading = locationManager.heading {
            heading = realHeading
        } else if let userLocation = locationManager.location,
                  let hole = currentHole {
            // Fallback: Use bearing to hole + 45 degrees as simulated offset
            let bearingToHole = calculateBearing(from: userLocation.coordinate, to: hole.coordinate)
            heading = (bearingToHole + 45).truncatingRemainder(dividingBy: 360)
        }

        guard let finalHeading = heading else { return }

        // Capture the current heading
        trajectoryHeading = finalHeading
    }

    private func toggleTargetPlacement() {
        isPlacingTarget.toggle()
    }

    private func undoLastAction() {
        guard let round = activeRound else { return }

        // Check if current hole is completed - if so, undo the completion first
        if let currentHole = currentHole, currentRound?.isHoleCompleted(currentHole.number) == true {
            store.reopenHole(in: round, holeNumber: currentHole.number)
            return
        }

        // If there are strokes on current hole, delete the last one
        if let lastStroke = strokesForCurrentHole.last {
            store.deleteStroke(in: round, stroke: lastStroke)
        } else if currentHoleIndex > 0 {
            // No strokes on current hole - check if we just finished the previous hole
            // Only undo if: we're on a hole with no strokes AND the immediately previous hole is completed
            let previousHoleIdx = currentHoleIndex - 1
            let previousHoleNumber = currentCourse.holes[previousHoleIdx].number

            if currentRound?.isHoleCompleted(previousHoleNumber) == true {
                // Undo the hole completion and go back to previous hole
                store.reopenHole(in: round, holeNumber: previousHoleNumber)
                currentHoleIndex = previousHoleIdx
                store.updateCurrentHoleIndex(for: round, newIndex: currentHoleIndex)
            }
        }
    }

    private func saveCurrentMapRegion() {
        guard let hole = currentHole else { return }

        let holeCoord = hole.coordinate

        // Determine the "start" of the hole: tee if present, otherwise user location.
        let startCoord: CLLocationCoordinate2D

        if let teeCoord = hole.teeCoordinate {
            startCoord = teeCoord
        } else if let userCoord = locationManager.location?.coordinate {
            startCoord = userCoord
        } else {
            // Fallback: just show a tight region around the hole.
            position = .region(MKCoordinateRegion(
                center: holeCoord,
                span: MKCoordinateSpan(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
            ))
            return
        }

        // Compute distance between start and hole
        let startLocation = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
        let holeLocation = CLLocation(latitude: holeCoord.latitude, longitude: holeCoord.longitude)
        let distance = max(startLocation.distance(from: holeLocation), 40.0)

        // Center point exactly between start and hole
        let centerLat = (holeCoord.latitude + startCoord.latitude) / 2.0
        let centerLon = (holeCoord.longitude + startCoord.longitude) / 2.0
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)

        // Bearing from start (tee/user) to hole so hole is at the "top" of the screen
        let bearing = calculateBearing(from: startCoord, to: holeCoord)

        // Use a similar zoom logic to the regular view: expand based on distance
        let spanInMeters = max(distance * 1.8, 40.0)
        let camera = MapCamera(
            centerCoordinate: center,
            distance: spanInMeters * 2.2,
            heading: bearing,
            pitch: 0
        )

        position = .camera(camera)
    }

    private func restoreSavedMapRegion() {
        updateMapPosition()
    }

    private func moveCurrentHoleToUserLocation() {
        guard let hole = currentHole,
              let location = locationManager.location else { return }
        store.updateHole(hole, in: currentCourse, newCoordinate: location.coordinate)
    }

    private func addTeeMarkerAtCurrentLocation() {
        guard let hole = currentHole,
              let location = locationManager.location else { return }
        store.updateTeeMarker(hole, in: currentCourse, teeCoordinate: location.coordinate)
    }

    private func recordStroke(with club: Club) {
        guard let round = activeRound,
              let hole = currentHole,
              let location = locationManager.location else { return }
        store.addStroke(to: round, holeNumber: hole.number, coordinate: location.coordinate, club: club, trajectoryHeading: trajectoryHeading)

        // Reset aim direction after recording stroke
        trajectoryHeading = nil
    }

    private func startAddingNextHole() {
        isAddingHole = true
        temporaryHolePosition = nil
        updateAddHoleMapPosition()
    }

    private func saveTemporaryHole(par: Int) {
        guard let coordinate = temporaryHolePosition else { return }

        // Save the hole with par
        store.addHole(to: currentCourse, coordinate: coordinate, par: par)

        // Navigate to the newly added hole
        currentHoleIndex = currentCourse.holes.count - 1

        // Exit add mode
        isAddingHole = false
        temporaryHolePosition = nil

        // Update map position for the new hole (will be triggered by updateMapPosition)
        updateMapPosition()
    }

    private func updateAddHoleMapPosition() {
        guard let userLocation = locationManager.location else { return }

        // Show area ~350 yards (320 meters) around the user
        let spanInMeters: CLLocationDistance = 320.0
        let spanDegrees = spanInMeters / 111000.0 // rough conversion

        position = .region(MKCoordinateRegion(
            center: userLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
        ))
    }

    @ViewBuilder
    private func floatingButtons() -> some View {
        ZStack {
            // Right side buttons (bottom to top: stroke, penalty, finish)
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    // Yellow button for finish hole (top)
                    Button(action: finishCurrentHole) {
                        Image(systemName: "flag.fill")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.yellow.opacity(0.95))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(activeRound == nil || isCurrentHoleCompleted)
                    .opacity((activeRound == nil || isCurrentHoleCompleted) ? 0.3 : 0.95)

                    // Orange button for penalty stroke
                    Button(action: {
                        saveCurrentMapRegion()
                        isAddingPenaltyStroke = true
                    }) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.orange.opacity(0.95))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(activeRound == nil || isCurrentHoleCompleted)
                    .opacity((activeRound == nil || isCurrentHoleCompleted) ? 0.3 : 0.95)

                    // Green button for new stroke (bottom)
                    Button(action: {
                        showingClubSelection = true
                    }) {
                        floatingStrokeButton
                    }
                    .disabled(locationManager.location == nil || activeRound == nil || isCurrentHoleCompleted)
                    .opacity((locationManager.location == nil || activeRound == nil || isCurrentHoleCompleted) ? 0.3 : 1.0)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 200)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Left side buttons (bottom to top: undo, aim direction, target)
            VStack {
                Spacer()
                HStack {
                    VStack(spacing: 12) {
                        // Target button (top)
                        Button(action: toggleTargetPlacement) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.95))
                                    .frame(width: 60, height: 60)
                                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                                if isPlacingTarget {
                                    Circle()
                                        .stroke(Color.yellow, lineWidth: 4)
                                        .frame(width: 60, height: 60)
                                }

                                Image(systemName: "scope")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                            }
                        }

                        // Blue button for aim direction
                        Button(action: captureAimDirection) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.95))
                                    .frame(width: 60, height: 60)
                                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                                Image(systemName: "location.north.fill")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .rotationEffect(.degrees(aimArrowRotation))
                            }
                        }
                        .disabled(activeRound == nil || isCurrentHoleCompleted)
                        .opacity((activeRound == nil || isCurrentHoleCompleted) ? 0.3 : 0.95)

                        // Undo button (bottom)
                        Button(action: undoLastAction) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.95))
                                    .frame(width: 60, height: 60)
                                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                                Image(systemName: "arrow.uturn.backward")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(!canUndo)
                        .opacity(canUndo ? 0.95 : 0.9)
                    }
                    .padding(.leading, 20)

                    Spacer()
                }
                .padding(.bottom, 200)
            }
        }
    }

    private func recordStrokeAtCoordinate(_ coordinate: CLLocationCoordinate2D) {
        temporaryPosition = coordinate
        showingLongPressClubSelection = true
    }

    private func recordLongPressStroke(with club: Club) {
        guard let round = activeRound,
              let hole = currentHole,
              let coordinate = temporaryPosition else { return }
        store.addStroke(to: round, holeNumber: hole.number, coordinate: coordinate, club: club, trajectoryHeading: nil)
        temporaryPosition = nil
    }

    private func updateMapPosition() {
        guard let hole = currentHole else { return }

        if let userLocation = locationManager.location {
            let userCoord = userLocation.coordinate
            let holeCoord = hole.coordinate
            let holeLocation = CLLocation(latitude: holeCoord.latitude, longitude: holeCoord.longitude)

            // Calculate distance in meters
            let distanceToHole = userLocation.distance(from: holeLocation)

            // Determine the max expected distance for the hole (use yards if available, otherwise default)
            let holeYardsInMeters = (hole.yards.map { Double($0) * 0.9144 }) ?? 300.0 // Default to ~300 meters
            let maxDistance = holeYardsInMeters * 1.5 // 50% buffer

            // Determine starting point based on toggle and distance
            let startCoord: CLLocationCoordinate2D
            if forceUserHoleView {
                // User has toggled to force user/hole view
                startCoord = userCoord
            } else if let teeCoord = hole.teeCoordinate {
                // Tee exists - use it if user is far away
                if distanceToHole > maxDistance {
                    startCoord = teeCoord
                } else {
                    startCoord = userCoord
                }
            } else {
                // No tee marker - ALWAYS show user-to-hole view (user at bottom, hole at top)
                startCoord = userCoord
            }

            // Calculate bearing and distance from starting point to hole
            let bearing = calculateBearing(from: startCoord, to: holeCoord)
            let startLocation = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
            let distance = max(startLocation.distance(from: holeLocation), 40.0)

            // Calculate span based on distance
            let spanInMeters = max(distance * 1.8, 40.0) // Minimum 40 meters view

            // Center point exactly between start and hole
            let centerLat = (holeCoord.latitude + startCoord.latitude) / 2.0
            let centerLon = (holeCoord.longitude + startCoord.longitude) / 2.0
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)

            // Create camera with rotation so hole is always at top
            // Increased distance to zoom out more, giving space above hole for yardage display
            let camera = MapCamera(
                centerCoordinate: center,
                distance: spanInMeters * 2.2, // Zoom out more for extra space at top
                heading: bearing, // Rotate map so bearing points up
                pitch: 0
            )

            position = .camera(camera)
        } else if let teeCoord = hole.teeCoordinate {
            // No user location but tee exists - show tee to hole view
            let holeCoord = hole.coordinate
            let bearing = calculateBearing(from: teeCoord, to: holeCoord)
            let teeLocation = CLLocation(latitude: teeCoord.latitude, longitude: teeCoord.longitude)
            let holeLocation = CLLocation(latitude: holeCoord.latitude, longitude: holeCoord.longitude)
            let distance = max(teeLocation.distance(from: holeLocation), 40.0)

            let spanInMeters = max(distance * 1.8, 40.0)
            let centerLat = (holeCoord.latitude + teeCoord.latitude) / 2.0
            let centerLon = (holeCoord.longitude + teeCoord.longitude) / 2.0
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)

            let camera = MapCamera(
                centerCoordinate: center,
                distance: spanInMeters * 2.2,
                heading: bearing,
                pitch: 0
            )

            position = .camera(camera)
        } else {
            // No user location and no tee - just center on the hole
            position = .region(MKCoordinateRegion(
                center: hole.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
            ))
        }
    }

    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let lon2 = to.longitude * .pi / 180.0

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x)

        // Convert from radians to degrees
        let bearingDegrees = bearing * 180.0 / .pi

        // Normalize to 0-360
        return (bearingDegrees + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    private func calculateDestination(from: CLLocationCoordinate2D, bearing: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6371000.0 // meters
        let bearingRadians = bearing * .pi / 180.0
        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0

        let lat2 = asin(sin(lat1) * cos(distanceMeters / earthRadius) +
                       cos(lat1) * sin(distanceMeters / earthRadius) * cos(bearingRadians))
        let lon2 = lon1 + atan2(sin(bearingRadians) * sin(distanceMeters / earthRadius) * cos(lat1),
                                cos(distanceMeters / earthRadius) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(
            latitude: lat2 * 180.0 / .pi,
            longitude: lon2 * 180.0 / .pi
        )
    }
}

struct StrokeDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: DataStore
    let round: Round
    let strokes: [Stroke]
    @Binding var selectedStrokeIndex: Int
    @Binding var isMovingStroke: Bool
    @Binding var strokeToMove: Stroke?
    @Binding var temporaryPosition: CLLocationCoordinate2D?
    @Binding var position: MapCameraPosition
    @Binding var savedMapRegion: MKCoordinateRegion?

    @State private var showingRenumberAlert = false
    @State private var newStrokeNumber = ""

    private var currentStroke: Stroke? {
        guard selectedStrokeIndex < strokes.count else { return nil }
        return strokes[selectedStrokeIndex]
    }

    private func saveCurrentMapRegion() {
        guard let stroke = currentStroke else { return }
        savedMapRegion = MKCoordinateRegion(
            center: stroke.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
        )
    }


    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 20) {
                // Stroke navigation
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button(action: {
                            if selectedStrokeIndex > 0 {
                                saveCurrentStroke()
                                selectedStrokeIndex -= 1
                                loadStrokeData()
                            }
                        }) {
                            Label("Previous", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedStrokeIndex == 0)

                        Button(action: {
                            guard let stroke = currentStroke else { return }
                            newStrokeNumber = "\(stroke.strokeNumber)"
                            showingRenumberAlert = true
                        }) {
                            VStack(spacing: 2) {
                                Text("Stroke \(selectedStrokeIndex + 1)")
                                    .font(.headline)
                                Text("of \(strokes.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentStroke?.isPenalty == true)

                        Button(action: {
                            if selectedStrokeIndex < strokes.count - 1 {
                                saveCurrentStroke()
                                selectedStrokeIndex += 1
                                loadStrokeData()
                            }
                        }) {
                            Label("Next", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedStrokeIndex >= strokes.count - 1)
                    }
                }
                .padding(.horizontal)

                // Move stroke button
                if currentStroke?.isPenalty != true {
                    Button(action: {
                        guard let stroke = currentStroke else { return }
                        saveCurrentMapRegion()
                        strokeToMove = stroke
                        temporaryPosition = stroke.coordinate
                        isMovingStroke = true
                        dismiss()
                    }) {
                        Label("Move Stroke Position", systemImage: "location")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }

                // Delete stroke button
                if let _ = currentStroke {
                    Button(role: .destructive) {
                        guard let stroke = currentStroke else { return }
                        // Remove the stroke from the round in the data store
                        store.deleteStroke(in: round, stroke: stroke)
                        dismiss()
                    } label: {
                        Label("Delete Stroke", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .padding(.horizontal)
                }

                // Penalty stroke indicator
                if currentStroke?.isPenalty == true {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Penalty Stroke")
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                        Text("This is an automatic penalty stroke. All details are disabled.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }

                    Button(action: {
                        saveCurrentStroke()
                        dismiss()
                    }) {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(currentStroke?.isPenalty == true)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding(.top, 20)
            }
            .navigationTitle("Stroke Details")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadStrokeData()
            }
            .alert("Renumber Stroke", isPresented: $showingRenumberAlert) {
                TextField("Stroke number", text: $newStrokeNumber)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) {
                    newStrokeNumber = ""
                }
                Button("Update") {
                    if let stroke = currentStroke,
                       let number = Int(newStrokeNumber),
                       number > 0,
                       number <= strokes.count {
                        store.renumberStroke(in: round, stroke: stroke, newNumber: number)
                        // Update selected index if needed
                        if number - 1 != selectedStrokeIndex {
                            selectedStrokeIndex = number - 1
                        }
                        loadStrokeData()
                    }
                    newStrokeNumber = ""
                }
            } message: {
                Text("Enter new stroke number (1-\(strokes.count))")
            }
        }
    }

    private func loadStrokeData() {
        // No data to load anymore
    }

    private func saveCurrentStroke() {
        // No stroke details to save anymore
    }
}
