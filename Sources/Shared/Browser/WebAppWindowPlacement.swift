import AppKit

/// 侧边 Dock 当前占用的那条屏幕边。宿主写入、运行时读取，两边必须用同一份。
struct SideDockScreenReserve: Equatable, Sendable, Codable {
    enum Edge: String, Codable, Sendable {
        case left
        case right
        case bottom
    }

    var edge: Edge
    var displayID: UInt32?
    var thickness: CGFloat
}

/// 网页窗口不得压住本应用侧边 Dock：在系统 `visibleFrame` 上再扣掉 Dock 所在边的整条厚度。
enum SideDockWindowAvoidance {
    static let didChangeNotification = Notification.Name("com.geraltgraham.NeatWebApp.sideDock.reserveDidChange")

    static func usableFrame(
        visibleFrame: CGRect,
        reserve: SideDockScreenReserve?,
        screenDisplayID: UInt32?
    ) -> CGRect {
        guard let reserve, reserve.thickness > 0 else {
            return visibleFrame
        }

        if let reservedDisplayID = reserve.displayID,
           let screenDisplayID,
           reservedDisplayID != screenDisplayID {
            return visibleFrame
        }

        let thickness = min(reserve.thickness, edgeLength(for: reserve.edge, in: visibleFrame))
        guard thickness > 0 else {
            return visibleFrame
        }

        switch reserve.edge {
        case .left:
            return CGRect(
                x: visibleFrame.minX + thickness,
                y: visibleFrame.minY,
                width: visibleFrame.width - thickness,
                height: visibleFrame.height
            )
        case .right:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width - thickness,
                height: visibleFrame.height
            )
        case .bottom:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY + thickness,
                width: visibleFrame.width,
                height: visibleFrame.height - thickness
            )
        }
    }

    static func clamp(_ frame: CGRect, into usableFrame: CGRect) -> CGRect {
        let width = min(max(frame.width, 1), max(usableFrame.width, 1))
        let height = min(max(frame.height, 1), max(usableFrame.height, 1))
        let maxX = usableFrame.maxX - width
        let maxY = usableFrame.maxY - height
        guard usableFrame.width > 0, usableFrame.height > 0 else {
            return frame
        }

        return CGRect(
            x: min(max(frame.minX, usableFrame.minX), max(maxX, usableFrame.minX)),
            y: min(max(frame.minY, usableFrame.minY), max(maxY, usableFrame.minY)),
            width: width,
            height: height
        )
    }

    private static func edgeLength(for edge: SideDockScreenReserve.Edge, in visibleFrame: CGRect) -> CGFloat {
        switch edge {
        case .left, .right:
            visibleFrame.width
        case .bottom:
            visibleFrame.height
        }
    }
}

struct WebAppWindowPlacementScreen: Equatable, Sendable {
    let displayID: UInt32?
    let localizedName: String
    let frame: CGRect
    let visibleFrame: CGRect
    /// 扣掉本应用侧边 Dock 占用条之后，窗口可以落到的区域。
    let usableFrame: CGRect
    let notchGeometry: ScreenNotchGeometry?

    init(
        displayID: UInt32?,
        localizedName: String,
        frame: CGRect,
        visibleFrame: CGRect,
        usableFrame: CGRect? = nil,
        notchGeometry: ScreenNotchGeometry?
    ) {
        self.displayID = displayID
        self.localizedName = localizedName
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.usableFrame = usableFrame ?? visibleFrame
        self.notchGeometry = notchGeometry
    }

    init(screen: NSScreen, dockReserve: SideDockScreenReserve? = nil) {
        let visibleFrame = screen.visibleFrame
        let displayID = screen.displayID
        self.init(
            displayID: displayID,
            localizedName: screen.localizedName,
            frame: screen.frame,
            visibleFrame: visibleFrame,
            usableFrame: SideDockWindowAvoidance.usableFrame(
                visibleFrame: visibleFrame,
                reserve: dockReserve,
                screenDisplayID: displayID
            ),
            notchGeometry: ScreenNotchGeometry(screen: screen)
        )
    }
}

enum WebAppWindowPlacementResolver {
    private static let notchSpacing: CGFloat = 80
    private static let fallbackTopMargin: CGFloat = 84

