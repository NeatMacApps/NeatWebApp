import AppKit
import Foundation
import MacKitLaunchAtLogin
import Observation

/// 宿主应用根状态。按职责拆到同目录 `AppModel+*.swift` extension：
/// Launcher / Favicon / WebApps / Preferences。
@Observable
@MainActor
final class AppModel {
    // MARK: - Constants

    static let launcherHideDelay: Duration = .milliseconds(800)
    static let launcherTransitionDuration: Duration = .milliseconds(220)
    static let menuBarIconVisibleKey = "menuBar.iconVisible"

    // MARK: - Published state
    // 跨文件 extension 会写入；对外仍以只读用法为主（同模块内可写）。

    var apps: [WebAppDefinition] = []
    var detectedNotchScreens: [ScreenNotchGeometry] = []
    var launcherContext: LauncherPresentationContext?
    var diagnosticsMessage = "Move the mouse into the notch zone to reveal the launcher."
    var isNotchDebugOverlayVisible = false
    var isLauncherVisible = false
    var isTemporarilySuppressed = false
    var activeRuntimeAppID: String?
    /// 图标内存缓存世代：压力丢缓存或磁盘回填后递增，驱动界面重新读盘。
    var faviconCacheGeneration: UInt64 = 0
    var isLaunchAtLoginEnabled = false
    /// 登录项被系统挂起的例外状态：正常开启不会出现，只有它曾被关掉过才会。
    /// 此时开关点了也不会生效，界面需要给出解释，否则表现为「怎么点都没反应」。
    var isLaunchAtLoginBlockedBySystem = false
    var isMenuBarIconVisible = true
    var sideDockEdge: SideDockEdge = .right
    var sideDockVerticalPosition = SideDockPlacementResolver.defaultVerticalPosition
    var sideDockDisplayID: CGDirectDisplayID?
    var isVirtualNotchEnabled = AppPreferencesStore.defaultVirtualNotchEnabled
    var collapsedWebApps: [WebAppDefinition] = []

    // MARK: - Collaborators

    @ObservationIgnored
    let overlayController = LauncherOverlayController()

    @ObservationIgnored
    let notchActivationMonitor = NotchActivationMonitor()

    @ObservationIgnored
    let notchDebugOverlayController = NotchDebugOverlayController()

    @ObservationIgnored
    let customAppStore = CustomWebAppStore()

    @ObservationIgnored
    let faviconStore = WebAppFaviconStore()

    @ObservationIgnored
    let faviconMemoryCache = WebAppFaviconMemoryCache()

    @ObservationIgnored
    var memoryPressureMonitor: HostMemoryPressureMonitor?

    /// 系统内存告警期间暂停图标网络预取，压力解除后不自动恢复预取风暴（下次启动或显式刷新再抓）。
    @ObservationIgnored
    var isFaviconPrefetchSuspended = false

    @ObservationIgnored
    let launchAtLoginService = LaunchAtLoginService()

    @ObservationIgnored
    let appPreferencesStore = AppPreferencesStore()

    @ObservationIgnored
    let sideDockOverlayController = SideDockOverlayController()

    @ObservationIgnored
    let sideDockReserveStore = SideDockReserveStore()

    @ObservationIgnored
    lazy var runtimeCoordinator = WebAppRuntimeCoordinator(
        dockReserveStore: sideDockReserveStore,
        onActiveAppIDChange: { [weak self] appID in
            self?.activeRuntimeAppID = appID
        },
        onDiagnosticMessage: { [weak self] message in
            self?.diagnosticsMessage = message
        },
        onRuntimeStatesChange: { [weak self] states in
            self?.handleRuntimeStatesChange(states)
        }
    )

    // MARK: - Session / tasks

    @ObservationIgnored
    var screenObserver: NSObjectProtocol?

    @ObservationIgnored
    var activationObserver: NSObjectProtocol?

    @ObservationIgnored
    var hasStarted = false

    @ObservationIgnored
    var failedFaviconAppIDs: Set<String> = []

    @ObservationIgnored
    var faviconLoadTasks: [String: Task<Void, Never>] = [:]

    @ObservationIgnored
    var hideLauncherTask: Task<Void, Never>?

    @ObservationIgnored
    var pendingActivationTask: Task<Void, Never>?

    @ObservationIgnored
    var pendingActivationGeometryID: String?

    // MARK: - Lifecycle

    func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        loadApps()
        restoreCachedFavicons()
        // 虚拟刘海开关会影响屏幕热区的识别结果，必须先恢复偏好再做首次识别。
        loadAppPreferences()
        restoreMenuBarIconVisibility()
        refreshScreenState()
        refreshLaunchAtLoginState()
        runtimeCoordinator.refreshRegistry()
        preloadFavicons()
        startMemoryPressureMonitorIfNeeded()

        notchActivationMonitor.start { [weak self] mouseLocation, eventType in
            self?.handleMouseEvent(mouseLocation, eventType)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreenState()
            }
        }

        // 用户是在系统设置里放行登录项的，应用收不到任何回调；
        // 回到应用时重读一次，界面才不会一直停在「等待放行」。
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLaunchAtLoginState()
            }
        }
    }
}
