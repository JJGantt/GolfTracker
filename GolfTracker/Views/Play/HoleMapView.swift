import SwiftUI
import MapKit

struct HoleMapView: View {
    let hole: Hole
    let currentRound: Round?
    let userLocation: CLLocation?
    let heading: CLLocationDirection?
    let useStandardMap: Bool
    @Binding var position: MapCameraPosition

    let onHoleTap: () -> Void
    let onTeeTap: () -> Void
    let onStrokeTap: (Int) -> Void

    private var isHoleCompleted: Bool {
        currentRound?.isHoleCompleted(hole.number) ?? false
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                // Show current hole marker (green if completed, yellow if not)
                Annotation("", coordinate: hole.coordinate) {
                    Image(systemName: "flag.fill")
                        .foregroundColor(isHoleCompleted ? .green : .yellow)
                        .font(.title)
                        .onTapGesture {
                            onHoleTap()
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
                        .onTapGesture {
                            onTeeTap()
                        }
                    }
                }

                // Show strokes for current hole
                if let round = currentRound {
                    let strokesForHole = round.strokes.filter { $0.holeNumber == hole.number }
                    ForEach(Array(strokesForHole.enumerated()), id: \.element.id) { index, stroke in
                        // Show stroke position
                        Annotation("", coordinate: stroke.coordinate) {
                            if stroke.isPenalty {
                                // Orange ball for penalty strokes
                                ZStack {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 25, height: 25)
                                    Text("\(stroke.strokeNumber)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .onTapGesture {
                                    onStrokeTap(index)
                                }
                            } else {
                                GolfBallMarker(strokeNumber: stroke.strokeNumber)
                                    .onTapGesture {
                                        onStrokeTap(index)
                                    }
                            }
                        }
                    }
                }

                // Show user location
                if let userLocation = userLocation {
                    Annotation("", coordinate: userLocation.coordinate) {
                        UserLocationMarker(heading: heading)
                    }
                }
            }
            .mapStyle(useStandardMap ? .standard : .hybrid)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
        }
    }
}
