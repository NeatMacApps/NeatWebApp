import Combine
import MacKitUpdater
import Sparkle
import SwiftUI

/// 应用内自动更新的统一入口。
///
/// 除了持有 Sparkle 控制器（必须活到应用退出，否则后台检查会停），
/// 还负责在更新覆盖安装之前把所有 WebApp 运行时收掉——运行时是从应用包内部
/// 启动的独立进程，更新会把整个应用包整体换掉，留着它们会继续跑在旧代码上。
@MainActor
final class AppUpdater: NSObject, ObservableObject,
    @preconcurrency SPUUpdaterDelegate,
    @preconcurrency SPUStandardUserDriverDelegate {
    /// 后台已发现、但还没让用户处理的版本号；没有待处理更新时为 nil。
    @Published private(set) var availableVersion: String?
    /// 跟随 Sparkle 的真实状态；值没变不写。菜单按钮不要观察本对象。
    @Published private(set) var canCheckForUpdates = true
    private var canCheckForUpdatesCancellable: AnyCancellable?

    private let onWillInstallUpdate: @MainActor () -> Void
    private var hasPreparedForInstall = false

    private lazy var controller = SparkleUpdateChecker(
        updaterDelegate: self,
        userDriverDelegate: self
    )

    init(onWillInstallUpdate: @escaping @MainActor () -> Void) {
        self.onWillInstallUpdate = onWillInstallUpdate
        super.init()
        _ = controller
        canCheckForUpdatesCancellable = updater.publisher(for: \.canCheckForUpdates)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                guard let self, self.canCheckForUpdates != canCheck else { return }
                self.canCheckForUpdates = canCheck
            }
    }

    var updater: SPUUpdater {
        controller.updater
    }

    // MARK: - 覆盖安装前的收尾

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        prepareForInstall()
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        prepareForInstall()
    }

    /// 上面两个回调按安装方式不同只会到一个或先后都到，取先到的那次，重复调用无副作用。
    private func prepareForInstall() {
        guard !hasPreparedForInstall else {
            return
        }

        hasPreparedForInstall = true
        onWillInstallUpdate()
    }

    // MARK: - 菜单栏应用的温和提醒

    /// 本应用常驻菜单栏、没有主窗口，后台发现更新时直接弹窗会打断用户手上的事，
    /// 所以只有用户主动触发时才让 Sparkle 抢焦点，其余情况把入口挂回菜单里。
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        availableVersion = handleShowingUpdate ? nil : update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
