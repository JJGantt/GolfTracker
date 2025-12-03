import Foundation
import CoreLocation

class DataStore: ObservableObject {
    @Published var courses: [Course] = []
    @Published var rounds: [Round] = []
    @Published var errorMessage: String?

    private let coursesFileName = "courses.json"
    private let roundsFileName = "rounds.json"

    init() {
        loadCourses()
        loadRounds()
    }

    private var coursesFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(coursesFileName)
    }

    private var roundsFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(roundsFileName)
    }
    
    func loadCourses() {
        guard FileManager.default.fileExists(atPath: coursesFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: coursesFileURL)
            courses = try JSONDecoder().decode([Course].self, from: data)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load courses: \(error.localizedDescription)"
        }
    }

    func loadRounds() {
        guard FileManager.default.fileExists(atPath: roundsFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: roundsFileURL)
            rounds = try JSONDecoder().decode([Round].self, from: data)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load rounds: \(error.localizedDescription)"
        }
    }

    func saveCourses() {
        do {
            let data = try JSONEncoder().encode(courses)
            try data.write(to: coursesFileURL)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save courses: \(error.localizedDescription)"
        }
    }

    func saveRounds() {
        do {
            let data = try JSONEncoder().encode(rounds)
            try data.write(to: roundsFileURL)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save rounds: \(error.localizedDescription)"
        }
    }
    
    func addCourse(name: String) {
        let course = Course(name: name, holes: [])
        courses.append(course)
        saveCourses()
    }

    func deleteCourse(_ course: Course) {
        courses.removeAll { $0.id == course.id }
        saveCourses()
    }

    func addHole(to course: Course, coordinate: CLLocationCoordinate2D) {
        guard let index = courses.firstIndex(where: { $0.id == course.id }) else { return }
        let holeNumber = courses[index].holes.count + 1
        let hole = Hole(number: holeNumber, coordinate: coordinate)
        courses[index].holes.append(hole)
        saveCourses()
    }

    func deleteHole(_ hole: Hole, from course: Course) {
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }) else { return }
        courses[courseIndex].holes.removeAll { $0.id == hole.id }
        // Renumber remaining holes
        for i in courses[courseIndex].holes.indices {
            courses[courseIndex].holes[i].number = i + 1
        }
        saveCourses()
    }

    func updateHole(_ hole: Hole, in course: Course, newCoordinate: CLLocationCoordinate2D) {
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }),
              let holeIndex = courses[courseIndex].holes.firstIndex(where: { $0.id == hole.id }) else { return }
        courses[courseIndex].holes[holeIndex].latitude = newCoordinate.latitude
        courses[courseIndex].holes[holeIndex].longitude = newCoordinate.longitude
        saveCourses()
    }

    func renumberHole(_ hole: Hole, in course: Course, newNumber: Int) {
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }),
              let holeIndex = courses[courseIndex].holes.firstIndex(where: { $0.id == hole.id }) else { return }

        // Ensure new number is valid
        let clampedNumber = max(1, min(newNumber, courses[courseIndex].holes.count))

        // Remove hole from current position
        let removedHole = courses[courseIndex].holes.remove(at: holeIndex)

        // Insert at new position (newNumber - 1 because array is 0-indexed)
        let newIndex = clampedNumber - 1
        courses[courseIndex].holes.insert(removedHole, at: newIndex)

        // Renumber all holes sequentially
        for i in courses[courseIndex].holes.indices {
            courses[courseIndex].holes[i].number = i + 1
        }

        saveCourses()
    }

    func updateHoleYards(_ hole: Hole, in course: Course, yards: Int?) {
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }),
              let holeIndex = courses[courseIndex].holes.firstIndex(where: { $0.id == hole.id }) else { return }
        courses[courseIndex].holes[holeIndex].yards = yards
        saveCourses()
    }

    func updateHolePar(_ hole: Hole, in course: Course, par: Int?) {
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }),
              let holeIndex = courses[courseIndex].holes.firstIndex(where: { $0.id == hole.id }) else { return }
        courses[courseIndex].holes[holeIndex].par = par
        saveCourses()
    }

    func updateTeeMarker(_ hole: Hole, in course: Course, teeCoordinate: CLLocationCoordinate2D) {
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }),
              let holeIndex = courses[courseIndex].holes.firstIndex(where: { $0.id == hole.id }) else { return }

        courses[courseIndex].holes[holeIndex].teeLatitude = teeCoordinate.latitude
        courses[courseIndex].holes[holeIndex].teeLongitude = teeCoordinate.longitude

        // Automatically calculate yards from tee to hole
        let teeLocation = CLLocation(latitude: teeCoordinate.latitude, longitude: teeCoordinate.longitude)
        let holeLocation = CLLocation(
            latitude: courses[courseIndex].holes[holeIndex].latitude,
            longitude: courses[courseIndex].holes[holeIndex].longitude
        )
        let distanceInMeters = teeLocation.distance(from: holeLocation)
        let distanceInYards = Int(distanceInMeters * 1.09361)

        courses[courseIndex].holes[holeIndex].yards = distanceInYards

        saveCourses()
    }

    // MARK: - Round Management

    func startRound(for course: Course) -> Round {
        let round = Round(courseId: course.id, courseName: course.name)
        rounds.append(round)
        saveRounds()
        return round
    }

    func addStroke(to round: Round, holeNumber: Int, coordinate: CLLocationCoordinate2D, club: Club) {
        guard let roundIndex = rounds.firstIndex(where: { $0.id == round.id }) else { return }

        let strokesForHole = rounds[roundIndex].strokes.filter { $0.holeNumber == holeNumber }
        let strokeNumber = strokesForHole.count + 1

        let stroke = Stroke(holeNumber: holeNumber, strokeNumber: strokeNumber, coordinate: coordinate, club: club)
        rounds[roundIndex].strokes.append(stroke)
        saveRounds()
    }

    func updateStrokeDetails(in round: Round, stroke: Stroke, landingCoordinate: CLLocationCoordinate2D, length: StrokeLength?, direction: StrokeDirection?, location: StrokeLocation?) {
        guard let roundIndex = rounds.firstIndex(where: { $0.id == round.id }),
              let strokeIndex = rounds[roundIndex].strokes.firstIndex(where: { $0.id == stroke.id }) else { return }

        rounds[roundIndex].strokes[strokeIndex].landingLatitude = landingCoordinate.latitude
        rounds[roundIndex].strokes[strokeIndex].landingLongitude = landingCoordinate.longitude
        rounds[roundIndex].strokes[strokeIndex].length = length
        rounds[roundIndex].strokes[strokeIndex].direction = direction
        rounds[roundIndex].strokes[strokeIndex].location = location

        // Add penalty stroke if location requires it
        if let location = location, location.addsPenaltyStroke {
            let strokesForHole = rounds[roundIndex].strokes.filter { $0.holeNumber == stroke.holeNumber }
            let nextStrokeNumber = strokesForHole.map { $0.strokeNumber }.max()! + 1

            let penaltyStroke = Stroke(
                holeNumber: stroke.holeNumber,
                strokeNumber: nextStrokeNumber,
                coordinate: landingCoordinate,
                club: stroke.club
            )
            rounds[roundIndex].strokes.append(penaltyStroke)
        }

        saveRounds()
    }

    func endRound(_ round: Round) {
        // Round is already saved, just need to ensure it's persisted
        saveRounds()
    }
}
