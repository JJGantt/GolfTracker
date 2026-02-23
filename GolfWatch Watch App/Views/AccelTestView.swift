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
                        Text("Recording: \(swingDetector.recordingBufferCount) samples")
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
                Text("Rotation (rad/s · °/s)")
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
                        radDegRateCell(swingDetector.rotationMag)
                        Text("-")
                        radDegRateCell(swingDetector.maxRotationMag)
                    }
                    GridRow {
                        Text("X")
                        radDegRateCell(swingDetector.rotationX)
                        radDegRateCell(swingDetector.minRotationX)
                        radDegRateCell(swingDetector.maxRotationX)
                    }
                    GridRow {
                        Text("Y")
                        radDegRateCell(swingDetector.rotationY)
                        radDegRateCell(swingDetector.minRotationY)
                        radDegRateCell(swingDetector.maxRotationY)
                    }
                    GridRow {
                        Text("Z")
                        radDegRateCell(swingDetector.rotationZ)
                        radDegRateCell(swingDetector.minRotationZ)
                        radDegRateCell(swingDetector.maxRotationZ)
                    }
                }
                .font(.system(size: 11, design: .monospaced))

                Divider()

                // Attitude Table
                Text("Attitude (rad · °)")
                    .font(.caption)
                if swingDetector.isFrozen {
                    Grid {
                        GridRow {
                            Text("")
                            Text("Cur").font(.caption2)
                            Text("Snap").font(.caption2)
                        }
                        GridRow {
                            Text("Pitch")
                            radDegCell(swingDetector.pitch)
                            radDegCell(swingDetector.frozenPitch)
                        }
                        GridRow {
                            Text("Roll")
                            radDegCell(swingDetector.roll)
                            radDegCell(swingDetector.frozenRoll)
                        }
                        GridRow {
                            Text("Yaw")
                            radDegCell(swingDetector.yaw)
                            radDegCell(swingDetector.frozenYaw)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                } else {
                    Grid {
                        GridRow {
                            Text("")
                            Text("Cur").font(.caption2)
                            Text("Min").font(.caption2)
                            Text("Max").font(.caption2)
                        }
                        GridRow {
                            Text("Pitch")
                            radDegCell(swingDetector.pitch)
                            radDegCell(swingDetector.minPitch)
                            radDegCell(swingDetector.maxPitch)
                        }
                        GridRow {
                            Text("Roll")
                            radDegCell(swingDetector.roll)
                            radDegCell(swingDetector.minRoll)
                            radDegCell(swingDetector.maxRoll)
                        }
                        GridRow {
                            Text("Yaw")
                            radDegCell(swingDetector.yaw)
                            radDegCell(swingDetector.minYaw)
                            radDegCell(swingDetector.maxYaw)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                }

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

                    Toggle("Require Contact", isOn: $swingDetector.requireContact)
                        .font(.system(size: 12))

                    Toggle("Auto Add", isOn: $swingDetector.autoAdd)
                        .font(.system(size: 12))
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
                        paramRow("Rot:", value: swingDetector.rotationThreshold, format: "%.0f", unit: "°/s",
                                 dec: { swingDetector.rotationThreshold = max(50.0, swingDetector.rotationThreshold - 5.0) },
                                 inc: { swingDetector.rotationThreshold = min(2000.0, swingDetector.rotationThreshold + 5.0) })
                        paramRow("Rot T:", value: swingDetector.rotationTimeThreshold, format: "%.2f", unit: "s",
                                 dec: { swingDetector.rotationTimeThreshold = max(0.0, swingDetector.rotationTimeThreshold - 0.01) },
                                 inc: { swingDetector.rotationTimeThreshold = min(1.0, swingDetector.rotationTimeThreshold + 0.01) })
                    case .smartDetect:
                        // Last detected swing type
                        if let lastSwing = swingDetector.lastDetectedSwing {
                            Text("Last: \(lastSwing.swingType.rawValue)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(swingTypeColor(lastSwing.swingType))
                        }

                        // Contact confirmation indicator (800Hz stream)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(swingDetector.contactConfirmedRecently ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text(swingDetector.contactConfirmedRecently ? "contact ✓" : "no contact")
                                .font(.system(size: 11))
                                .foregroundColor(swingDetector.contactConfirmedRecently ? .green : .secondary)
                        }

                        // Continuous log send button
                        Button("Send Log (\(swingDetector.continuousLogCount))") {
                            swingDetector.sendContinuousLog()
                        }
                        .font(.system(size: 11))

                        // Contact detection parameters
                        Text("Contact").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("Bump:", value: swingDetector.impactBumpThresh, format: "%.3f", unit: "G",
                                 dec: { swingDetector.impactBumpThresh = max(0.010, swingDetector.impactBumpThresh - 0.005) },
                                 inc: { swingDetector.impactBumpThresh = min(0.200, swingDetector.impactBumpThresh + 0.005) })
                        paramRow("Trough:", value: swingDetector.impactTroughRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.impactTroughRatio = max(0.5, swingDetector.impactTroughRatio - 0.1) },
                                 inc: { swingDetector.impactTroughRatio = min(5.0, swingDetector.impactTroughRatio + 0.1) })
                        paramRow("Rebound:", value: swingDetector.impactReboundRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.impactReboundRatio = max(0.5, swingDetector.impactReboundRatio - 0.1) },
                                 inc: { swingDetector.impactReboundRatio = min(5.0, swingDetector.impactReboundRatio + 0.1) })

                        // Boundary parameters
                        Text("Boundaries").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("P/Pt:", value: swingDetector.puttPartialBoundary, format: "%.1f", unit: "r/s",
                                 dec: { swingDetector.puttPartialBoundary = max(1.0, swingDetector.puttPartialBoundary - 0.5) },
                                 inc: { swingDetector.puttPartialBoundary = min(15.0, swingDetector.puttPartialBoundary + 0.5) })
                        paramRow("Pt/F:", value: swingDetector.partialFullBoundary, format: "%.1f", unit: "r/s",
                                 dec: { swingDetector.partialFullBoundary = max(10.0, swingDetector.partialFullBoundary - 1.0) },
                                 inc: { swingDetector.partialFullBoundary = min(50.0, swingDetector.partialFullBoundary + 1.0) })

                        // Putt params
                        Text("Putt").font(.system(size: 10, weight: .bold)).foregroundColor(.cyan)
                        paramRow("RotCeil:", value: swingDetector.puttSetupRotMagCeiling, format: "%.3f", unit: "r/s",
                                 dec: { swingDetector.puttSetupRotMagCeiling = max(0.01, swingDetector.puttSetupRotMagCeiling - 0.01) },
                                 inc: { swingDetector.puttSetupRotMagCeiling = min(2.0, swingDetector.puttSetupRotMagCeiling + 0.01) })
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
                        paramRow("FS/BS min:", value: swingDetector.puttMinFSBSRatio, format: "%.2f", unit: "x",
                                 dec: { swingDetector.puttMinFSBSRatio = max(0.5, swingDetector.puttMinFSBSRatio - 0.05) },
                                 inc: { swingDetector.puttMinFSBSRatio = min(5.0, swingDetector.puttMinFSBSRatio + 0.05) })
                        paramRow("FS/BS max:", value: swingDetector.puttMaxFSBSRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.puttMaxFSBSRatio = max(1.0, swingDetector.puttMaxFSBSRatio - 0.5) },
                                 inc: { swingDetector.puttMaxFSBSRatio = min(20.0, swingDetector.puttMaxFSBSRatio + 0.5) })
                        paramRow("RotZ ceil:", value: swingDetector.puttRotZCeiling, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.puttRotZCeiling = max(0.05, swingDetector.puttRotZCeiling - 0.05) },
                                 inc: { swingDetector.puttRotZCeiling = min(3.0, swingDetector.puttRotZCeiling + 0.05) })

                        // Partial params
                        Text("Partial").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
                        paramRow("RotCeil:", value: swingDetector.partialSetupRotMagCeiling, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.partialSetupRotMagCeiling = max(0.1, swingDetector.partialSetupRotMagCeiling - 0.1) },
                                 inc: { swingDetector.partialSetupRotMagCeiling = min(5.0, swingDetector.partialSetupRotMagCeiling + 0.1) })
                        paramRow("MinDur:", value: swingDetector.partialMinDurationS, format: "%.1f", unit: "s",
                                 dec: { swingDetector.partialMinDurationS = max(0.1, swingDetector.partialMinDurationS - 0.1) },
                                 inc: { swingDetector.partialMinDurationS = min(3.0, swingDetector.partialMinDurationS + 0.1) })
                        paramRow("BS dur:", value: swingDetector.partialBsMinDurationS, format: "%.1f", unit: "s",
                                 dec: { swingDetector.partialBsMinDurationS = max(0.1, swingDetector.partialBsMinDurationS - 0.1) },
                                 inc: { swingDetector.partialBsMinDurationS = min(3.0, swingDetector.partialBsMinDurationS + 0.1) })
                        paramRow("RotZ:", value: swingDetector.partialRotZThreshold, format: "%.1f", unit: "r/s",
                                 dec: { swingDetector.partialRotZThreshold -= 0.1 },
                                 inc: { swingDetector.partialRotZThreshold += 0.1 })
                        paramRow("FS/BS min:", value: swingDetector.partialMinFSBSRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.partialMinFSBSRatio = max(1.0, swingDetector.partialMinFSBSRatio - 0.5) },
                                 inc: { swingDetector.partialMinFSBSRatio = min(10.0, swingDetector.partialMinFSBSRatio + 0.5) })
                        paramRow("FS/BS max:", value: swingDetector.partialMaxFSBSRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.partialMaxFSBSRatio = max(2.0, swingDetector.partialMaxFSBSRatio - 0.5) },
                                 inc: { swingDetector.partialMaxFSBSRatio = min(20.0, swingDetector.partialMaxFSBSRatio + 0.5) })

                        // Full swing params
                        Text("Full").font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                        paramRow("RotCeil:", value: swingDetector.fullSetupRotMagCeiling, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.fullSetupRotMagCeiling = max(0.1, swingDetector.fullSetupRotMagCeiling - 0.1) },
                                 inc: { swingDetector.fullSetupRotMagCeiling = min(5.0, swingDetector.fullSetupRotMagCeiling + 0.1) })
                        paramRow("MinDur:", value: swingDetector.fullMinDurationS, format: "%.1f", unit: "s",
                                 dec: { swingDetector.fullMinDurationS = max(0.1, swingDetector.fullMinDurationS - 0.1) },
                                 inc: { swingDetector.fullMinDurationS = min(3.0, swingDetector.fullMinDurationS + 0.1) })
                        paramRow("BS rotX:", value: swingDetector.fullBsRotXMin, format: "%.1f", unit: "r/s",
                                 dec: { swingDetector.fullBsRotXMin = max(0.5, swingDetector.fullBsRotXMin - 0.5) },
                                 inc: { swingDetector.fullBsRotXMin = min(10.0, swingDetector.fullBsRotXMin + 0.5) })
                        paramRow("BS YZ:", value: swingDetector.fullBsYZRatioMax, format: "%.2f", unit: "x",
                                 dec: { swingDetector.fullBsYZRatioMax = max(0.05, swingDetector.fullBsYZRatioMax - 0.05) },
                                 inc: { swingDetector.fullBsYZRatioMax = min(1.0, swingDetector.fullBsYZRatioMax + 0.05) })
                        paramRow("FS/BS min:", value: swingDetector.fullMinFSBSRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.fullMinFSBSRatio = max(1.0, swingDetector.fullMinFSBSRatio - 0.5) },
                                 inc: { swingDetector.fullMinFSBSRatio = min(10.0, swingDetector.fullMinFSBSRatio + 0.5) })
                        paramRow("FS/BS max:", value: swingDetector.fullMaxFSBSRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.fullMaxFSBSRatio = max(2.0, swingDetector.fullMaxFSBSRatio - 0.5) },
                                 inc: { swingDetector.fullMaxFSBSRatio = min(20.0, swingDetector.fullMaxFSBSRatio + 0.5) })
                    }
                }

            }
            .padding()
        }
        .onAppear {
            swingDetector.startMonitoring()
            swingDetector.isUIObserving = true
        }
        .onDisappear {
            swingDetector.isUIObserving = false
        }
    }

    private func swingTypeColor(_ type: SwingType) -> Color {
        switch type {
        case .putt: return .cyan
        case .partial: return .green
        case .fullSwing: return .orange
        }
    }

    @ViewBuilder
    func radDegCell(_ radValue: Double) -> some View {
        VStack(spacing: 0) {
            Text(String(format: "%.2f", radValue))
            Text(String(format: "%.1f°", radValue * 180.0 / .pi))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    func radDegRateCell(_ radPerSec: Double) -> some View {
        VStack(spacing: 0) {
            Text(String(format: "%.2f", radPerSec))
            Text(String(format: "%.1f°", radPerSec * 180.0 / .pi))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
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
        isRecording = false
        WKInterfaceDevice.current().play(.stop)

        swingDetector.stopRecording {
            self.swingDetector.sendRecordedDataToPhone()
        }
    }
}

#Preview {
    AccelTestView()
}
