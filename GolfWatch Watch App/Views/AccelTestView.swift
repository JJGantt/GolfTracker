import SwiftUI
import WatchKit

struct AccelTestView: View {
    @StateObject private var swingDetector = SwingDetectionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Button(swingDetector.isFrozen ? "reset" : "freeze_exts") {
                    swingDetector.toggleResetFreeze()
                }
                
                Button("add_detect") {
                    swingDetector.simulateSwing()
                }

                // Recording controls right under freeze_opts
                VStack(spacing: 4) {
                    if isRecording {
                        Text("Recording: \(swingDetector.recordedDataPoints.count) samples")
                            .font(.caption2)
                    }

     
                    Button(isRecording ? "Stop" : "Record") {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }


                    
                }

                Divider()

                // User Acceleration Table
                Text("User Accel (G)")
                    .font(.caption)
                Grid {
                    GridRow {
                        Text("")
                        Text("Cur").font(.caption2)
                        Text("Min").font(.caption2)
                        Text("Max").font(.caption2)
                    }
                    GridRow {
                        Text("M")
                        Text(String(format: "%.2f", swingDetector.userAccelMag))
                        Text("-")
                        Text(String(format: "%.2f", swingDetector.maxUserAccelMag))
                    }
                    GridRow {
                        Text("X")
                        Text(String(format: "%.2f", swingDetector.userAccelX))
                        Text(String(format: "%.2f", swingDetector.minUserAccelX))
                        Text(String(format: "%.2f", swingDetector.maxUserAccelX))
                    }
                    GridRow {
                        Text("Y")
                        Text(String(format: "%.2f", swingDetector.userAccelY))
                        Text(String(format: "%.2f", swingDetector.minUserAccelY))
                        Text(String(format: "%.2f", swingDetector.maxUserAccelY))
                    }
                    GridRow {
                        Text("Z")
                        Text(String(format: "%.2f", swingDetector.userAccelZ))
                        Text(String(format: "%.2f", swingDetector.minUserAccelZ))
                        Text(String(format: "%.2f", swingDetector.maxUserAccelZ))
                    }
                }
                .font(.system(size: 11, design: .monospaced))

                Divider()

                // Rotation Table
                Text("Rotation (rad/s)")
                    .font(.caption)
                Grid {
                    GridRow {
                        Text("")
                        Text("Cur").font(.caption2)
                        Text("Min").font(.caption2)
                        Text("Max").font(.caption2)
                    }
                    GridRow {
                        Text("M")
                        Text(String(format: "%.2f", swingDetector.rotationMag))
                        Text("-")
                        Text(String(format: "%.2f", swingDetector.maxRotationMag))
                    }
                    GridRow {
                        Text("X")
                        Text(String(format: "%.2f", swingDetector.rotationX))
                        Text(String(format: "%.2f", swingDetector.minRotationX))
                        Text(String(format: "%.2f", swingDetector.maxRotationX))
                    }
                    GridRow {
                        Text("Y")
                        Text(String(format: "%.2f", swingDetector.rotationY))
                        Text(String(format: "%.2f", swingDetector.minRotationY))
                        Text(String(format: "%.2f", swingDetector.maxRotationY))
                    }
                    GridRow {
                        Text("Z")
                        Text(String(format: "%.2f", swingDetector.rotationZ))
                        Text(String(format: "%.2f", swingDetector.minRotationZ))
                        Text(String(format: "%.2f", swingDetector.maxRotationZ))
                    }
                }
                .font(.system(size: 11, design: .monospaced))

                Divider()

                // Attitude Table
                Text("Attitude (rad)")
                    .font(.caption)
                Grid {
                    GridRow {
                        Text("")
                        Text("Cur").font(.caption2)
                        Text("Min").font(.caption2)
                        Text("Max").font(.caption2)
                    }
                    GridRow {
                        Text("Pitch")
                        Text(String(format: "%.2f", swingDetector.pitch))
                        Text(String(format: "%.2f", swingDetector.minPitch))
                        Text(String(format: "%.2f", swingDetector.maxPitch))
                    }
                    GridRow {
                        Text("Roll")
                        Text(String(format: "%.2f", swingDetector.roll))
                        Text(String(format: "%.2f", swingDetector.minRoll))
                        Text(String(format: "%.2f", swingDetector.maxRoll))
                    }
                    GridRow {
                        Text("Yaw")
                        Text(String(format: "%.2f", swingDetector.yaw))
                        Text(String(format: "%.2f", swingDetector.minYaw))
                        Text(String(format: "%.2f", swingDetector.maxYaw))
                    }
                }
                .font(.system(size: 11, design: .monospaced))

