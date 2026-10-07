import AppKit
import Foundation

/// Watches the host that launched this runtime and calls back once it is gone.
///
/// The host identity is resolved to an `NSRunningApplication` once at start, so a process
/// identifier recycled for an unrelated process is never mistaken for the original host.
@MainActor
final class RuntimeHostLifecycleMonitor {
    private var task: Task<Void, Never>?

    /// Returns false when a host identifier was given but that host can no longer be found.
    @discardableResult
    func start(hostProcessID: Int32?, onHostGone: @escaping @MainActor () -> Void) -> Bool {
        stop()
        guard let hostProcessID,
              hostProcessID != ProcessInfo.processInfo.processIdentifier else {
            return true
        }

        guard let hostApplication = NSRunningApplication(processIdentifier: hostProcessID),
              !hostApplication.isTerminated else {
            return false
        }

        task = Task { @MainActor [hostApplication] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                guard hostApplication.isTerminated else { continue }

                onHostGone()
                return
            }
        }
        return true
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
