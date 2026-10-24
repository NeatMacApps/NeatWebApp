import Foundation

/// Focus history is independent of visibility: collapsing a window does not make it less recent.
struct WebAppSwitchingHistory {
    private var appIDs: [String] = []

    mutating func recordFocus(appID: String) {
        appIDs.removeAll { $0 == appID }
        appIDs.insert(appID, at: 0)
    }

    mutating func retainRunningApps(in states: [RuntimeState]) {
        let runningIDs = Set(states.filter { $0.phase != .terminating }.map(\.appID))
        appIDs.removeAll { !runningIDs.contains($0) }
    }

    func restorationTarget(in states: [RuntimeState]) -> RuntimeState? {
        let running = states.filter { $0.phase != .terminating }
        for appID in appIDs {
            if let state = running.first(where: { $0.appID == appID }) {
                return state
            }
        }

        // Registry takeover has no in-memory focus history. Use a deterministic live fallback.
        return running.sorted {
            if $0.lastUpdatedAt == $1.lastUpdatedAt {
                return $0.appID < $1.appID
            }
            return $0.lastUpdatedAt > $1.lastUpdatedAt
        }.first
    }
}
