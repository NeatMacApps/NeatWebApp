import CoreGraphics
import Foundation

struct AppPreferences: Equatable, Sendable {
    let sideDockEdge: SideDockEdge
    let sideDockVerticalPosition: CGFloat
    let sideDockDisplayID: CGDirectDisplayID?
    let isVirtualNotchEnabled: Bool
    var sideDockFloatingPosition: CGPoint? = nil
}

final class AppPreferencesStore {
    static let defaultVirtualNotchEnabled = true

    private enum Key {
        static let sideDockEdge = "sideDock.edge"
        static let sideDockVerticalPosition = "sideDock.verticalPosition"
        static let sideDockDisplayID = "sideDock.displayID"
        static let sideDockFloatingX = "sideDock.floatingX"
        static let sideDockFloatingY = "sideDock.floatingY"
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

        let floatingPosition: CGPoint?
        if defaults.object(forKey: Key.sideDockFloatingX) != nil,
           defaults.object(forKey: Key.sideDockFloatingY) != nil {
            floatingPosition = CGPoint(
                x: SideDockPlacementResolver.clamped(defaults.double(forKey: Key.sideDockFloatingX)),
                y: SideDockPlacementResolver.clamped(defaults.double(forKey: Key.sideDockFloatingY))
            )
        } else {
            floatingPosition = nil
        }

        return AppPreferences(
            sideDockEdge: edge,
            sideDockVerticalPosition: verticalPosition,
            sideDockDisplayID: displayID,
            isVirtualNotchEnabled: isVirtualNotchEnabled,
            sideDockFloatingPosition: floatingPosition
        )
    }

    func save(_ preferences: AppPreferences) {
        defaults.set(preferences.sideDockEdge.rawValue, forKey: Key.sideDockEdge)
        defaults.set(Double(preferences.sideDockVerticalPosition), forKey: Key.sideDockVerticalPosition)
        defaults.set(preferences.isVirtualNotchEnabled, forKey: Key.virtualNotchEnabled)

        if let position = preferences.sideDockFloatingPosition {
            defaults.set(Double(position.x), forKey: Key.sideDockFloatingX)
            defaults.set(Double(position.y), forKey: Key.sideDockFloatingY)
        } else {
            defaults.removeObject(forKey: Key.sideDockFloatingX)
            defaults.removeObject(forKey: Key.sideDockFloatingY)
        }

        if let displayID = preferences.sideDockDisplayID {
            defaults.set(Int(displayID), forKey: Key.sideDockDisplayID)
        } else {
            defaults.removeObject(forKey: Key.sideDockDisplayID)
        }
    }
}
