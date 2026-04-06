import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService {
    enum RegistrationError: LocalizedError {
        case approvalRequired

        var errorDescription: String? {
            switch self {
            case .approvalRequired:
                return "Launch at Login needs approval in System Settings > General > Login Items."
            }
        }
    }

    private let appService: SMAppService

    init(appService: SMAppService = .mainApp) {
        self.appService = appService
    }

    var isEnabled: Bool {
        appService.status == .enabled || appService.status == .requiresApproval
    }

    var requiresApproval: Bool {
        appService.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard appService.status != .enabled else {
                return
            }

            try appService.register()

            if appService.status == .requiresApproval {
                throw RegistrationError.approvalRequired
            }

            return
        }

        guard appService.status != .notRegistered else {
            return
        }

        try appService.unregister()
    }
}
