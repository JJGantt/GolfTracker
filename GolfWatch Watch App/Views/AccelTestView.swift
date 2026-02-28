import SwiftUI
import WatchKit

struct AccelTestView: View {
    @StateObject private var swingDetector = SwingDetectionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Motion Config")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.bottom, 4)

                if !swingDetector.rawAccelAuthOK {
                    VStack(spacing: 2) {
                        Text("800Hz Accel Not Authorized")
                            .font(.caption2).bold()
                        Text("Settings > Privacy >\nMotion & Fitness")
                            .font(.system(size: 10))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.cornerRadius(6))
                }

                Button(swingDetector.isFrozen ? "reset" : "freeze_exts") {
                    swingDetector.toggleResetFreeze()
                }

                Button("add_detect") {
                    swingDetector.simulateSwing()
                }

                // Recording controls
                VStack(spacing: 4) {
                    if isRecording {
                        Text("Recording: \(swingDetector.recordingBufferCount) samples")
                            .font(.caption2)
                    }

                    HStack(spacing: 8) {
                        Button(isRecording ? "Stop" : "Record") {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        }

                        Button("Snapshot 3m") {
                            swingDetector.sendRollingBufferSnapshot()
                            WKInterfaceDevice.current().play(.click)
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

                    Button(action: { swingDetector.detectionMode = .unifiedDetect; swingDetector.resetToIdle() }) {
                        HStack {
                            Image(systemName: swingDetector.detectionMode == .unifiedDetect ? "circle.fill" : "circle")
                                .font(.system(size: 12))
                            Text("smart_2.1")
                                .font(.system(size: 14))
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: { swingDetector.detectionMode = .unifDetect; swingDetector.resetToIdle() }) {
                        HStack {
                            Image(systemName: swingDetector.detectionMode == .unifDetect ? "circle.fill" : "circle")
                                .font(.system(size: 12))
                            Text("unif_detect")
                                .font(.system(size: 14))
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    Toggle("Require Contact", isOn: $swingDetector.requireContact)
                        .font(.system(size: 12))

                    Toggle("Auto Add", isOn: $swingDetector.autoAdd)
                        .font(.system(size: 12))

                    Toggle("Ignore Practice", isOn: $swingDetector.ignorePractice)
                        .font(.system(size: 12))

                    if swingDetector.ignorePractice {
                        paramRow("Radius", value: swingDetector.ignorePracticeRadius, format: "%.0f", unit: "yd",
                                 dec: { swingDetector.ignorePracticeRadius = max(1.0, swingDetector.ignorePracticeRadius - 1.0) },
                                 inc: { swingDetector.ignorePracticeRadius = min(50.0, swingDetector.ignorePracticeRadius + 1.0) })
                    }
                }

                Divider()

                // Send Log button (above Parameters for modes that have it)
                if swingDetector.detectionMode == .smartDetect || swingDetector.detectionMode == .unifiedDetect || swingDetector.detectionMode == .unifDetect {
                    Button("Send Log (\(swingDetector.continuousLogCount))") {
                        swingDetector.sendContinuousLog()
                    }
                    .font(.system(size: 11))

                    Divider()
                }

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
                        paramRow("Accel", value: swingDetector.accelerationThreshold, format: "%.1f", unit: "G",
                                 dec: { swingDetector.accelerationThreshold = max(0.1, swingDetector.accelerationThreshold - 0.1) },
                                 inc: { swingDetector.accelerationThreshold = min(10.0, swingDetector.accelerationThreshold + 0.1) })
                        paramRow("Accel T", value: swingDetector.accelTimeThreshold, format: "%.2f", unit: "s",
                                 dec: { swingDetector.accelTimeThreshold = max(0.0, swingDetector.accelTimeThreshold - 0.01) },
                                 inc: { swingDetector.accelTimeThreshold = min(1.0, swingDetector.accelTimeThreshold + 0.01) })
                        paramRow("Rot", value: swingDetector.rotationThreshold, format: "%.0f", unit: "°/s",
                                 dec: { swingDetector.rotationThreshold = max(50.0, swingDetector.rotationThreshold - 5.0) },
                                 inc: { swingDetector.rotationThreshold = min(2000.0, swingDetector.rotationThreshold + 5.0) })
                        paramRow("Rot T", value: swingDetector.rotationTimeThreshold, format: "%.2f", unit: "s",
                                 dec: { swingDetector.rotationTimeThreshold = max(0.0, swingDetector.rotationTimeThreshold - 0.01) },
                                 inc: { swingDetector.rotationTimeThreshold = min(1.0, swingDetector.rotationTimeThreshold + 0.01) })

                    case .smartDetect:
                        // Last detected swing type
                        if let lastSwing = swingDetector.lastDetectedSwing {
                            Text("Last: \(lastSwing.swingType.rawValue)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(swingTypeColor(lastSwing.swingType))
                        }

                        // Contact detection parameters (TV-based)
                        Text("Contact (TV)").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("Prom", value: swingDetector.contactTVProminence, format: "%.3f", unit: "G",
                                 dec: { swingDetector.contactTVProminence = max(0.001, swingDetector.contactTVProminence - 0.005) },
                                 inc: { swingDetector.contactTVProminence = min(0.200, swingDetector.contactTVProminence + 0.005) })
                        paramRow("TV Thresh", value: swingDetector.contactTVThreshold, format: "%.2f", unit: "G",
                                 dec: { swingDetector.contactTVThreshold = max(0.01, swingDetector.contactTVThreshold - 0.01) },
                                 inc: { swingDetector.contactTVThreshold = min(5.0, swingDetector.contactTVThreshold + 0.01) })
                        paramRow("BL Thresh", value: swingDetector.baselineTVThreshold, format: "%.2f", unit: "G",
                                 dec: { swingDetector.baselineTVThreshold = max(0.01, swingDetector.baselineTVThreshold - 0.01) },
                                 inc: { swingDetector.baselineTVThreshold = min(1.0, swingDetector.baselineTVThreshold + 0.01) })
                        paramRow("Win R", value: swingDetector.contactTVWindowRight, format: "%.2f", unit: "s",
                                 dec: { swingDetector.contactTVWindowRight = max(0.05, swingDetector.contactTVWindowRight - 0.05) },
                                 inc: { swingDetector.contactTVWindowRight = min(1.0, swingDetector.contactTVWindowRight + 0.05) })

                        // Boundary parameters
                        Text("Boundaries").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("P/S", value: swingDetector.puttPartialBoundary, format: "%.1f", unit: "r/s",
                                 dec: { swingDetector.puttPartialBoundary = max(1.0, swingDetector.puttPartialBoundary - 0.5) },
                                 inc: { swingDetector.puttPartialBoundary = min(15.0, swingDetector.puttPartialBoundary + 0.5) })

                        // Putt params
                        Text("Putt").font(.system(size: 10, weight: .bold)).foregroundColor(.cyan)
                        paramRow("RotCeil", value: swingDetector.puttSetupRotMagCeiling, format: "%.3f", unit: "r/s",
                                 dec: { swingDetector.puttSetupRotMagCeiling = max(0.01, swingDetector.puttSetupRotMagCeiling - 0.01) },
                                 inc: { swingDetector.puttSetupRotMagCeiling = min(2.0, swingDetector.puttSetupRotMagCeiling + 0.01) })
                        paramRow("MinDur", value: swingDetector.puttMinDurationS, format: "%.1f", unit: "s",
                                 dec: { swingDetector.puttMinDurationS = max(0.1, swingDetector.puttMinDurationS - 0.1) },
                                 inc: { swingDetector.puttMinDurationS = min(3.0, swingDetector.puttMinDurationS + 0.1) })
                        paramRow("P min", value: swingDetector.puttPitchMinDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttPitchMinDeg -= 0.5 },
                                 inc: { swingDetector.puttPitchMinDeg += 0.5 })
                        paramRow("P max", value: swingDetector.puttPitchMaxDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttPitchMaxDeg -= 0.5 },
                                 inc: { swingDetector.puttPitchMaxDeg += 0.5 })
                        paramRow("R min", value: swingDetector.puttRollMinDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttRollMinDeg -= 0.5 },
                                 inc: { swingDetector.puttRollMinDeg += 0.5 })
                        paramRow("R max", value: swingDetector.puttRollMaxDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttRollMaxDeg -= 0.5 },
                                 inc: { swingDetector.puttRollMaxDeg += 0.5 })
                        paramRow("FS/BS min", value: swingDetector.puttMinFSBSRatio, format: "%.2f", unit: "x",
                                 dec: { swingDetector.puttMinFSBSRatio = max(0.5, swingDetector.puttMinFSBSRatio - 0.05) },
                                 inc: { swingDetector.puttMinFSBSRatio = min(5.0, swingDetector.puttMinFSBSRatio + 0.05) })
                        paramRow("FS/BS max", value: swingDetector.puttMaxFSBSRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.puttMaxFSBSRatio = max(1.0, swingDetector.puttMaxFSBSRatio - 0.5) },
                                 inc: { swingDetector.puttMaxFSBSRatio = min(20.0, swingDetector.puttMaxFSBSRatio + 0.5) })
                        paramRow("RotZ ceil", value: swingDetector.puttRotZCeiling, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.puttRotZCeiling = max(0.05, swingDetector.puttRotZCeiling - 0.05) },
                                 inc: { swingDetector.puttRotZCeiling = min(3.0, swingDetector.puttRotZCeiling + 0.05) })

