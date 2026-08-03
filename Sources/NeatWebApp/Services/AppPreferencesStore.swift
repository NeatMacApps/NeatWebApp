import CoreGraphics
import Foundation

struct AppPreferences: Equatable, Sendable {
    let sideDockEdge: SideDockEdge
    let sideDockVerticalPosition: CGFloat
    let sideDockDisplayID: CGDirectDisplayID?
    let isVirtualNotchEnabled: Bool
}

final class AppPreferencesStore {
    static let defaultVirtualNotchEnabled = true

    private enum Key {
        static let sideDockEdge = "sideDock.edge"
        static let sideDockVerticalPosition = "sideDock.verticalPosition"
        static let sideDockDisplayID = "sideDock.displayID"
        static let virtualNotchEnabled = "launcher.virtualNotchEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(defaultEdge: SideDockEdge) -> AppPreferences {
        let edge = defaults.string(forKey: Key.sideDockEdge)
            .flatMap(SideDockEdge.init(rawValue:))
            ?? defaultEdge
        let verticalPosition: CGFloat
        if defaults.object(forKey: Key.sideDockVerticalPosition) == nil {
            verticalPosition = SideDockPlacementResolver.defaultVerticalPosition
        } else {
            verticalPosition = min(max(defaults.double(forKey: Key.sideDockVerticalPosition), 0), 1)
        }
        let displayID: CGDirectDisplayID?
        if defaults.object(forKey: Key.sideDockDisplayID) == nil {
            displayID = nil
        } else {
            displayID = CGDirectDisplayID(defaults.integer(forKey: Key.sideDockDisplayID))
        }

        let isVirtualNotchEnabled: Bool
        if defaults.object(forKey: Key.virtualNotchEnabled) == nil {
            isVirtualNotchEnabled = Self.defaultVirtualNotchEnabled
        } else {
            isVirtualNotchEnabled = defaults.bool(forKey: Key.virtualNotchEnabled)
        }

        return AppPreferences(
            sideDockEdge: edge,
            sideDockVerticalPosition: verticalPosition,
            sideDockDisplayID: displayID,
            isVirtualNotchEnabled: isVirtualNotchEnabled
        )
    }

    func save(_ preferences: AppPreferences) {
        defaults.set(preferences.sideDockEdge.rawValue, forKey: Key.sideDockEdge)
        defaults.set(Double(preferences.sideDockVerticalPosition), forKey: Key.sideDockVerticalPosition)
        defaults.set(preferences.isVirtualNotchEnabled, forKey: Key.virtualNotchEnabled)

        if let displayID = preferences.sideDockDisplayID {
            defaults.set(Int(displayID), forKey: Key.sideDockDisplayID)
        } else {
            defaults.removeObject(forKey: Key.sideDockDisplayID)
        }
    }
}
