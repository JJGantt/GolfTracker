import SwiftUI
import MapKit

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