    static func resolveFrame(
        preference: StoredWebAppPreference,
        preferredGeometry: ScreenNotchGeometry?,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackDisplayID: UInt32?,
        defaultFrameSize: CGSize,
        minimumFrameSize: CGSize
    ) -> CGRect {
        let preferredScreen = resolvePreferredScreen(
            preferredGeometry: preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: fallbackDisplayID
        )
        let preferredNotch = resolvePreferredNotch(
            preferredGeometry: preferredGeometry,
            preferredScreen: preferredScreen
        )

        if let storedPlacement = preference.resolvedWindowPlacement,
           let matchedScreen = resolveStoredScreen(for: storedPlacement, availableScreens: availableScreens),
           !isFillVisibleFrame(storedPlacement.frame, visibleFrame: matchedScreen.visibleFrame) {
            // 用户拖过的尺寸只许缩小以塞进屏幕，不许被「最小窗口」抬成整块可用桌面。
            let size = fittedSize(storedPlacement.frame.size, within: matchedScreen.usableFrame.size)
            let frame = CGRect(origin: storedPlacement.frame.origin, size: size)
            return clamp(frame, into: matchedScreen.usableFrame)
        }

        let fallbackScreen = preferredScreen ?? availableScreens.first
        let safeDefaultSize = sanitizedDefaultSize(
            defaultFrameSize,
            visibleSize: fallbackScreen?.visibleFrame.size
        )
        let requestedSize = usableStoredSize(
            preference.resolvedWindowPlacement?.frame.size,
            visibleSize: fallbackScreen?.visibleFrame.size
        ) ?? safeDefaultSize
        let placementBounds = fallbackPlacementBounds(
            preferredNotch: preferredNotch ?? fallbackScreen?.notchGeometry,
            usableFrame: fallbackScreen?.usableFrame
        )
        let size = clampedSize(
            requestedSize,
            within: placementBounds?.size ?? fallbackScreen?.usableFrame.size ?? safeDefaultSize,
            minimumFrameSize: sanitizedMinimumSize(
                minimumFrameSize,
                visibleSize: placementBounds?.size ?? fallbackScreen?.usableFrame.size
            )
        )

        guard let fallbackScreen else {
            return CGRect(origin: .zero, size: size)
        }

        return fallbackFrame(
            size: size,
            preferredNotch: preferredNotch ?? fallbackScreen.notchGeometry,
            visibleFrame: fallbackScreen.visibleFrame,
            placementBounds: placementBounds ?? fallbackScreen.usableFrame
        )
    }

    /// 铺满当前可用桌面的框不是用户选的窗口大小，而是缩放 / 系统贴边的结果。
    static func isFillVisibleFrame(_ frame: CGRect, visibleFrame: CGRect, tolerance: CGFloat = 8) -> Bool {
        isFillVisibleSize(frame.size, visibleSize: visibleFrame.size, tolerance: tolerance) &&
            abs(frame.minX - visibleFrame.minX) <= tolerance &&
            abs(frame.minY - visibleFrame.minY) <= tolerance
    }

    static func isFillVisibleSize(_ size: CGSize, visibleSize: CGSize, tolerance: CGFloat = 8) -> Bool {
        abs(size.width - visibleSize.width) <= tolerance &&
            abs(size.height - visibleSize.height) <= tolerance
    }

    static func isFrameVisible(_ frame: CGRect, across screens: [WebAppWindowPlacementScreen]) -> Bool {
        screens.contains { $0.visibleFrame.contains(frame) }
    }

    static func clamp(_ frame: CGRect, into screens: [WebAppWindowPlacementScreen]) -> CGRect {
        let matchedScreen = screens.first(where: { $0.usableFrame.intersects(frame) || $0.visibleFrame.intersects(frame) })
            ?? screens.first
        guard let matchedScreen else {
            return frame
        }

        return SideDockWindowAvoidance.clamp(frame, into: matchedScreen.usableFrame)
    }

    private static func resolveStoredScreen(
        for placement: StoredWindowPlacement,
        availableScreens: [WebAppWindowPlacementScreen]
    ) -> WebAppWindowPlacementScreen? {
        guard let storedDisplay = placement.display else {
            return nil
        }

        return availableScreens.first(where: { screen in
            if let storedDisplayID = storedDisplay.displayID,
               let screenDisplayID = screen.displayID,
               storedDisplayID == screenDisplayID {
                return true
            }

            // 显示器名字会随系统语言变，不能当主键；编号对不上时用物理尺寸兜底。
            return storedDisplay.frame.size == screen.frame.size
        })
    }

    private static func usableStoredSize(_ size: CGSize?, visibleSize: CGSize?) -> CGSize? {
        guard let size else {
            return nil
        }

        if let visibleSize, isFillVisibleSize(size, visibleSize: visibleSize) {
            return nil
        }

        return size
    }

    private static func sanitizedDefaultSize(_ size: CGSize, visibleSize: CGSize?) -> CGSize {
        if let visibleSize, isFillVisibleSize(size, visibleSize: visibleSize) {
            return WebAppWindowMetrics.defaultContentSize
        }

        return size
    }

