import SwiftUI
import MapKit

struct HolePlayView: View {
    @ObservedObject var store: DataStore
    let course: Course

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
    @State private var selectedStrokeForDetails: Stroke?
    @State private var selectedLength: StrokeLength? = nil
    @State private var selectedDirection: StrokeDirection? = nil
    @State private var selectedLocation: StrokeLocation? = nil

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

    private var mostRecentStroke: Stroke? {
        guard let round = currentRound,
              let hole = currentHole else { return nil }
        return round.strokes.filter { $0.holeNumber == hole.number }.last
    }

    private var floatingStrokeButton: some View {
        Image(systemName: "plus")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(width: 60, height: 60)
            .background(.green)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .opacity((locationManager.location == nil || activeRound == nil) ? 0.5 : 1.0)
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
            .opacity((mostRecentStroke == nil || locationManager.location == nil) ? 0.5 : 1.0)
    }

    var body: some View {
        ZStack {
            if let hole = currentHole {
                mapView(for: hole)

                overlayControls(for: hole)

                // Floating stroke buttons
                VStack {
                    Spacer()
                    HStack {
                        // Yellow button for stroke details (left side)
                        Button(action: {
                            if let stroke = mostRecentStroke {
                                selectedStrokeForDetails = stroke
                                selectedLength = nil
                                selectedDirection = nil
                                selectedLocation = nil
                                showingStrokeDetails = true
                            }
                        }) {
                            floatingDetailsButton
                        }
                        .disabled(mostRecentStroke == nil || locationManager.location == nil)
                        .padding(.leading, 20)
                        .padding(.bottom, 200)

                        Spacer()

                        // Green button for new stroke (right side)
                        Button(action: {
                            showingClubSelection = true
                        }) {
                            floatingStrokeButton
                        }
                        .disabled(locationManager.location == nil || activeRound == nil)
                        .padding(.trailing, 20)
                        .padding(.bottom, 200)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Holes",
                    systemImage: "flag.slash",
                    description: Text("This course doesn't have any holes yet. Add holes in the course editor.")
                )
            }
        }
        .ignoresSafeArea(edges: .all)
        .navigationTitle(currentCourse.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingEditMenu = true
                }) {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(currentHole == nil)
            }
        }
        .confirmationDialog("Edit Hole \(currentHole?.number ?? 0)", isPresented: $showingEditMenu) {
            Button("Move Hole Position") {
                showingMoveHoleConfirmation = true
            }
            .disabled(locationManager.location == nil)

            Button("Add Tee Marker") {
                showingAddTeeConfirmation = true
            }
            .disabled(locationManager.location == nil)

            Button("Edit Yards") {
                yardsInput = currentHole?.yards != nil ? "\(currentHole!.yards!)" : ""
                showingEditYards = true
            }

            Button("Edit Par") {
                parInput = currentHole?.par != nil ? "\(currentHole!.par!)" : ""
                showingEditPar = true
            }

            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Move Hole Position", isPresented: $showingMoveHoleConfirmation) {
            Button("Move Hole \(currentHole?.number ?? 0) Here", role: .destructive) {
                moveCurrentHoleToUserLocation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move this hole to your current GPS location?")
        }
        .confirmationDialog("Add Tee Marker", isPresented: $showingAddTeeConfirmation) {
            Button("Add Tee at Current Location") {
                addTeeMarkerAtCurrentLocation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Place the tee marker at your current GPS location? This will automatically calculate the hole yardage.")
        }
        .alert("Edit Hole Yards", isPresented: $showingEditYards) {
            TextField("Yards", text: $yardsInput)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                yardsInput = ""
            }
            Button("Save") {
                if let hole = currentHole {
                    let yards = yardsInput.isEmpty ? nil : Int(yardsInput)
                    store.updateHoleYards(hole, in: currentCourse, yards: yards)
                }
                yardsInput = ""
            }
        } message: {
            Text("Enter the total yards for hole \(currentHole?.number ?? 0)")
        }
        .alert("Edit Hole Par", isPresented: $showingEditPar) {
            TextField("Par", text: $parInput)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                parInput = ""
            }
            Button("Save") {
                if let hole = currentHole {
                    let par = parInput.isEmpty ? nil : Int(parInput)
                    store.updateHolePar(hole, in: currentCourse, par: par)
                }
                parInput = ""
            }
        } message: {
            Text("Enter the par for hole \(currentHole?.number ?? 0)")
        }
        .confirmationDialog("Select Club", isPresented: $showingClubSelection) {
            ForEach(Club.allCases, id: \.self) { club in
                Button(club.rawValue) {
                    recordStroke(with: club)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Which club did you use for this stroke?")
        }
        .sheet(isPresented: $showingStrokeDetails) {
            StrokeDetailsView(
                length: $selectedLength,
                direction: $selectedDirection,
                location: $selectedLocation,
                onSave: saveStrokeDetails
            )
        }
        .onAppear {
            locationManager.requestPermission()
            updateMapPosition()
            // Start round automatically
            if activeRound == nil {
                activeRound = store.startRound(for: currentCourse)
            }
        }
        .onChange(of: currentHoleIndex) { _, _ in
            updateMapPosition()
        }
        .onChange(of: locationManager.location) { _, _ in
            updateMapPosition()
        }
    }

    private func previousHole() {
        if currentHoleIndex > 0 {
            currentHoleIndex -= 1
        }
    }

    private func nextHole() {
        if currentHoleIndex < currentCourse.holes.count - 1 {
            currentHoleIndex += 1
        }
    }

    private func moveCurrentHoleToUserLocation() {
        guard let hole = currentHole,
              let location = locationManager.location else { return }
        store.updateHole(hole, in: currentCourse, newCoordinate: location.coordinate)
        updateMapPosition()
    }

    private func addTeeMarkerAtCurrentLocation() {
        guard let hole = currentHole,
              let location = locationManager.location else { return }
        store.updateTeeMarker(hole, in: currentCourse, teeCoordinate: location.coordinate)
        updateMapPosition()
    }

    private func recordStroke(with club: Club) {
        guard let round = activeRound,
              let hole = currentHole,
              let location = locationManager.location else { return }
        store.addStroke(to: round, holeNumber: hole.number, coordinate: location.coordinate, club: club)
    }

    private func saveStrokeDetails() {
        guard let round = activeRound,
              let stroke = selectedStrokeForDetails,
              let location = locationManager.location else { return }
        store.updateStrokeDetails(
            in: round,
            stroke: stroke,
            landingCoordinate: location.coordinate,
            length: selectedLength,
            direction: selectedDirection,
            location: selectedLocation
        )
    }

    @ViewBuilder
    private func overlayControls(for hole: Hole) -> some View {
        VStack(spacing: 0) {
            // Distance display section
            VStack(spacing: 8) {
                Text("Hole \(hole.number)")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(locationManager.formattedDistance(to: hole.coordinate))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)

                if let errorMessage = locationManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
            .padding(.top, 50)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)

            Spacer()

            // Hole info panel
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Hole")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(hole.number)")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text("Par")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let par = hole.par {
                        Text("\(par)")
                            .font(.title2)
                            .fontWeight(.bold)
                    } else {
                        Text("--")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text("Yards")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let yards = hole.yards {
                        Text("\(yards)")
                            .font(.title2)
                            .fontWeight(.bold)
                    } else {
                        Text("--")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text("Strokes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(strokeCountForCurrentHole)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)

            // Navigation controls
            HStack(spacing: 20) {
                Button(action: previousHole) {
                    Label("Previous", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(currentHoleIndex == 0)

                Button(action: nextHole) {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentHoleIndex >= currentCourse.holes.count - 1)
            }
            .padding()
            .padding(.bottom, 20)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func mapView(for hole: Hole) -> some View {
        MapReader { proxy in
            Map(position: $position) {
                // Show hole marker
                Annotation("", coordinate: hole.coordinate) {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 40, height: 40)
                        Image(systemName: "flag.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }

                // Show tee marker if set
                if let teeCoord = hole.teeCoordinate {
                    Annotation("", coordinate: teeCoord) {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 30, height: 30)
                            Circle()
                                .stroke(.black, lineWidth: 2)
                                .frame(width: 30, height: 30)
                            Text("T")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                        }
                    }
                }

                // Show strokes for current hole
                if let round = currentRound {
                    let strokesForHole = round.strokes.filter { $0.holeNumber == hole.number }
                    ForEach(strokesForHole) { stroke in
                        // Show stroke start position
                        Annotation("", coordinate: stroke.coordinate) {
                            GolfBallMarker(strokeNumber: stroke.strokeNumber)
                        }

                        // Show landing position if available
                        if let landingCoord = stroke.landingCoordinate {
                            Annotation("", coordinate: landingCoord) {
                                GolfBallMarker(strokeNumber: stroke.strokeNumber, size: 20)
                            }
                        }
                    }
                }

                // Show user location
                if let userLocation = locationManager.location {
                    Annotation("You", coordinate: userLocation.coordinate) {
                        ZStack {
                            Circle()
                                .fill(.blue)
                                .frame(width: 20, height: 20)
                            Circle()
                                .stroke(.white, lineWidth: 3)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
            }
            .mapStyle(.hybrid)
        }
    }

    private func updateMapPosition() {
        guard let hole = currentHole else { return }

        if let userLocation = locationManager.location {
            let userCoord = userLocation.coordinate
            let holeCoord = hole.coordinate
            let holeLocation = CLLocation(latitude: holeCoord.latitude, longitude: holeCoord.longitude)

            // Calculate distance in meters
            let distance = userLocation.distance(from: holeLocation)

            // Calculate bearing from user to hole (direction in degrees)
            let bearing = calculateBearing(from: userCoord, to: holeCoord)

            // Calculate span based on distance
            let spanInMeters = max(distance * 1.8, 40.0) // Minimum 40 meters view

            // Center point exactly between user and hole
            let centerLat = (holeCoord.latitude + userCoord.latitude) / 2.0
            let centerLon = (holeCoord.longitude + userCoord.longitude) / 2.0
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
        } else {
            // Just center on the hole
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
}

struct StrokeDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var length: StrokeLength?
    @Binding var direction: StrokeDirection?
    @Binding var location: StrokeLocation?
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Length section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Length")
                        .font(.headline)
                        .padding(.leading, 4)

                    HStack(spacing: 8) {
                        Button(action: { length = .redShort }) {
                            Text("Short")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(length == .redShort ? Color.red : Color.red.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: { length = .yellowShort }) {
                            Text("Short")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(length == .yellowShort ? Color.yellow : Color.yellow.opacity(0.3))
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }

                        Button(action: { length = .center }) {
                            Text("Center")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(length == .center ? Color.green : Color.green.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: { length = .yellowLong }) {
                            Text("Long")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(length == .yellowLong ? Color.yellow : Color.yellow.opacity(0.3))
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }

                        Button(action: { length = .redLong }) {
                            Text("Long")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(length == .redLong ? Color.red : Color.red.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)

                // Direction section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Direction")
                        .font(.headline)
                        .padding(.leading, 4)

                    HStack(spacing: 8) {
                        Button(action: { direction = .redLeft }) {
                            Text("Left")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(direction == .redLeft ? Color.red : Color.red.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: { direction = .yellowLeft }) {
                            Text("Left")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(direction == .yellowLeft ? Color.yellow : Color.yellow.opacity(0.3))
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }

                        Button(action: { direction = .center }) {
                            Text("Center")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(direction == .center ? Color.green : Color.green.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: { direction = .yellowRight }) {
                            Text("Right")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(direction == .yellowRight ? Color.yellow : Color.yellow.opacity(0.3))
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }

                        Button(action: { direction = .redRight }) {
                            Text("Right")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(direction == .redRight ? Color.red : Color.red.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)

                // Location section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location")
                        .font(.headline)
                        .padding(.leading, 4)

                    // Penalty locations
                    HStack(spacing: 8) {
                        Button(action: { location = .oob }) {
                            VStack(spacing: 2) {
                                Text("OOB")
                                    .font(.caption)
                                Text("+1")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(location == .oob ? Color.red : Color.red.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }

                        Button(action: { location = .hazard }) {
                            VStack(spacing: 2) {
                                Text("Hazard")
                                    .font(.caption)
                                Text("+1")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(location == .hazard ? Color.red : Color.red.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }

                        Button(action: { location = .unplayable }) {
                            VStack(spacing: 2) {
                                Text("Unplayable")
                                    .font(.caption)
                                Text("+1")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(location == .unplayable ? Color.red : Color.red.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }

                    // Regular locations
                    HStack(spacing: 8) {
                        Button(action: { location = .rough }) {
                            Text("Rough")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(location == .rough ? Color.blue : Color.blue.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: { location = .sand }) {
                            Text("Sand")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(location == .sand ? Color.orange : Color.orange.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: { location = .fairway }) {
                            Text("Fairway")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(location == .fairway ? Color.green : Color.green.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: { location = .green }) {
                            Text("Green")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(location == .green ? Color.green : Color.green.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

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
                        length = nil
                        direction = nil
                        location = nil
                        onSave()
                        dismiss()
                    }) {
                        Text("Skip")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: {
                        onSave()
                        dismiss()
                    }) {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding(.top, 20)
            .navigationTitle("Stroke Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct GolfBallMarker: View {
    let strokeNumber: Int
    var size: CGFloat = 25

    var body: some View {
        ZStack {
            // Main golf ball circle
            Circle()
                .fill(.white)
                .frame(width: size, height: size)

            // Shadow/3D effect
            Circle()
                .stroke(.gray.opacity(0.3), lineWidth: 1)
                .frame(width: size, height: size)

            // Dimples pattern
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(.gray.opacity(0.15))
                        .frame(width: size * 0.15, height: size * 0.15)
                        .offset(x: cos(Double(i) * .pi / 3) * (size * 0.25),
                                y: sin(Double(i) * .pi / 3) * (size * 0.25))
                }
            }

            // Stroke number
            Text("\(strokeNumber)")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.black)
        }
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}
