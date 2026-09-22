import Foundation

@MainActor
struct RuntimeBootstrapLoader {
    enum LoaderError: LocalizedError {
        case missingBootstrapPath
        case invalidBootstrapPath(String)
        case instanceMismatch(expected: UUID, actual: UUID)

        var errorDescription: String? {
            switch self {
            case .missingBootstrapPath:
                "Missing --bootstrap-path for NeatWebAppRuntime."
            case let .invalidBootstrapPath(path):
                "Runtime bootstrap file was not found at \(path)."
            case let .instanceMismatch(expected, actual):
                "Runtime bootstrap instance mismatch. Expected \(expected.uuidString), got \(actual.uuidString)."
            }
        }
    }

    private let registryStore: RuntimeRegistryStore

    init(registryStore: RuntimeRegistryStore = RuntimeRegistryStore()) {
        self.registryStore = registryStore
    }

    func load(arguments: [String] = CommandLine.arguments) throws -> RuntimeBootstrap {
        guard let bootstrapPath = value(after: "--bootstrap-path", in: arguments) else {
            throw LoaderError.missingBootstrapPath
        }

        let bootstrapURL = URL(fileURLWithPath: bootstrapPath)
        guard FileManager.default.fileExists(atPath: bootstrapURL.path) else {
            throw LoaderError.invalidBootstrapPath(bootstrapPath)
        }

        let bootstrap = try registryStore.loadBootstrap(at: bootstrapURL)
        if let instanceValue = value(after: "--instance-id", in: arguments),
           let expectedInstanceID = UUID(uuidString: instanceValue),
           expectedInstanceID != bootstrap.instanceID {
            throw LoaderError.instanceMismatch(expected: expectedInstanceID, actual: bootstrap.instanceID)
        }

        return bootstrap
    }

    /// 从启动参数里读宿主进程号（`--host-pid`）：宿主异常没了时，运行时靠它认出
    /// 「当初拉起我的那个宿主已经不在」，再自己收尾退出。只认正数，缺失或非法返回 nil。
    nonisolated static func processIdentifier(after flag: String, in arguments: [String]) -> Int32? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1),
              let value = Int32(arguments[index + 1]),
              value > 0 else {
            return nil
        }

        return value
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }
}
