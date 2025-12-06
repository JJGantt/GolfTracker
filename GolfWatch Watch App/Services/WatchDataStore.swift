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

    private func getCourse(for round: Round) -> Course? {
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

    func addStroke(club: Club) {
        guard var round = currentRound,
              let hole = currentHole,
              let location = LocationManager.shared.location else { return }

        let strokesForHole = round.strokes.filter { $0.holeNumber == hole.number }
        let strokeNumber = strokesForHole.count + 1

        let stroke = Stroke(
            holeNumber: hole.number,
            strokeNumber: strokeNumber,
            coordinate: location.coordinate,
            club: club
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

    func moveToNextHole() {
        guard var round = currentRound,
              let course = getCourse(for: round) else { return }

        if currentHoleIndex < course.holes.count - 1 {
            currentHoleIndex += 1
            round.currentHoleIndex = currentHoleIndex
            currentRound = round
            saveToStorage()

            // Send update to iPhone
            WatchConnectivityManager.shared.sendRound(round)
        }
    }

    func moveToPreviousHole() {
        guard var round = currentRound else { return }

        if currentHoleIndex > 0 {
            currentHoleIndex -= 1
            round.currentHoleIndex = currentHoleIndex
            currentRound = round
            saveToStorage()

            // Send update to iPhone
            WatchConnectivityManager.shared.sendRound(round)
        }
    }

    func deleteLastStroke() {
        guard var round = currentRound,
              let hole = currentHole else { return }

        // Find and remove the last stroke for this hole
        let strokesForHole = round.strokes.filter { $0.holeNumber == hole.number }
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
        } else if round.isHoleCompleted(hole.number) {
            // No strokes to delete, but hole is completed - reopen it
            round.completedHoles.remove(hole.number)
            currentRound = round
            saveToStorage()
            print("⌚ [WatchDataStore] Reopened hole \(hole.number)")

            // Send update to iPhone
            WatchConnectivityManager.shared.sendRound(round)
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

    private func saveToStorage() {
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
        guard var round = currentRound,
              let hole = currentHole else { return }

        // Mark hole as completed
        round.completedHoles.insert(hole.number)

        // Auto-advance to next hole if available
        if let course = getCourse(for: round),
           currentHoleIndex < course.holes.count - 1 {
            currentHoleIndex += 1
            round.currentHoleIndex = currentHoleIndex
        }

        currentRound = round
        saveToStorage()

        // Send update to iPhone
        WatchConnectivityManager.shared.sendRound(round)
    }

    func isHoleCompleted(_ holeNumber: Int) -> Bool {
        return currentRound?.isHoleCompleted(holeNumber) ?? false
    }

    // MARK: - Helpers

    func strokeCount(for hole: Hole) -> Int {
        currentRound?.strokes.filter { $0.holeNumber == hole.number }.count ?? 0
    }
}
