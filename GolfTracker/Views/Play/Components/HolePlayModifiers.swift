import SwiftUI
import MapKit

// MARK: - View Modifiers for HolePlayView

struct NavigationModifier: ViewModifier {
    @Binding var showingCourseEditor: Bool
    let store: DataStore
    let currentCourse: Course

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: $showingCourseEditor) {
                CourseEditorView(store: store, course: currentCourse)
            }
    }
}

struct EditMenuModifier: ViewModifier {
    @Binding var showingEditMenu: Bool
    @Binding var showingMoveHoleConfirmation: Bool
    @Binding var showingAddTeeConfirmation: Bool
    @Binding var showingEditYards: Bool
    @Binding var showingEditPar: Bool
    @Binding var showingCourseEditor: Bool
    let currentHole: Hole?
    let locationManager: LocationManager
    @Binding var yardsInput: String
    @Binding var parInput: String
    let isCurrentHoleCompleted: Bool
    let reopenHole: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Edit Hole \(currentHole?.number ?? 0)", isPresented: $showingEditMenu) {
                if isCurrentHoleCompleted {
                    Button("Reopen Hole") {
                        reopenHole()
                    }
                }

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

                Button("Edit Course") {
                    showingCourseEditor = true
                }

                Button("Cancel", role: .cancel) {}
            }
    }
}

struct HoleEditingModifier: ViewModifier {
    @Binding var showingMoveHoleConfirmation: Bool
    @Binding var showingAddTeeConfirmation: Bool
    @Binding var showingEditYards: Bool
    @Binding var showingEditPar: Bool
    @Binding var yardsInput: String
    @Binding var parInput: String
    let currentHole: Hole?
    let locationManager: LocationManager
    @Binding var temporaryPosition: CLLocationCoordinate2D?
    @Binding var isMovingHoleManually: Bool
    @Binding var isAddingTeeManually: Bool
    let store: DataStore
    let currentCourse: Course
    let moveCurrentHoleToUserLocation: () -> Void
    let addTeeMarkerAtCurrentLocation: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Move Hole Position", isPresented: $showingMoveHoleConfirmation) {
                Button("Move to Current Location") {
                    moveCurrentHoleToUserLocation()
                }
                .disabled(locationManager.location == nil)

                Button("Move Manually") {
                    temporaryPosition = currentHole?.coordinate
                    isMovingHoleManually = true
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose how to move hole \(currentHole?.number ?? 0)")
            }
            .confirmationDialog("Add Tee Marker", isPresented: $showingAddTeeConfirmation) {
                Button("Add at Current Location") {
                    addTeeMarkerAtCurrentLocation()
                }
                .disabled(locationManager.location == nil)

                Button("Add Manually") {
                    temporaryPosition = currentHole?.teeCoordinate
                    isAddingTeeManually = true
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose how to place the tee marker")
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
    }
}

struct ClubSelectionModifier: ViewModifier {
    @Binding var showingClubSelection: Bool
    @Binding var showingLongPressClubSelection: Bool
    @Binding var temporaryPosition: CLLocationCoordinate2D?
    let recordStroke: (Club) -> Void
    let recordLongPressStroke: (Club) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Select Club", isPresented: $showingClubSelection) {
                ForEach(Club.allCases, id: \.self) { club in
                    Button(club.rawValue) {
                        recordStroke(club)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Which club did you use for this stroke?")
            }
            .confirmationDialog("Select Club", isPresented: $showingLongPressClubSelection) {
                ForEach(Club.allCases, id: \.self) { club in
                    Button(club.rawValue) {
                        recordLongPressStroke(club)
                    }
                }
                Button("Cancel", role: .cancel) {
                    temporaryPosition = nil
                }
            } message: {
                Text("Which club did you use for this stroke?")
            }
    }
}

struct StrokeDetailsModifier: ViewModifier {
    @Binding var showingStrokeDetails: Bool
    let activeRound: Round?
    let strokesForCurrentHole: [Stroke]
    @Binding var selectedStrokeIndex: Int
    @Binding var isMovingStroke: Bool
    @Binding var strokeToMove: Stroke?
    @Binding var temporaryPosition: CLLocationCoordinate2D?
    @Binding var position: MapCameraPosition
    @Binding var savedMapRegion: MKCoordinateRegion?
    let store: DataStore

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingStrokeDetails) {
                if let round = activeRound {
                    StrokeDetailsView(
                        store: store,
                        round: round,
                        strokes: strokesForCurrentHole,
                        selectedStrokeIndex: $selectedStrokeIndex,
                        isMovingStroke: $isMovingStroke,
                        strokeToMove: $strokeToMove,
                        temporaryPosition: $temporaryPosition,
                        position: $position,
                        savedMapRegion: $savedMapRegion
                    )
                }
            }
    }
}
