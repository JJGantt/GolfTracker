import Foundation
import CoreMotion
import CoreLocation
import Combine
import WatchKit
import WatchConnectivity

class SwingDetectionManager: ObservableObject {
    static let shared = SwingDetectionManager()

    private let motionManager = CMMotionManager()
    private let locationManager = LocationManager.shared
    private let motionQueue = OperationQueue()

    @Published var lastDetectedSwing: DetectedSwing?
    @Published var isMonitoring: Bool = false

    // User Acceleration (gravity removed)
    @Published var userAccelMag: Double = 0.0
    @Published var userAccelX: Double = 0.0
    @Published var userAccelY: Double = 0.0
    @Published var userAccelZ: Double = 0.0

    // Rotation Rate (gyroscope)
    @Published var rotationMag: Double = 0.0
    @Published var rotationX: Double = 0.0
    @Published var rotationY: Double = 0.0
    @Published var rotationZ: Double = 0.0

    // Gravity vector
    @Published var gravityX: Double = 0.0
    @Published var gravityY: Double = 0.0
    @Published var gravityZ: Double = 0.0

    // Attitude (orientation)
    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0
    @Published var yaw: Double = 0.0

    // Min/Max tracking (since last reset)
    @Published var minUserAccelX: Double = 0.0
    @Published var maxUserAccelX: Double = 0.0
    @Published var minUserAccelY: Double = 0.0
    @Published var maxUserAccelY: Double = 0.0
    @Published var minUserAccelZ: Double = 0.0
    @Published var maxUserAccelZ: Double = 0.0
    @Published var maxUserAccelMag: Double = 0.0

    @Published var minRotationX: Double = 0.0
    @Published var maxRotationX: Double = 0.0
    @Published var minRotationY: Double = 0.0
    @Published var maxRotationY: Double = 0.0
    @Published var minRotationZ: Double = 0.0
    @Published var maxRotationZ: Double = 0.0
    @Published var maxRotationMag: Double = 0.0

    @Published var minPitch: Double = 0.0
    @Published var maxPitch: Double = 0.0
    @Published var minRoll: Double = 0.0
    @Published var maxRoll: Double = 0.0
    @Published var minYaw: Double = 0.0
    @Published var maxYaw: Double = 0.0

    @Published var lastTimeAboveThreshold: TimeInterval = 0.0
    @Published var accelerationThreshold: Double = 2.5 // G-force threshold (configurable)
    @Published var timeAboveThreshold: TimeInterval = 0.1 // Time required above threshold (configurable)
    @Published var isFrozen: Bool = false // Whether min/max tracking is frozen
    @Published var swingDetectionEnabled: Bool = false // Toggle swing detection on/off

    struct RecordedDataPoint: Codable {
        let timestamp: Date
        let userAccelX: Double
        let userAccelY: Double
        let userAccelZ: Double
        let userAccelMag: Double
        let rotationX: Double
        let rotationY: Double
        let rotationZ: Double
        let rotationMag: Double
        let gravityX: Double
        let gravityY: Double
        let gravityZ: Double
        let pitch: Double
        let roll: Double
        let yaw: Double
    }

    @Published var recordedDataPoints: [RecordedDataPoint] = []

    // Swing detection parameters
    private let updateInterval: TimeInterval = 0.02 // 50 Hz sampling rate
    private let maxAccelWindow: TimeInterval = 5.0 // Track max over 5 seconds


    // Track time above threshold for swing detection
    private var aboveThresholdStartTime: Date?

    // Recording state
    private var isRecording: Bool = false

    struct DetectedSwing {
        let location: CLLocationCoordinate2D
        let timestamp: Date
        let peakAcceleration: Double
    }

    private init() {
        setupMotionManager()
    }

