import Foundation
import CoreLocation

enum Club: String, Codable, CaseIterable {
    case driver = "Driver"
    case threeIron = "3i"
    case fourIron = "4i"
    case fiveIron = "5i"
    case sixIron = "6i"
    case sevenIron = "7i"
    case eightIron = "8i"
    case nineIron = "9i"
    case pitch = "Pitch"
    case approach = "Approach"
    case hybrid = "Hybrid"
    case putter = "Putter"
}

enum StrokeLength: Codable, CaseIterable {
    case redShort
    case yellowShort
    case center
    case yellowLong
    case redLong

    var displayName: String {
        switch self {
        case .redShort, .yellowShort: return "Short"
        case .center: return "Good"
        case .yellowLong, .redLong: return "Long"
        }
    }

    var severity: Int {
        switch self {
        case .redShort, .redLong: return 2
        case .yellowShort, .yellowLong: return 1
        case .center: return 0
        }
    }
}

enum StrokeDirection: Codable, CaseIterable {
    case redRight
    case yellowRight
    case center
    case yellowLeft
    case redLeft

    var displayName: String {
        switch self {
        case .redRight, .yellowRight: return "Right"
        case .center: return "Center"
        case .yellowLeft, .redLeft: return "Left"
        }
    }

    var severity: Int {
        switch self {
        case .redRight, .redLeft: return 2
        case .yellowRight, .yellowLeft: return 1
        case .center: return 0
        }
    }
}

enum StrokeLocation: String, Codable, CaseIterable {
    case hazard = "Hazard"
    case rough = "Rough"
    case sand = "Sand"
    case fringe = "Fringe"
    case fairway = "Fairway"
    case green = "Green"
}

enum StrokeContact: String, Codable, CaseIterable {
    case fat = "Fat"
    case clean = "Clean"
    case top = "Top"
}

enum SwingStrength: String, Codable, CaseIterable {
    case chip = "Chip"
    case medium = "Medium"
    case full = "Full"
}

struct Course: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var holes: [Hole]
    var rating: Double?
    var slope: Int?
    var city: String?

    var coordinate: CLLocationCoordinate2D? {
        guard let firstHole = holes.first else { return nil }
        return firstHole.coordinate
    }
}

struct Hole: Identifiable, Codable, Hashable {
    var id = UUID()
    var number: Int
    var latitude: Double
    var longitude: Double
    var teeLatitude: Double?
    var teeLongitude: Double?
    var yards: Int?
    var par: Int?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var teeCoordinate: CLLocationCoordinate2D? {
        guard let teeLat = teeLatitude, let teeLon = teeLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: teeLat, longitude: teeLon)
    }

    init(number: Int, coordinate: CLLocationCoordinate2D, yards: Int? = nil, par: Int? = nil, teeCoordinate: CLLocationCoordinate2D? = nil) {
        self.number = number
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.yards = yards
        self.par = par
        self.teeLatitude = teeCoordinate?.latitude
        self.teeLongitude = teeCoordinate?.longitude
    }
}

struct Stroke: Identifiable, Codable, Hashable {
    var id = UUID()
    var holeNumber: Int
    var strokeNumber: Int
    var latitude: Double
    var longitude: Double
    var club: Club
    var timestamp: Date
    var length: StrokeLength?
    var direction: StrokeDirection?
    var location: StrokeLocation?
    var contact: StrokeContact?
    var swingStrength: SwingStrength?
    var landingLatitude: Double?
    var landingLongitude: Double?
    var isPenalty: Bool
    var trajectoryHeading: Double? // Direction user was trying to hit (in degrees)

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var landingCoordinate: CLLocationCoordinate2D? {
        guard let lat = landingLatitude, let lon = landingLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init(holeNumber: Int, strokeNumber: Int, coordinate: CLLocationCoordinate2D, club: Club, isPenalty: Bool = false, trajectoryHeading: Double? = nil) {
        self.holeNumber = holeNumber
        self.strokeNumber = strokeNumber
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.club = club
        self.timestamp = Date()
        self.isPenalty = isPenalty
        self.trajectoryHeading = trajectoryHeading
    }
}

struct Target: Identifiable, Codable, Hashable {
    var id = UUID()
    var holeNumber: Int
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(holeNumber: Int, coordinate: CLLocationCoordinate2D) {
        self.holeNumber = holeNumber
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct Round: Identifiable, Codable, Hashable {
    var id = UUID()
    var courseId: UUID
    var courseName: String
    var date: Date
    var strokes: [Stroke]
    var holes: [Hole] // Course holes for Watch sync
    var completedHoles: Set<Int> // Hole numbers that have been finished
    var currentHoleIndex: Int // Current hole being played (synced between devices)
    var targets: [Target] // Target markers placed on the map (synced between devices)

    init(courseId: UUID, courseName: String, holes: [Hole] = []) {
        self.courseId = courseId
        self.courseName = courseName
        self.date = Date()
        self.strokes = []
        self.holes = holes
        self.completedHoles = []
        self.currentHoleIndex = 0
        self.targets = []
    }

    func isHoleCompleted(_ holeNumber: Int) -> Bool {
        return completedHoles.contains(holeNumber)
    }
}
