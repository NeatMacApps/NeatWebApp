import CoreGraphics
import XCTest
@testable import NeatWebApp

final class SideDockPlacementTests: XCTestCase {
    private let desktop = CGRect(x: -1440, y: 24, width: 1440, height: 900)
    private let panelSize = CGSize(width: 47, height: 200)

    func testFloatingPlacementUsesBothAxes() {
        let frame = SideDockPlacementResolver.panelFrame(
            position: CGPoint(x: 0.35, y: 0.61), visibleFrame: desktop, panelSize: panelSize
        )
        XCTAssertEqual(frame.minX, -1428 + 1369 * 0.35, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 36 + 676 * 0.61, accuracy: 0.001)
        let restored = SideDockPlacementResolver.normalizedPosition(panelFrame: frame, visibleFrame: desktop)
        XCTAssertEqual(restored.x, 0.35, accuracy: 0.001)
        XCTAssertEqual(restored.y, 0.61, accuracy: 0.001)
    }

    func testAllBoundsStayInsideUsableDesktop() {
        for position in [CGPoint(x: -2, y: -3), CGPoint(x: 4, y: 5), CGPoint(x: 0.2, y: 0.8)] {
            let frame = SideDockPlacementResolver.panelFrame(
                position: position, visibleFrame: desktop, panelSize: panelSize
            )
            XCTAssertTrue(desktop.insetBy(dx: 12, dy: 12).contains(frame))
        }
    }

    func testLegacyPositionsBecomeFloatingPresets() {
        XCTAssertEqual(SideDockPlacementResolver.initialPosition(edge: .left, legacyPosition: 0.3),
                       CGPoint(x: 0, y: 0.3))
        XCTAssertEqual(SideDockPlacementResolver.initialPosition(edge: .right, legacyPosition: 0.3),
                       CGPoint(x: 1, y: 0.3))
        XCTAssertEqual(SideDockPlacementResolver.initialPosition(edge: .bottom, legacyPosition: 0.3),
                       CGPoint(x: 0.3, y: 0))
    }

    func testResolutionChangeRetainsBothCoordinates() {
        let newDesktop = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let position = CGPoint(x: 0.2, y: 0.8)
        let frame = SideDockPlacementResolver.panelFrame(
            position: position, visibleFrame: newDesktop, panelSize: panelSize
        )
        let restored = SideDockPlacementResolver.normalizedPosition(panelFrame: frame, visibleFrame: newDesktop)
        XCTAssertEqual(restored.x, position.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, position.y, accuracy: 0.001)
        XCTAssertTrue(newDesktop.insetBy(dx: 12, dy: 12).contains(frame))
    }

    func testOffscreenReleaseAndNonfiniteValuesRecover() {
        let position = SideDockPlacementResolver.normalizedPosition(
            panelFrame: CGRect(x: -4000, y: 8000, width: 47, height: 200), visibleFrame: desktop
        )
        XCTAssertEqual(position, CGPoint(x: 0, y: 1))
        let frame = SideDockPlacementResolver.panelFrame(
            position: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), visibleFrame: desktop, panelSize: panelSize
        )
        XCTAssertEqual(frame.midX, desktop.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, desktop.midY, accuracy: 0.001)
    }

    func testPanelWithNoTravelRemainsFiniteAndCentered() {
        let smallDesktop = CGRect(x: 100, y: 100, width: 50, height: 50)
        let frame = SideDockPlacementResolver.panelFrame(
            position: CGPoint(x: 0, y: 1), visibleFrame: smallDesktop,
            panelSize: CGSize(width: 47, height: 47)
        )
        XCTAssertEqual(frame.midX, smallDesktop.midX)
        XCTAssertEqual(frame.midY, smallDesktop.midY)
        XCTAssertEqual(SideDockPlacementResolver.normalizedPosition(panelFrame: frame, visibleFrame: smallDesktop),
                       CGPoint(x: 0.5, y: 0.5))
    }

    func testMinimumDockSizeMatchesCapsuleEndPadding() {
        let context = SideDockPresentationContext(
            apps: [], edge: .right, screenFrame: desktop, visibleFrame: desktop, verticalPosition: 0.72
        )
        XCTAssertEqual(
            context.layout.panelSize,
            CGSize(
                width: SideDockPresentationContext.Layout.thickness,
                height: SideDockPresentationContext.Layout.thickness
            )
        )
        XCTAssertFalse(context.layout.shouldScroll)
        XCTAssertEqual(SideDockPresentationContext.Layout.iconSlotSize / 2
                       + SideDockPresentationContext.Layout.padding,
                       SideDockPresentationContext.Layout.thickness / 2)
    }

    func testDefaultPresetAvoidsSystemDockSide() {
        XCTAssertEqual(SideDockPlacementResolver.recommendedDefaultEdge(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1350, height: 876)
        ), .left)
    }
}

