import AppKit
import Foundation

@MainActor
protocol RuntimeStandbyProviding: AnyObject {
    /// Hands out the ready standby runtime, if any, and schedules its replacement.
    func takeReadyStandby() -> UUID?
    /// The standby was handed a web app but never started it; kill it so the fallback launch is the only runtime.
    func discardAdoptedStandby(_ instanceID: UUID)
    /// Warm a standby unless one is already running or the pool is paused.
    func prepare()
    /// Drop the standby under memory pressure; the next open launches normally and re-arms the pool.
    func releaseForMemoryPressure()
    func terminate()
}

/// Keeps at most one pre-launched, app-agnostic runtime so opening a not-running web app
/// skips process launch, app start-up and WebKit warm-up. See `docs/design/warm-standby-runtime.md`.
@MainActor
final class RuntimeStandbyPool: RuntimeStandbyProviding {
    private enum Slot {
        case empty
        case launching(UUID)
        case ready(UUID, NSRunningApplication)
    }

    /// Wait before warming a replacement so it does not compete with the page that was just opened.
    static let replenishDelay: Duration = .seconds(5)
    static let readyDeadline: Duration = .seconds(20)

    private let launcher: RuntimeLauncher
    private let commandBus: RuntimeCommandBus
    private var slot = Slot.empty
    private var launchingApplication: NSRunningApplication?
    private var readyInstanceIDs: Set<UUID> = []
    private var adoptedApplications: [UUID: NSRunningApplication] = [:]
    private var isPausedForMemoryPressure = false
    private var replenishTask: Task<Void, Never>?
    private var eventObserver: NSObjectProtocol?

    init(launcher: RuntimeLauncher, commandBus: RuntimeCommandBus) {
        self.launcher = launcher
        self.commandBus = commandBus
        eventObserver = commandBus.observeEvents { [weak self] event in
            self?.handle(event)
        }
    }

    func takeReadyStandby() -> UUID? {
        if isPausedForMemoryPressure {
            isPausedForMemoryPressure = false
            scheduleReplenish()
            return nil
        }

        guard case let .ready(instanceID, application) = slot else {
            return nil
        }

        slot = .empty
        scheduleReplenish()
        guard !application.isTerminated else {
            return nil
        }

        adoptedApplications[instanceID] = application
        // Only kept long enough for the adoption deadline in the runtime coordinator.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.adoptedApplications[instanceID] = nil
        }
        return instanceID
    }

    func discardAdoptedStandby(_ instanceID: UUID) {
        adoptedApplications.removeValue(forKey: instanceID)?.forceTerminate()
    }

    func prepare() {
        guard !isPausedForMemoryPressure, case .empty = slot else {
            return
        }

        let instanceID = UUID()
        slot = .launching(instanceID)
        readyInstanceIDs.removeAll()
        do {
            try launcher.launchStandby(instanceID: instanceID) { [weak self] application in
                guard let self, case .launching(instanceID) = self.slot else {
                    application?.terminate()
                    return
                }

                guard let application else {
                    self.slot = .empty
                    return
                }

                self.launchingApplication = application
                self.promoteIfReady(instanceID)
            }
        } catch {
            slot = .empty
            return
        }

        // A standby that never reports ready (crashed, blocked) must not hold the slot forever.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.readyDeadline)
            guard let self, case .launching(instanceID) = self.slot else {
                return
            }

            self.launchingApplication?.forceTerminate()
            self.launchingApplication = nil
            self.slot = .empty
        }
    }

    func releaseForMemoryPressure() {
        isPausedForMemoryPressure = true
        terminate()
    }

    func terminate() {
        replenishTask?.cancel()
        replenishTask = nil
        switch slot {
        case let .ready(_, application):
            application.terminate()
        case .launching:
            launchingApplication?.terminate()
        case .empty:
            break
        }
        slot = .empty
        launchingApplication = nil
    }

    private func handle(_ event: RuntimeEvent) {
        guard event.event == .standbyReady,
              case let .launching(instanceID) = slot,
              event.instanceID == instanceID else {
            return
        }

        // The ready event can beat the Launch Services completion that hands us the process.
        readyInstanceIDs.insert(instanceID)
        promoteIfReady(instanceID)
    }

    private func promoteIfReady(_ instanceID: UUID) {
        guard readyInstanceIDs.contains(instanceID),
              let application = launchingApplication else {
            return
        }

        readyInstanceIDs.removeAll()
        launchingApplication = nil
        slot = .ready(instanceID, application)
    }

    private func scheduleReplenish() {
        replenishTask?.cancel()
        replenishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.replenishDelay)
            guard !Task.isCancelled else {
                return
            }

            self?.replenishTask = nil
            self?.prepare()
        }
    }
}
