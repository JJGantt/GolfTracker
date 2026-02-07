import SwiftUI
import WatchKit

struct AccelTestView: View {
    @StateObject private var swingDetector = SwingDetectionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Button("Exit") {
                    dismiss()
                }

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
                    Button(action: { swingDetector.detectionMode = .off; swingDetector.resetToIdle() }) {
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
                    Button(action: { swingDetector.detectionMode = .naiveDetect; swingDetector.resetToIdle() }) {
                        HStack {
                            Image(systemName: swingDetector.detectionMode == .naiveDetect ? "circle.fill" : "circle")
                                .font(.system(size: 12))
                            Text("naive_detect")
                                .font(.system(size: 14))
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Smart option
                    Button(action: { swingDetector.detectionMode = .smartDetect; swingDetector.resetToIdle() }) {
                        HStack {
                            Image(systemName: swingDetector.detectionMode == .smartDetect ? "circle.fill" : "circle")
                                .font(.system(size: 12))
                            Text("smart_detect")
                                .font(.system(size: 14))
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Divider()

                // Parameters section - mode-specific
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parameters")
                        .font(.caption)

                    switch swingDetector.detectionMode {
                    case .off:
                        Text("N/A")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    case .naiveDetect:
                        paramRow("Accel:", value: swingDetector.accelerationThreshold, format: "%.1f", unit: "G",
                                 dec: { swingDetector.accelerationThreshold = max(0.1, swingDetector.accelerationThreshold - 0.1) },
                                 inc: { swingDetector.accelerationThreshold = min(10.0, swingDetector.accelerationThreshold + 0.1) })
                        paramRow("Accel T:", value: swingDetector.accelTimeThreshold, format: "%.2f", unit: "s",
                                 dec: { swingDetector.accelTimeThreshold = max(0.0, swingDetector.accelTimeThreshold - 0.01) },
                                 inc: { swingDetector.accelTimeThreshold = min(1.0, swingDetector.accelTimeThreshold + 0.01) })
                        paramRow("Rot:", value: swingDetector.rotationThreshold, format: "%.1f", unit: "r/s",
                                 dec: { swingDetector.rotationThreshold = max(1.0, swingDetector.rotationThreshold - 0.1) },
                                 inc: { swingDetector.rotationThreshold = min(30.0, swingDetector.rotationThreshold + 0.1) })
                        paramRow("Rot T:", value: swingDetector.rotationTimeThreshold, format: "%.2f", unit: "s",
                                 dec: { swingDetector.rotationTimeThreshold = max(0.0, swingDetector.rotationTimeThreshold - 0.01) },
                                 inc: { swingDetector.rotationTimeThreshold = min(1.0, swingDetector.rotationTimeThreshold + 0.01) })
                    case .smartDetect:
                        // Putt state indicator
                        Text("State: \(swingDetector.puttStateDescription)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.cyan)

                        Text("Setup").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("Window:", value: swingDetector.puttWindowSeconds, format: "%.1f", unit: "s",
                                 dec: { swingDetector.puttWindowSeconds = max(0.1, swingDetector.puttWindowSeconds - 0.1) },
                                 inc: { swingDetector.puttWindowSeconds = min(5.0, swingDetector.puttWindowSeconds + 0.1) })
                        paramRow("Std:", value: swingDetector.puttStabilityStdDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttStabilityStdDeg = max(1.0, swingDetector.puttStabilityStdDeg - 1.0) },
                                 inc: { swingDetector.puttStabilityStdDeg = min(90.0, swingDetector.puttStabilityStdDeg + 1.0) })
                        paramRow("Tol:", value: swingDetector.puttToleranceDeg, format: "%.2f", unit: "°",
                                 dec: { swingDetector.puttToleranceDeg = max(0.5, swingDetector.puttToleranceDeg - 0.125) },
                                 inc: { swingDetector.puttToleranceDeg = min(30.0, swingDetector.puttToleranceDeg + 0.125) })
                        paramRow("MinDur:", value: swingDetector.puttMinDurationS, format: "%.1f", unit: "s",
                                 dec: { swingDetector.puttMinDurationS = max(0.1, swingDetector.puttMinDurationS - 0.1) },
                                 inc: { swingDetector.puttMinDurationS = min(3.0, swingDetector.puttMinDurationS + 0.1) })
                        paramRow("P min:", value: swingDetector.puttPitchMinDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttPitchMinDeg -= 0.5 },
                                 inc: { swingDetector.puttPitchMinDeg += 0.5 })
                        paramRow("P max:", value: swingDetector.puttPitchMaxDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttPitchMaxDeg -= 0.5 },
                                 inc: { swingDetector.puttPitchMaxDeg += 0.5 })
                        paramRow("R min:", value: swingDetector.puttRollMinDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttRollMinDeg -= 0.5 },
                                 inc: { swingDetector.puttRollMinDeg += 0.5 })
                        paramRow("R max:", value: swingDetector.puttRollMaxDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttRollMaxDeg -= 0.5 },
                                 inc: { swingDetector.puttRollMaxDeg += 0.5 })

                        Text("Rotation").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("Th1:", value: swingDetector.puttRotThreshold1, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.puttRotThreshold1 = max(0.05, swingDetector.puttRotThreshold1 - 0.05) },
                                 inc: { swingDetector.puttRotThreshold1 = min(5.0, swingDetector.puttRotThreshold1 + 0.05) })
                        paramRow("Th2:", value: swingDetector.puttRotThreshold2, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.puttRotThreshold2 = max(0.05, swingDetector.puttRotThreshold2 - 0.05) },
                                 inc: { swingDetector.puttRotThreshold2 = min(5.0, swingDetector.puttRotThreshold2 + 0.05) })
                        paramRow("Srch1:", value: swingDetector.puttRotSearchWindow1, format: "%.1f", unit: "s",
                                 dec: { swingDetector.puttRotSearchWindow1 = max(0.5, swingDetector.puttRotSearchWindow1 - 0.5) },
                                 inc: { swingDetector.puttRotSearchWindow1 = min(10.0, swingDetector.puttRotSearchWindow1 + 0.5) })
                        paramRow("Srch2:", value: swingDetector.puttRotSearchWindow2, format: "%.1f", unit: "s",
                                 dec: { swingDetector.puttRotSearchWindow2 = max(0.5, swingDetector.puttRotSearchWindow2 - 0.5) },
                                 inc: { swingDetector.puttRotSearchWindow2 = min(10.0, swingDetector.puttRotSearchWindow2 + 0.5) })
                        paramRow("Evt1:", value: swingDetector.puttRotEventWindow1, format: "%.2f", unit: "s",
                                 dec: { swingDetector.puttRotEventWindow1 = max(0.01, swingDetector.puttRotEventWindow1 - 0.01) },
                                 inc: { swingDetector.puttRotEventWindow1 = min(1.0, swingDetector.puttRotEventWindow1 + 0.01) })
                        paramRow("Evt2:", value: swingDetector.puttRotEventWindow2, format: "%.2f", unit: "s",
                                 dec: { swingDetector.puttRotEventWindow2 = max(0.01, swingDetector.puttRotEventWindow2 - 0.01) },
                                 inc: { swingDetector.puttRotEventWindow2 = min(1.0, swingDetector.puttRotEventWindow2 + 0.01) })

                        Text("Orient Return").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("Tol:", value: swingDetector.puttOrientReturnTolDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttOrientReturnTolDeg = max(0.5, swingDetector.puttOrientReturnTolDeg - 0.5) },
                                 inc: { swingDetector.puttOrientReturnTolDeg = min(30.0, swingDetector.puttOrientReturnTolDeg + 0.5) })
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

    @ViewBuilder
    func paramRow(_ label: String, value: Double, format: String, unit: String,
                  dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        HStack {
            Text("\(label) \(String(format: format, value)) \(unit)")
                .font(.system(size: 11))
            Spacer()
            Button("-", action: dec).font(.system(size: 12))
            Button("+", action: inc).font(.system(size: 12))
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