final class AppPreferencesStoreTests: XCTestCase {
    func testMissingPreferenceUsesRecommendedDefaultEdge() {
        withStore { store in
            let preferences = store.load(defaultEdge: .left)

            XCTAssertEqual(preferences.sideDockEdge, .left)
            XCTAssertEqual(
                preferences.sideDockVerticalPosition,
                SideDockPlacementResolver.defaultVerticalPosition
            )
            XCTAssertNil(preferences.sideDockFloatingPosition)
            XCTAssertNil(preferences.sideDockDisplayID)
            XCTAssertEqual(
                preferences.isVirtualNotchEnabled,
                AppPreferencesStore.defaultVirtualNotchEnabled
            )
        }
    }

    func testPreferencesRoundTrip() {
        withStore { store in
            let expected = AppPreferences(
                sideDockEdge: .right,
                sideDockVerticalPosition: 0.31,
                sideDockDisplayID: 7,
                isVirtualNotchEnabled: false,
                sideDockFloatingPosition: CGPoint(x: 0.42, y: 0.67)
            )

            store.save(expected)

            XCTAssertEqual(store.load(defaultEdge: .left), expected)
        }
    }

    func testInvalidStoredEdgeFallsBackAndPositionIsClamped() {
        let suiteName = "SideDockPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set("center", forKey: "sideDock.edge")
        defaults.set(5.0, forKey: "sideDock.verticalPosition")

        let preferences = AppPreferencesStore(defaults: defaults).load(defaultEdge: .left)

        XCTAssertEqual(preferences.sideDockEdge, .left)
        XCTAssertEqual(preferences.sideDockVerticalPosition, 1)
    }

    func testMissingAxisUsesLegacyPositionAndFloatingValuesAreClamped() throws {
        let suite = "SideDockPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppPreferencesStore(defaults: defaults)
        defaults.set(5.0, forKey: "sideDock.floatingX")
        XCTAssertNil(store.load(defaultEdge: .right).sideDockFloatingPosition)
        defaults.set(-1.0, forKey: "sideDock.floatingY")
        XCTAssertEqual(store.load(defaultEdge: .right).sideDockFloatingPosition, CGPoint(x: 1, y: 0))
        store.save(AppPreferences(sideDockEdge: .right, sideDockVerticalPosition: 0.72,
                                  sideDockDisplayID: nil, isVirtualNotchEnabled: true))
        XCTAssertNil(defaults.object(forKey: "sideDock.floatingX"))
        XCTAssertNil(defaults.object(forKey: "sideDock.floatingY"))
    }

    func testGlassInsetKeepsTheAttachedEdgeFlush() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 47)
        let shape = EdgeAttachedShape(edge: .bottom, cornerRadius: 15)
        let original = shape.path(in: rect).boundingRect
        let inset = shape.inset(by: 4).path(in: rect).boundingRect

        XCTAssertEqual(original.maxY, rect.maxY, accuracy: 0.5)
        XCTAssertEqual(inset.maxY, rect.maxY, accuracy: 0.5)
        XCTAssertGreaterThan(inset.minY, original.minY)
        XCTAssertGreaterThan(inset.minX, original.minX)
        XCTAssertLessThan(inset.maxX, original.maxX)
    }

    private func withStore(_ body: (AppPreferencesStore) -> Void) {
        let suiteName = "SideDockPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        body(AppPreferencesStore(defaults: defaults))
    }
}