    private func setupMotionManager() {
        guard motionManager.isDeviceMotionAvailable else {
            print("⌚ [SwingDetection] Device Motion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = updateInterval
    }

    func startMonitoring() {
        guard motionManager.isDeviceMotionAvailable else {
            print("⌚ [SwingDetection] Cannot start monitoring - device motion not available")
            return
        }

        guard !isMonitoring else {
            print("⌚ [SwingDetection] Already monitoring")
            return
        }

        print("⌚ [SwingDetection] Starting swing detection on background queue")
        isMonitoring = true

        // Use background queue so updates continue when screen is off
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let data = data else { return }

            self.processDeviceMotion(data)
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        print("⌚ [SwingDetection] Stopping swing detection")
        isMonitoring = false
        motionManager.stopDeviceMotionUpdates()
    }

    private func processDeviceMotion(_ data: CMDeviceMotion) {
        let now = Date()

        // User Acceleration (gravity removed)
        let uax = data.userAcceleration.x
        let uay = data.userAcceleration.y
        let uaz = data.userAcceleration.z
        let uaMag = sqrt(uax * uax + uay * uay + uaz * uaz)

        // Rotation Rate
        let rx = data.rotationRate.x
        let ry = data.rotationRate.y
        let rz = data.rotationRate.z
        let rMag = sqrt(rx * rx + ry * ry + rz * rz)

        // Gravity
        let gx = data.gravity.x
        let gy = data.gravity.y
        let gz = data.gravity.z

        // Attitude
        let p = data.attitude.pitch
        let r = data.attitude.roll
        let y = data.attitude.yaw

        // Update current values on main thread for UI binding
        DispatchQueue.main.async {
            self.userAccelMag = uaMag
            self.userAccelX = uax
            self.userAccelY = uay
            self.userAccelZ = uaz

            self.rotationMag = rMag
            self.rotationX = rx
            self.rotationY = ry
            self.rotationZ = rz

            self.gravityX = gx
            self.gravityY = gy
            self.gravityZ = gz

            self.pitch = p
            self.roll = r
            self.yaw = y

            // Update min/max tracking (only if not frozen)
            if !self.isFrozen {
                self.minUserAccelX = min(self.minUserAccelX, uax)
                self.maxUserAccelX = max(self.maxUserAccelX, uax)
                self.minUserAccelY = min(self.minUserAccelY, uay)
                self.maxUserAccelY = max(self.maxUserAccelY, uay)
                self.minUserAccelZ = min(self.minUserAccelZ, uaz)
                self.maxUserAccelZ = max(self.maxUserAccelZ, uaz)
                self.maxUserAccelMag = max(self.maxUserAccelMag, uaMag)

                self.minRotationX = min(self.minRotationX, rx)
                self.maxRotationX = max(self.maxRotationX, rx)
                self.minRotationY = min(self.minRotationY, ry)
                self.maxRotationY = max(self.maxRotationY, ry)
                self.minRotationZ = min(self.minRotationZ, rz)
                self.maxRotationZ = max(self.maxRotationZ, rz)
                self.maxRotationMag = max(self.maxRotationMag, rMag)

                self.minPitch = min(self.minPitch, p)
                self.maxPitch = max(self.maxPitch, p)
                self.minRoll = min(self.minRoll, r)
                self.maxRoll = max(self.maxRoll, r)
                self.minYaw = min(self.minYaw, y)
                self.maxYaw = max(self.maxYaw, y)
            }
        }

        // Record data if recording is active
        if isRecording {
            let dataPoint = RecordedDataPoint(
                timestamp: now,
                userAccelX: uax,
                userAccelY: uay,
                userAccelZ: uaz,
                userAccelMag: uaMag,
                rotationX: rx,
                rotationY: ry,
                rotationZ: rz,
                rotationMag: rMag,
                gravityX: gx,
                gravityY: gy,
                gravityZ: gz,
                pitch: p,
                roll: r,
                yaw: y
            )
            recordedDataPoints.append(dataPoint)
        }

        // Track time above threshold (using user acceleration magnitude)
        // DISABLED FOR TESTING - will re-enable after testing phase
        if swingDetectionEnabled {
            if uaMag > accelerationThreshold {
                if aboveThresholdStartTime == nil {
                    aboveThresholdStartTime = now
                } else if let startTime = aboveThresholdStartTime {
                    let timeAbove = now.timeIntervalSince(startTime)
                    if timeAbove >= timeAboveThreshold {
                        // Has been above threshold for required duration
                        detectSwing(magnitude: uaMag)
                        lastTimeAboveThreshold = timeAbove
                        aboveThresholdStartTime = nil
                    }
                }
            } else {
                // Fell below threshold - save duration if we were tracking
                if let startTime = aboveThresholdStartTime {
                    lastTimeAboveThreshold = now.timeIntervalSince(startTime)
                }
                aboveThresholdStartTime = nil
            }
        }
    }

    private var lastSwingDetectionTime: Date?

    private func detectSwing(magnitude: Double) {
        // Debounce: Don't detect another swing within 0.5 seconds of the last one
        if let lastTime = lastSwingDetectionTime,
           Date().timeIntervalSince(lastTime) < 0.5 {
            return
        }

        // Get current location
        guard let location = locationManager.location else {
            print("⌚ [SwingDetection] Swing detected but no location available")
            return
        }

        lastSwingDetectionTime = Date()

        print("⌚ [SwingDetection] Swing detected! Magnitude: \(magnitude) G")

        // Save the detected swing with peak acceleration
        let swing = DetectedSwing(
            location: location.coordinate,
            timestamp: Date(),
            peakAcceleration: magnitude
        )
        lastDetectedSwing = swing

        // Play haptic and sound feedback
        playFeedback()
    }

    private func playFeedback() {
        // Play haptic feedback
        WKInterfaceDevice.current().play(.click)

        // Play sound feedback
        WKInterfaceDevice.current().play(.notification)
    }

    func clearLastSwing() {
        lastDetectedSwing = nil
        print("⌚ [SwingDetection] Cleared last detected swing")
    }

    func toggleResetFreeze() {
        if isFrozen {
            // Currently frozen - unfreeze and reset
            isFrozen = false
            resetMinMaxToCurrent()
            print("⌚ [SwingDetection] Unfrozen and reset min/max values")
        } else {
            // Currently tracking - freeze
            isFrozen = true
            print("⌚ [SwingDetection] Froze min/max values")
        }
    }

    private func resetMinMaxToCurrent() {
        minUserAccelX = userAccelX
        maxUserAccelX = userAccelX
        minUserAccelY = userAccelY
        maxUserAccelY = userAccelY
        minUserAccelZ = userAccelZ
        maxUserAccelZ = userAccelZ
        maxUserAccelMag = userAccelMag

        minRotationX = rotationX
        maxRotationX = rotationX
        minRotationY = rotationY
        maxRotationY = rotationY
        minRotationZ = rotationZ
        maxRotationZ = rotationZ
        maxRotationMag = rotationMag

        minPitch = pitch
        maxPitch = pitch
        minRoll = roll
        maxRoll = roll
        minYaw = yaw
        maxYaw = yaw
    }

    // MARK: - Recording

    func startRecording() {
        recordedDataPoints = []
        isRecording = true
        print("⌚ [SwingDetection] Started recording acceleration data")
    }

    func stopRecording() {
        isRecording = false
        print("⌚ [SwingDetection] Stopped recording. Captured \(recordedDataPoints.count) samples")
    }

    func sendRecordedDataToPhone() {
        if recordedDataPoints.isEmpty {
            print("⌚ [SwingDetection] No data recorded (likely simulator - device motion not available)")
            // Still try to send so user knows it was triggered
        }

        // Convert to CSV format
        var csv = "Timestamp,UserAccelX,UserAccelY,UserAccelZ,UserAccelMag,RotationX,RotationY,RotationZ,RotationMag,GravityX,GravityY,GravityZ,Pitch,Roll,Yaw\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        for dataPoint in recordedDataPoints {
            let timestamp = dateFormatter.string(from: dataPoint.timestamp)
            csv += "\(timestamp),"
            csv += "\(String(format: "%.4f", dataPoint.userAccelX)),"
            csv += "\(String(format: "%.4f", dataPoint.userAccelY)),"
            csv += "\(String(format: "%.4f", dataPoint.userAccelZ)),"
            csv += "\(String(format: "%.4f", dataPoint.userAccelMag)),"
            csv += "\(String(format: "%.4f", dataPoint.rotationX)),"
            csv += "\(String(format: "%.4f", dataPoint.rotationY)),"
            csv += "\(String(format: "%.4f", dataPoint.rotationZ)),"
            csv += "\(String(format: "%.4f", dataPoint.rotationMag)),"
            csv += "\(String(format: "%.4f", dataPoint.gravityX)),"
            csv += "\(String(format: "%.4f", dataPoint.gravityY)),"
            csv += "\(String(format: "%.4f", dataPoint.gravityZ)),"
            csv += "\(String(format: "%.4f", dataPoint.pitch)),"
            csv += "\(String(format: "%.4f", dataPoint.roll)),"
            csv += "\(String(format: "%.4f", dataPoint.yaw))\n"
        }

        // Send via WatchConnectivity
        let message: [String: Any] = [
            "type": "motionData",
            "csv": csv,
            "sampleCount": recordedDataPoints.count,
            "threshold": accelerationThreshold,
            "timeAboveThreshold": timeAboveThreshold
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("⌚ [SwingDetection] Error sending data to phone: \(error.localizedDescription)")
            }
        } else {
            print("⌚ [SwingDetection] Phone not reachable, cannot send data")
        }

        print("⌚ [SwingDetection] Sent \(recordedDataPoints.count) data points to phone")
    }
}