                        // Full swing params
                        Text("Swing").font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                        paramRow("RotCeil", value: swingDetector.fullSetupRotMagCeiling, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.fullSetupRotMagCeiling = max(0.1, swingDetector.fullSetupRotMagCeiling - 0.1) },
                                 inc: { swingDetector.fullSetupRotMagCeiling = min(5.0, swingDetector.fullSetupRotMagCeiling + 0.1) })
                        paramRow("MinDur", value: swingDetector.fullMinDurationS, format: "%.1f", unit: "s",
                                 dec: { swingDetector.fullMinDurationS = max(0.1, swingDetector.fullMinDurationS - 0.1) },
                                 inc: { swingDetector.fullMinDurationS = min(3.0, swingDetector.fullMinDurationS + 0.1) })
                        paramRow("BS rotX", value: swingDetector.fullBsRotXMin, format: "%.1f", unit: "r/s",
                                 dec: { swingDetector.fullBsRotXMin = max(0.5, swingDetector.fullBsRotXMin - 0.5) },
                                 inc: { swingDetector.fullBsRotXMin = min(10.0, swingDetector.fullBsRotXMin + 0.5) })
                        paramRow("BS YZ", value: swingDetector.fullBsYZRatioMax, format: "%.2f", unit: "x",
                                 dec: { swingDetector.fullBsYZRatioMax = max(0.05, swingDetector.fullBsYZRatioMax - 0.05) },
                                 inc: { swingDetector.fullBsYZRatioMax = min(1.0, swingDetector.fullBsYZRatioMax + 0.05) })
                        paramRow("FS/BS min", value: swingDetector.fullMinFSBSRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.fullMinFSBSRatio = max(1.0, swingDetector.fullMinFSBSRatio - 0.5) },
                                 inc: { swingDetector.fullMinFSBSRatio = min(10.0, swingDetector.fullMinFSBSRatio + 0.5) })
                        paramRow("FS/BS max", value: swingDetector.fullMaxFSBSRatio, format: "%.1f", unit: "x",
                                 dec: { swingDetector.fullMaxFSBSRatio = max(2.0, swingDetector.fullMaxFSBSRatio - 0.5) },
                                 inc: { swingDetector.fullMaxFSBSRatio = min(20.0, swingDetector.fullMaxFSBSRatio + 0.5) })

                    case .unifiedDetect:
                        // Last detected swing type
                        if let lastSwing = swingDetector.lastDetectedSwing {
                            Text("Last: \(lastSwing.swingType.rawValue)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(swingTypeColor(lastSwing.swingType))
                        }

                        // Contact detection parameters (TV-based)
                        Text("Contact (TV)").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("Prom", value: swingDetector.contactTVProminence, format: "%.3f", unit: "G",
                                 dec: { swingDetector.contactTVProminence = max(0.001, swingDetector.contactTVProminence - 0.005) },
                                 inc: { swingDetector.contactTVProminence = min(0.200, swingDetector.contactTVProminence + 0.005) })
                        paramRow("TV Thresh", value: swingDetector.contactTVThreshold, format: "%.2f", unit: "G",
                                 dec: { swingDetector.contactTVThreshold = max(0.01, swingDetector.contactTVThreshold - 0.01) },
                                 inc: { swingDetector.contactTVThreshold = min(5.0, swingDetector.contactTVThreshold + 0.01) })
                        paramRow("BL Thresh", value: swingDetector.baselineTVThreshold, format: "%.2f", unit: "G",
                                 dec: { swingDetector.baselineTVThreshold = max(0.01, swingDetector.baselineTVThreshold - 0.01) },
                                 inc: { swingDetector.baselineTVThreshold = min(1.0, swingDetector.baselineTVThreshold + 0.01) })
                        paramRow("Win R", value: swingDetector.contactTVWindowRight, format: "%.2f", unit: "s",
                                 dec: { swingDetector.contactTVWindowRight = max(0.05, swingDetector.contactTVWindowRight - 0.05) },
                                 inc: { swingDetector.contactTVWindowRight = min(1.0, swingDetector.contactTVWindowRight + 0.05) })

                        // Boundary parameters
                        Text("Boundaries").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("P/S", value: swingDetector.puttPartialBoundary, format: "%.1f", unit: "r/s",
                                 dec: { swingDetector.puttPartialBoundary = max(1.0, swingDetector.puttPartialBoundary - 0.5) },
                                 inc: { swingDetector.puttPartialBoundary = min(15.0, swingDetector.puttPartialBoundary + 0.5) })

                        // Orientation bounds (shared)
                        Text("Orientation").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("P min", value: swingDetector.puttPitchMinDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttPitchMinDeg -= 0.5 },
                                 inc: { swingDetector.puttPitchMinDeg += 0.5 })
                        paramRow("P max", value: swingDetector.puttPitchMaxDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttPitchMaxDeg -= 0.5 },
                                 inc: { swingDetector.puttPitchMaxDeg += 0.5 })
                        paramRow("R min", value: swingDetector.puttRollMinDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttRollMinDeg -= 0.5 },
                                 inc: { swingDetector.puttRollMinDeg += 0.5 })
                        paramRow("R max", value: swingDetector.puttRollMaxDeg, format: "%.1f", unit: "°",
                                 dec: { swingDetector.puttRollMaxDeg -= 0.5 },
                                 inc: { swingDetector.puttRollMaxDeg += 0.5 })

                        // Putt event detector params
                        Text("Putt Event").font(.system(size: 10, weight: .bold)).foregroundColor(.cyan)
                        paramRow("Ceiling", value: swingDetector.uPuttSetupCeiling, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.uPuttSetupCeiling = max(0.05, swingDetector.uPuttSetupCeiling - 0.05) },
                                 inc: { swingDetector.uPuttSetupCeiling = min(2.0, swingDetector.uPuttSetupCeiling + 0.05) })
                        paramRow("MinDur", value: swingDetector.uPuttSetupMinDur, format: "%.2f", unit: "s",
                                 dec: { swingDetector.uPuttSetupMinDur = max(0.05, swingDetector.uPuttSetupMinDur - 0.05) },
                                 inc: { swingDetector.uPuttSetupMinDur = min(2.0, swingDetector.uPuttSetupMinDur + 0.05) })
                        paramRow("ValProm", value: swingDetector.uPuttValleyProm, format: "%.3f", unit: "",
                                 dec: { swingDetector.uPuttValleyProm = max(0.01, swingDetector.uPuttValleyProm - 0.01) },
                                 inc: { swingDetector.uPuttValleyProm = min(1.0, swingDetector.uPuttValleyProm + 0.01) })
                        paramRow("PkProm", value: swingDetector.uPuttPeakProm, format: "%.3f", unit: "",
                                 dec: { swingDetector.uPuttPeakProm = max(0.01, swingDetector.uPuttPeakProm - 0.01) },
                                 inc: { swingDetector.uPuttPeakProm = min(1.0, swingDetector.uPuttPeakProm + 0.01) })
                        paramRow("AreaW", value: swingDetector.uPuttAreaWindow, format: "%.2f", unit: "s",
                                 dec: { swingDetector.uPuttAreaWindow = max(0.05, swingDetector.uPuttAreaWindow - 0.05) },
                                 inc: { swingDetector.uPuttAreaWindow = min(1.0, swingDetector.uPuttAreaWindow + 0.05) })

                        // Swing event detector params
                        Text("Swing Event").font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                        paramRow("Area Thresh", value: swingDetector.swingAreaThreshold, format: "%.1f", unit: "",
                                 dec: { swingDetector.swingAreaThreshold = max(1.0, swingDetector.swingAreaThreshold - 1.0) },
                                 inc: { swingDetector.swingAreaThreshold = min(50.0, swingDetector.swingAreaThreshold + 1.0) })
                        paramRow("Ceiling", value: swingDetector.uSwingSetupCeiling, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.uSwingSetupCeiling = max(0.1, swingDetector.uSwingSetupCeiling - 0.1) },
                                 inc: { swingDetector.uSwingSetupCeiling = min(5.0, swingDetector.uSwingSetupCeiling + 0.1) })
                        paramRow("MinDur", value: swingDetector.uSwingSetupMinDur, format: "%.2f", unit: "s",
                                 dec: { swingDetector.uSwingSetupMinDur = max(0.05, swingDetector.uSwingSetupMinDur - 0.05) },
                                 inc: { swingDetector.uSwingSetupMinDur = min(2.0, swingDetector.uSwingSetupMinDur + 0.05) })
                        paramRow("ValProm", value: swingDetector.uSwingValleyProm, format: "%.3f", unit: "",
                                 dec: { swingDetector.uSwingValleyProm = max(0.01, swingDetector.uSwingValleyProm - 0.01) },
                                 inc: { swingDetector.uSwingValleyProm = min(2.0, swingDetector.uSwingValleyProm + 0.01) })
                        paramRow("PkProm", value: swingDetector.uSwingPeakProm, format: "%.3f", unit: "",
                                 dec: { swingDetector.uSwingPeakProm = max(0.05, swingDetector.uSwingPeakProm - 0.05) },
                                 inc: { swingDetector.uSwingPeakProm = min(5.0, swingDetector.uSwingPeakProm + 0.05) })
                        paramRow("AreaW", value: swingDetector.uSwingAreaWindow, format: "%.2f", unit: "s",
                                 dec: { swingDetector.uSwingAreaWindow = max(0.05, swingDetector.uSwingAreaWindow - 0.05) },
                                 inc: { swingDetector.uSwingAreaWindow = min(1.0, swingDetector.uSwingAreaWindow + 0.05) })

                        // Swing contact (rotX spike) params
                        Text("Swing Contact").font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                        paramRow("ΔrotX", value: swingDetector.swingContactDelta, format: "%.1f", unit: "r/s",
                                 dec: { swingDetector.swingContactDelta = max(1.0, swingDetector.swingContactDelta - 0.5) },
                                 inc: { swingDetector.swingContactDelta = min(20.0, swingDetector.swingContactDelta + 0.5) })
                        paramRow("Samples", value: Double(swingDetector.swingContactSamples), format: "%.0f", unit: "",
                                 dec: { swingDetector.swingContactSamples = max(2, swingDetector.swingContactSamples - 1) },
                                 inc: { swingDetector.swingContactSamples = min(10, swingDetector.swingContactSamples + 1) })
                        paramRow("Window", value: swingDetector.swingContactWindow, format: "%.3f", unit: "s",
                                 dec: { swingDetector.swingContactWindow = max(0.01, swingDetector.swingContactWindow - 0.01) },
                                 inc: { swingDetector.swingContactWindow = min(0.20, swingDetector.swingContactWindow + 0.01) })

                    case .unifDetect:
                        // Last detected swing type
                        if let lastSwing = swingDetector.lastDetectedSwing {
                            Text("Last: \(lastSwing.swingType.rawValue)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(swingTypeColor(lastSwing.swingType))
                        }

                        // Preset picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preset").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                            ForEach(UnifDetectPreset.allCases, id: \.self) { preset in
                                Button(action: {
                                    if preset == .custom {
                                        swingDetector.unifDetectPreset = .custom
                                    } else {
                                        swingDetector.applyUnifPreset(preset)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: swingDetector.unifDetectPreset == preset ? "circle.fill" : "circle")
                                            .font(.system(size: 12))
                                        Text(preset.rawValue)
                                            .font(.system(size: 14))
                                        Spacer()
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        // Config params
                        Text("Config").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        paramRow("Ceiling", value: swingDetector.unifSetupCeiling, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.unifSetupCeiling = max(0.05, swingDetector.unifSetupCeiling - 0.05) },
                                 inc: { swingDetector.unifSetupCeiling = min(2.0, swingDetector.unifSetupCeiling + 0.05) })
                        paramRow("MinDur", value: swingDetector.unifSetupMinDur, format: "%.2f", unit: "s",
                                 dec: { swingDetector.unifSetupMinDur = max(0.05, swingDetector.unifSetupMinDur - 0.05) },
                                 inc: { swingDetector.unifSetupMinDur = min(2.0, swingDetector.unifSetupMinDur + 0.05) })
                        paramRow("ValProm", value: swingDetector.unifValleyProm, format: "%.3f", unit: "",
                                 dec: { swingDetector.unifValleyProm = max(0.01, swingDetector.unifValleyProm - 0.01) },
                                 inc: { swingDetector.unifValleyProm = min(1.0, swingDetector.unifValleyProm + 0.01) })
                        paramRow("PkProm", value: swingDetector.unifPeakProm, format: "%.3f", unit: "",
                                 dec: { swingDetector.unifPeakProm = max(0.01, swingDetector.unifPeakProm - 0.01) },
                                 inc: { swingDetector.unifPeakProm = min(1.0, swingDetector.unifPeakProm + 0.01) })
                        paramRow("ValDist", value: Double(swingDetector.unifValleyDist), format: "%.0f", unit: "smp",
                                 dec: { swingDetector.unifValleyDist = max(0, swingDetector.unifValleyDist - 10) },
                                 inc: { swingDetector.unifValleyDist = min(500, swingDetector.unifValleyDist + 10) })
                        paramRow("PkDist", value: Double(swingDetector.unifPeakDist), format: "%.0f", unit: "smp",
                                 dec: { swingDetector.unifPeakDist = max(0, swingDetector.unifPeakDist - 10) },
                                 inc: { swingDetector.unifPeakDist = min(500, swingDetector.unifPeakDist + 10) })
                        paramRow("AreaW", value: swingDetector.unifAreaWindow, format: "%.2f", unit: "s",
                                 dec: { swingDetector.unifAreaWindow = max(0.05, swingDetector.unifAreaWindow - 0.05) },
                                 inc: { swingDetector.unifAreaWindow = min(1.0, swingDetector.unifAreaWindow + 0.05) })
                        paramRow("BsMaxRot", value: swingDetector.unifBsMaxRotMag, format: "%.2f", unit: "r/s",
                                 dec: { swingDetector.unifBsMaxRotMag = max(0.1, swingDetector.unifBsMaxRotMag - 0.1) },
                                 inc: { swingDetector.unifBsMaxRotMag = min(5.0, swingDetector.unifBsMaxRotMag + 0.1) })
                        paramRow("FS Area", value: swingDetector.unifSwingFSAreaThresh, format: "%.1f", unit: "",
                                 dec: { swingDetector.unifSwingFSAreaThresh = max(0.5, swingDetector.unifSwingFSAreaThresh - 0.5) },
                                 inc: { swingDetector.unifSwingFSAreaThresh = min(30.0, swingDetector.unifSwingFSAreaThresh + 0.5) })

                        // Post-pairing gates
                        Text("Post-Pairing Gates").font(.system(size: 10, weight: .bold)).foregroundColor(.purple)
                        paramRow("TV Min", value: swingDetector.unifContactTVSumMin, format: "%.3f", unit: "",
                                 dec: { swingDetector.unifContactTVSumMin = max(0.0, swingDetector.unifContactTVSumMin - 0.01) },
                                 inc: { swingDetector.unifContactTVSumMin = min(2.0, swingDetector.unifContactTVSumMin + 0.01) })
                        paramRow("Min Ext", value: Double(swingDetector.unifContactMinExtrema), format: "%.0f", unit: "",
                                 dec: { swingDetector.unifContactMinExtrema = max(0, swingDetector.unifContactMinExtrema - 1) },
                                 inc: { swingDetector.unifContactMinExtrema = min(20, swingDetector.unifContactMinExtrema + 1) })
                        paramRow("Spread", value: swingDetector.unifExtremaSpreadMax, format: "%.2f", unit: "",
                                 dec: { swingDetector.unifExtremaSpreadMax = max(0.1, swingDetector.unifExtremaSpreadMax - 0.05) },
                                 inc: { swingDetector.unifExtremaSpreadMax = min(2.0, swingDetector.unifExtremaSpreadMax + 0.05) })
                        paramRow("BL Max", value: swingDetector.unifBaselineTVMax, format: "%.2f", unit: "",
                                 dec: { swingDetector.unifBaselineTVMax = max(0.0, swingDetector.unifBaselineTVMax - 0.05) },
                                 inc: { swingDetector.unifBaselineTVMax = min(5.0, swingDetector.unifBaselineTVMax + 0.05) })
                        paramRow("Ct Prom", value: swingDetector.unifContactProminence, format: "%.3f", unit: "G",
                                 dec: { swingDetector.unifContactProminence = max(0.01, swingDetector.unifContactProminence - 0.01) },
                                 inc: { swingDetector.unifContactProminence = min(1.0, swingDetector.unifContactProminence + 0.01) })
                        paramRow("Win R", value: swingDetector.unifContactWindowRight, format: "%.2f", unit: "s",
                                 dec: { swingDetector.unifContactWindowRight = max(0.05, swingDetector.unifContactWindowRight - 0.05) },
                                 inc: { swingDetector.unifContactWindowRight = min(1.0, swingDetector.unifContactWindowRight + 0.05) })
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
        case .swing: return .orange
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
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                Spacer()
                Text("\(String(format: format, value))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            HStack {
                Button(action: dec) {
                    Text("-")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                Button(action: inc) {
                    Text("+")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
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