                Divider()

                // Gravity (just current, no min/max)
                Text("Gravity")
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("X: \(String(format: "%.2f", swingDetector.gravityX))")
                    Text("Y: \(String(format: "%.2f", swingDetector.gravityY))")
                    Text("Z: \(String(format: "%.2f", swingDetector.gravityZ))")
                }
                .font(.system(size: 11))

                Divider()

                // Last above threshold
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Above: \(String(format: "%.3f", swingDetector.lastTimeAboveThreshold)) s")
                        .font(.system(size: 11))
                }

                Divider()

                // Detection Mode - Radio buttons
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mode")
                        .font(.caption)

                    // Off option
                    Button(action: { swingDetector.detectionMode = .off }) {
                        HStack {
                            Image(systemName: swingDetector.detectionMode == .off ? "circle.fill" : "circle")
                                .font(.system(size: 12))
                            Text("Off")
                                .font(.system(size: 14))
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Naive option
                    Button(action: { swingDetector.detectionMode = .naiveDetect }) {
                        HStack {
                            Image(systemName: swingDetector.detectionMode == .naiveDetect ? "circle.fill" : "circle")
                                .font(.system(size: 12))
                            Text("naive_detect")
                                .font(.system(size: 14))
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Divider()

                // Parameters section - always visible
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parameters")
                        .font(.caption)

                    if swingDetector.detectionMode == .off {
                        Text("N/A")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    } else {
                        // Accel threshold
                        HStack {
                            Text("Accel: \(String(format: "%.1f", swingDetector.accelerationThreshold)) G")
                                .font(.system(size: 12))
                            Spacer()
                            Button("-") {
                                swingDetector.accelerationThreshold = max(0.1, swingDetector.accelerationThreshold - 0.1)
                            }
                            .font(.system(size: 12))
                            Button("+") {
                                swingDetector.accelerationThreshold = min(10.0, swingDetector.accelerationThreshold + 0.1)
                            }
                            .font(.system(size: 12))
                        }

                        // Accel time threshold
                        HStack {
                            Text("Accel T: \(String(format: "%.2f", swingDetector.accelTimeThreshold)) s")
                                .font(.system(size: 12))
                            Spacer()
                            Button("-") {
                                swingDetector.accelTimeThreshold = max(0.0, swingDetector.accelTimeThreshold - 0.01)
                            }
                            .font(.system(size: 12))
                            Button("+") {
                                swingDetector.accelTimeThreshold = min(1.0, swingDetector.accelTimeThreshold + 0.01)
                            }
                            .font(.system(size: 12))
                        }

                        // Rotation threshold
                        HStack {
                            Text("Rot: \(String(format: "%.1f", swingDetector.rotationThreshold)) r/s")
                                .font(.system(size: 12))
                            Spacer()
                            Button("-") {
                                swingDetector.rotationThreshold = max(1.0, swingDetector.rotationThreshold - 0.1)
                            }
                            .font(.system(size: 12))
                            Button("+") {
                                swingDetector.rotationThreshold = min(30.0, swingDetector.rotationThreshold + 0.1)
                            }
                            .font(.system(size: 12))
                        }

                        // Rotation time threshold
                        HStack {
                            Text("Rot T: \(String(format: "%.2f", swingDetector.rotationTimeThreshold)) s")
                                .font(.system(size: 12))
                            Spacer()
                            Button("-") {
                                swingDetector.rotationTimeThreshold = max(0.0, swingDetector.rotationTimeThreshold - 0.01)
                            }
                            .font(.system(size: 12))
                            Button("+") {
                                swingDetector.rotationTimeThreshold = min(1.0, swingDetector.rotationTimeThreshold + 0.01)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }

            }
            .padding()
        }
        .onAppear {
            // Start motion monitoring when view appears
            swingDetector.startMonitoring()
        }
        .onDisappear {
            // Stop motion monitoring when view disappears
            swingDetector.stopMonitoring()
        }
    }

    private func startRecording() {
        swingDetector.startRecording()
        isRecording = true
        WKInterfaceDevice.current().play(.start)
    }

    private func stopRecording() {
        swingDetector.stopRecording()
        isRecording = false
        WKInterfaceDevice.current().play(.stop)

        // Send data to phone for sharing
        swingDetector.sendRecordedDataToPhone()
    }
}

#Preview {
    AccelTestView()
}
