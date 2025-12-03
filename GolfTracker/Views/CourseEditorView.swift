import SwiftUI
import MapKit

struct CourseEditorView: View {
    @ObservedObject var store: DataStore
    let course: Course

    @StateObject private var locationManager = LocationManager()
    @State private var position = MapCameraPosition.automatic
    @State private var selectedHole: Hole?
    @State private var showingHoleActions = false
    @State private var showingRenumberAlert = false
    @State private var newHoleNumber = ""

    private var currentCourse: Course {
        store.courses.first { $0.id == course.id } ?? course
    }

    private var nearestHole: Hole? {
        guard let userLocation = locationManager.location else { return nil }
        guard !currentCourse.holes.isEmpty else { return nil }

        return currentCourse.holes.min { hole1, hole2 in
            let loc1 = CLLocation(latitude: hole1.latitude, longitude: hole1.longitude)
            let loc2 = CLLocation(latitude: hole2.latitude, longitude: hole2.longitude)
            return userLocation.distance(from: loc1) < userLocation.distance(from: loc2)
        }
    }
    
    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                ForEach(currentCourse.holes) { hole in
                    Annotation("", coordinate: hole.coordinate) {
                        HoleMarker(number: hole.number, isNearest: nearestHole?.id == hole.id)
                            .onTapGesture {
                                selectedHole = hole
                                showingHoleActions = true
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
            .mapStyle(.imagery)
            .onTapGesture { screenCoord in
                // Only add hole if not tapping near an existing hole
                if let coordinate = proxy.convert(screenCoord, from: .local),
                   !isTappingNearExistingHole(coordinate: coordinate) {
                    store.addHole(to: currentCourse, coordinate: coordinate)
                }
            }
        }
        .navigationTitle(currentCourse.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button(action: addHoleAtCurrentLocation) {
                    Label("Add Here", systemImage: "plus.circle.fill")
                }
                .disabled(locationManager.location == nil)

                Spacer()

                Button(action: moveNearestHoleToCurrentLocation) {
                    Label("Move Nearest", systemImage: "location.fill")
                }
                .disabled(nearestHole == nil || locationManager.location == nil)
            }
        }
        .confirmationDialog("Hole \(selectedHole?.number ?? 0)", isPresented: $showingHoleActions) {
            Button("Renumber") {
                if let hole = selectedHole {
                    newHoleNumber = "\(hole.number)"
                    showingRenumberAlert = true
                }
            }
            Button("Delete", role: .destructive) {
                if let hole = selectedHole {
                    store.deleteHole(hole, from: currentCourse)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Renumber Hole", isPresented: $showingRenumberAlert) {
            TextField("Hole number", text: $newHoleNumber)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                newHoleNumber = ""
            }
            Button("Update") {
                if let hole = selectedHole,
                   let number = Int(newHoleNumber),
                   number > 0,
                   number <= currentCourse.holes.count {
                    store.renumberHole(hole, in: currentCourse, newNumber: number)
                }
                newHoleNumber = ""
            }
        } message: {
            Text("Enter new hole number (1-\(currentCourse.holes.count))")
        }
        .onAppear {
            locationManager.requestPermission()
            if let firstHole = currentCourse.holes.first {
                position = .region(MKCoordinateRegion(
                    center: firstHole.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
    }

    private func isTappingNearExistingHole(coordinate: CLLocationCoordinate2D) -> Bool {
        let tappedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // Check if tap is within 10 meters of any existing hole
        for hole in currentCourse.holes {
            let holeLocation = CLLocation(latitude: hole.latitude, longitude: hole.longitude)
            if tappedLocation.distance(from: holeLocation) < 10 {
                return true
            }
        }
        return false
    }

    private func addHoleAtCurrentLocation() {
        guard let location = locationManager.location else { return }
        store.addHole(to: currentCourse, coordinate: location.coordinate)
    }

    private func moveNearestHoleToCurrentLocation() {
        guard let location = locationManager.location,
              let nearest = nearestHole else { return }
        store.updateHole(nearest, in: currentCourse, newCoordinate: location.coordinate)
    }
}

struct HoleMarker: View {
    let number: Int
    var isNearest: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isNearest ? .orange : .red)
                .frame(width: isNearest ? 35 : 30, height: isNearest ? 35 : 30)
            if isNearest {
                Circle()
                    .stroke(.yellow, lineWidth: 3)
                    .frame(width: 35, height: 35)
            }
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}
