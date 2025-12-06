import SwiftUI

struct HoleOverlayControls: View {
    let hole: Hole
    let strokeCount: Int
    let formattedDistance: String
    let errorMessage: String?
    let currentHoleIndex: Int
    let totalHoles: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onAddHole: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Distance display section
            VStack(spacing: 8) {
                Text(formattedDistance)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
            .padding(.top, 80)
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
                    Text("Strokes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(strokeCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)

            // Navigation controls
            HStack(spacing: 20) {
                Button(action: onPrevious) {
                    Label("Previous", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(currentHoleIndex == 0)

                if currentHoleIndex >= totalHoles - 1 {
                    Button(action: onAddHole) {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: onNext) {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .padding(.bottom, 20)
            .background(.ultraThinMaterial)
        }
    }
}
