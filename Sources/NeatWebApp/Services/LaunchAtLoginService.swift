import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService {
    private let appService: SMAppService

    init(appService: SMAppService = .mainApp) {
        self.appService = appService
    }

    /// 只认「系统确实会在登录时启动它」这一种状态。
    ///
    /// 注册成功但被系统挂起（`requiresApproval`）时必须算作未启用：
    /// 那种状态下开机并不会启动，把它并进「已启用」会让开关显示成开着却不生效。
    var isEnabled: Bool {
        appService.status == .enabled
    }

    /// 登录项被系统挂起：正常注册不会走到这里，只有这个登录项**曾经被关掉过**
    /// （用户在系统设置里关掉，或应用签名变化导致原登记作废）才会出现。
    /// 此时再怎么注册都不会生效，必须由用户去系统设置里重新放行。
    var isBlockedBySystem: Bool {
        appService.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if appService.status != .enabled {
                try appService.register()
            }
        } else if appService.status != .notRegistered {
            try appService.unregister()
        }
    }

    /// 打开系统设置的登录项页面，供用户解除上面那种被挂起的状态。
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
