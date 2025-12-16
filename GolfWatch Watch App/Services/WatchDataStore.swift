import Foundation
import Combine

class WatchDataStore: ObservableObject {
    static let shared = WatchDataStore()

    @Published var currentRound: Round?
    @Published var currentHoleIndex: Int = 0
    @Published var pendingStrokes: [Stroke] = []

    private let connectivity = WatchConnectivityManager.shared
    private let roundKey = "currentRound"
    private let pendingStrokesKey = "pendingStrokes"

    private init() {
        loadFromStorage()
        setupConnectivity()
    }

    // MARK: - Current Hole

    var currentHole: Hole? {
        guard let round = currentRound,
              let course = getCourse(for: round) else { return nil }
        guard currentHoleIndex < course.holes.count else { return nil }
        return course.holes[currentHoleIndex]
    }

    func getCourse(for round: Round) -> Course? {
        // Use holes from the synced round data
        return Course(
            id: round.courseId,
            name: round.courseName,
            holes: round.holes,
            rating: nil,
            slope: nil,
            city: nil
        )
    }

    // MARK: - Stroke Management

    func addStroke(club: Club, trajectoryHeading: Double? = nil) {
        guard var round = currentRound,
              let hole = currentHole,
              let location = LocationManager.shared.location else { return }

        let strokesForHole = round.strokes.filter { $0.holeNumber == hole.number }
        let strokeNumber = strokesForHole.count + 1

        let stroke = Stroke(
            holeNumber: hole.number,
            strokeNumber: strokeNumber,
            coordinate: location.coordinate,
            club: club,
            trajectoryHeading: trajectoryHeading
        )

        // Add to current round
        round.strokes.append(stroke)
        currentRound = round

        // Add to pending sync queue
        pendingStrokes.append(stroke)

        // Save locally
        saveToStorage()

        // Try to sync immediately
        syncStrokes()
    }

    // MARK: - Round State Management (with automatic sync)

    func updateCurrentHoleIndex(newIndex: Int) {
        guard var round = currentRound else { return }

        currentHoleIndex = newIndex
        round.currentHoleIndex = newIndex
        currentRound = round
        saveToStorage()

        // Sync to iPhone
        WatchConnectivityManager.shared.sendRound(round)
    }

    func completeHole(holeNumber: Int) {
        guard var round = currentRound else { return }

        round.completedHoles.insert(holeNumber)
        currentRound = round
        saveToStorage()

        // Sync to iPhone
        WatchConnectivityManager.shared.sendRound(round)
    }

    func reopenHole(holeNumber: Int) {
        guard var round = currentRound else { return }

        round.completedHoles.remove(holeNumber)
        currentRound = round
        saveToStorage()

        // Sync to iPhone
        WatchConnectivityManager.shared.sendRound(round)
    }

    func moveToNextHole() {
        guard let course = getCourse(for: currentRound ?? Round(courseId: UUID(), courseName: "", holes: [])) else { return }

        if currentHoleIndex < course.holes.count - 1 {
            updateCurrentHoleIndex(newIndex: currentHoleIndex + 1)
        }
    }

    func moveToPreviousHole() {
        if currentHoleIndex > 0 {
            updateCurrentHoleIndex(newIndex: currentHoleIndex - 1)
        }
    }

    func deleteLastStroke() {
        guard var round = currentRound else { return }

        // Get strokes for current hole
        let hole = currentHole
        let strokesForHole = hole.map { h in round.strokes.filter { $0.holeNumber == h.number } } ?? []

        // If there are strokes on current hole, delete the last one
        if let lastStroke = strokesForHole.last,
           let index = round.strokes.firstIndex(where: { $0.id == lastStroke.id }) {
            round.strokes.remove(at: index)
            currentRound = round

            // Also remove from pending if it's there
            if let pendingIndex = pendingStrokes.firstIndex(where: { $0.id == lastStroke.id }) {
                pendingStrokes.remove(at: pendingIndex)
            }

            saveToStorage()
            print("⌚ [WatchDataStore] Deleted last stroke")

            // Send update to iPhone
            WatchConnectivityManager.shared.sendRound(round)
        } else if currentHoleIndex > 0,
                  let course = getCourse(for: round) {
            // No strokes on current hole - check if we just finished the previous hole
            let previousHoleIdx = currentHoleIndex - 1
            let previousHoleNumber = course.holes[previousHoleIdx].number

            if round.isHoleCompleted(previousHoleNumber) {
                // Undo the hole completion and go back to previous hole
                reopenHole(holeNumber: previousHoleNumber)
                updateCurrentHoleIndex(newIndex: previousHoleIdx)
                print("⌚ [WatchDataStore] Undid hole completion, moved back to hole \(previousHoleNumber)")
            }
        }
    }

    // MARK: - Sync

    private func syncStrokes() {
        guard !pendingStrokes.isEmpty else { return }

        print("⌚ [WatchDataStore] Syncing \(pendingStrokes.count) pending strokes to iPhone")
        connectivity.sendStrokes(pendingStrokes) { [weak self] success in
            if success {
                print("⌚ [WatchDataStore] Successfully synced strokes, clearing pending queue")
                DispatchQueue.main.async {
                    self?.pendingStrokes.removeAll()
                    self?.saveToStorage()
                }
            } else {
                print("⌚ [WatchDataStore] Failed to sync strokes, will retry later")
            }
        }
    }

    // MARK: - Connectivity Setup

    private func setupConnectivity() {
        connectivity.onReceiveRound = { [weak self] round in
            print("⌚ [WatchDataStore] Received round: \(round.courseName)")
            print("⌚ [WatchDataStore] Round has \(round.holes.count) holes, current hole index: \(round.currentHoleIndex)")
            DispatchQueue.main.async {
                self?.currentRound = round
                self?.currentHoleIndex = round.currentHoleIndex
                self?.saveToStorage()
                print("⌚ [WatchDataStore] Current round set successfully, synced to hole \(round.currentHoleIndex)")
            }
        }
    }

    // MARK: - Persistence

    func saveToStorage() {
        if let round = currentRound,
           let data = try? JSONEncoder().encode(round) {
            UserDefaults.standard.set(data, forKey: roundKey)
        }

        if let data = try? JSONEncoder().encode(pendingStrokes) {
            UserDefaults.standard.set(data, forKey: pendingStrokesKey)
        }

        UserDefaults.standard.set(currentHoleIndex, forKey: "currentHoleIndex")
    }

    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: roundKey),
           let round = try? JSONDecoder().decode(Round.self, from: data) {
            currentRound = round
        }

        if let data = UserDefaults.standard.data(forKey: pendingStrokesKey),
           let strokes = try? JSONDecoder().decode([Stroke].self, from: data) {
            pendingStrokes = strokes
        }

        currentHoleIndex = UserDefaults.standard.integer(forKey: "currentHoleIndex")
    }

    // MARK: - Hole Completion

    func finishCurrentHole() {
        guard let hole = currentHole,
              let course = getCourse(for: currentRound ?? Round(courseId: UUID(), courseName: "", holes: [])) else { return }

        // Mark hole as completed
        completeHole(holeNumber: hole.number)

        // Auto-advance to next hole if available
        if currentHoleIndex < course.holes.count - 1 {
            updateCurrentHoleIndex(newIndex: currentHoleIndex + 1)
        }
    }

    func isHoleCompleted(_ holeNumber: Int) -> Bool {
        return currentRound?.isHoleCompleted(holeNumber) ?? false
    }

    // MARK: - Helpers

    func strokeCount(for hole: Hole) -> Int {
        currentRound?.strokes.filter { $0.holeNumber == hole.number }.count ?? 0
    }
}