    private static func sanitizedMinimumSize(_ size: CGSize, visibleSize: CGSize?) -> CGSize {
        if let visibleSize, isFillVisibleSize(size, visibleSize: visibleSize) {
            return WebAppWindowMetrics.minimumContentSize
        }

        return size
    }

    private static func fittedSize(_ size: CGSize, within availableSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, 1), availableSize.width),
            height: min(max(size.height, 1), availableSize.height)
        )
    }

    private static func resolvePreferredScreen(
        preferredGeometry: ScreenNotchGeometry?,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackDisplayID: UInt32?
    ) -> WebAppWindowPlacementScreen? {
        if let preferredDisplayID = preferredGeometry?.displayID,
           let screen = availableScreens.first(where: { $0.displayID == preferredDisplayID }) {
            return screen
        }

        if let preferredGeometry,
           let screen = availableScreens.first(where: { $0.frame == preferredGeometry.screenFrame }) {
            return screen
        }

        if let fallbackDisplayID,
           let screen = availableScreens.first(where: { $0.displayID == fallbackDisplayID }) {
            return screen
        }

        return availableScreens.first(where: { $0.notchGeometry != nil }) ?? availableScreens.first
    }

    private static func resolvePreferredNotch(
        preferredGeometry: ScreenNotchGeometry?,
        preferredScreen: WebAppWindowPlacementScreen?
    ) -> ScreenNotchGeometry? {
        if let preferredGeometry {
            return preferredGeometry
        }

        return preferredScreen?.notchGeometry
    }

    private static func clampedSize(
        _ size: CGSize,
        within availableSize: CGSize,
        minimumFrameSize: CGSize
    ) -> CGSize {
        CGSize(
            width: min(availableSize.width, max(minimumFrameSize.width, size.width)),
            height: min(availableSize.height, max(minimumFrameSize.height, size.height))
        )
    }

    private static func fallbackFrame(
        size: CGSize,
        preferredNotch: ScreenNotchGeometry?,
        visibleFrame: CGRect,
        placementBounds: CGRect
    ) -> CGRect {
        let origin: CGPoint

        if let preferredNotch {
            origin = CGPoint(
                x: preferredNotch.notchRect.midX - (size.width / 2),
                y: placementBounds.maxY - size.height
            )
        } else {
            origin = CGPoint(
                x: visibleFrame.midX - (size.width / 2),
                y: visibleFrame.maxY - size.height - fallbackTopMargin
            )
        }

        return clamp(CGRect(origin: origin, size: size), into: placementBounds)
    }

    private static func fallbackPlacementBounds(
        preferredNotch: ScreenNotchGeometry?,
        usableFrame: CGRect?
    ) -> CGRect? {
        guard let usableFrame else {
            return nil
        }

        guard let preferredNotch else {
            return usableFrame
        }

        let maxY = max(usableFrame.minY, preferredNotch.notchRect.minY - notchSpacing)
        return CGRect(
            x: usableFrame.minX,
            y: usableFrame.minY,
            width: usableFrame.width,
            height: maxY - usableFrame.minY
        )
    }

    private static func clamp(_ frame: CGRect, into visibleFrame: CGRect) -> CGRect {
        SideDockWindowAvoidance.clamp(frame, into: visibleFrame)
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// 宿主和运行时各有一份 UserDefaults，侧边 Dock 占用必须写到同一份文件。
final class SideDockReserveStore {
    private let fileURL: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let notificationCenter: DistributedNotificationCenter

    init(
        rootDirectoryURL: URL? = nil,
        notificationCenter: DistributedNotificationCenter = .default()
    ) {
        self.fileURL = try? RuntimeSupportDirectory.directoryURL(
            named: "Preferences",
            rootDirectoryURL: rootDirectoryURL
        ).appending(path: "side-dock-reserve.json")
        self.notificationCenter = notificationCenter
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> SideDockScreenReserve? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              !data.isEmpty else {
            return nil
        }

        return try? decoder.decode(SideDockScreenReserve.self, from: data)
    }

    func save(_ reserve: SideDockScreenReserve?) {
        guard let fileURL else {
            return
        }

        if let reserve, let data = try? encoder.encode(reserve) {
            try? data.write(to: fileURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }

        notificationCenter.postNotificationName(
            SideDockWindowAvoidance.didChangeNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    func observeChanges(using handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        notificationCenter.addObserver(
            forName: SideDockWindowAvoidance.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        notificationCenter.removeObserver(observer)
    }
}
