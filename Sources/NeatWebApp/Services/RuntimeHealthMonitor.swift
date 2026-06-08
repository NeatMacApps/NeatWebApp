import Darwin
import Foundation

struct RuntimeProcessMetrics: Equatable {
    let pid: Int32
    let cpuPercent: Double?
    let residentMemoryBytes: UInt64
    let physicalFootprintBytes: UInt64
}

struct RuntimeHealthPolicy: Equatable {
    static let gibibyte: UInt64 = 1024 * 1024 * 1024

    static let standard = RuntimeHealthPolicy(
        checkInterval: .seconds(30),
        minimumRuntimeAge: 120,
        consecutiveViolationLimit: 3,
        cpuPercentLimit: 100,
        residentMemoryLimitBytes: 4 * gibibyte,
        physicalFootprintLimitBytes: 8 * gibibyte
    )

    let checkInterval: Duration
    let minimumRuntimeAge: TimeInterval
    let consecutiveViolationLimit: Int
    let cpuPercentLimit: Double
    let residentMemoryLimitBytes: UInt64
    let physicalFootprintLimitBytes: UInt64

    var isEnabled: Bool {
        consecutiveViolationLimit > 0
    }

    func violations(in metrics: RuntimeProcessMetrics) -> [RuntimeHealthViolation] {
        var violations: [RuntimeHealthViolation] = []

        if let cpuPercent = metrics.cpuPercent, cpuPercent >= cpuPercentLimit {
            violations.append(.cpu(percent: cpuPercent))
        }

        if metrics.residentMemoryBytes >= residentMemoryLimitBytes {
            violations.append(.residentMemory(bytes: metrics.residentMemoryBytes))
        }

        if metrics.physicalFootprintBytes >= physicalFootprintLimitBytes {
            violations.append(.physicalFootprint(bytes: metrics.physicalFootprintBytes))
        }

        return violations
    }
}

enum RuntimeHealthViolation: Equatable {
    case cpu(percent: Double)
    case residentMemory(bytes: UInt64)
    case physicalFootprint(bytes: UInt64)

    var diagnosticDescription: String {
        switch self {
        case let .cpu(percent):
            "CPU \(Self.format(percent: percent))"
        case let .residentMemory(bytes):
            "resident memory \(Self.format(bytes: bytes))"
        case let .physicalFootprint(bytes):
            "physical footprint \(Self.format(bytes: bytes))"
        }
    }

    private static func format(percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }

    private static func format(bytes: UInt64) -> String {
        let gibibytes = Double(bytes) / Double(RuntimeHealthPolicy.gibibyte)
        return String(format: "%.1f GiB", gibibytes)
    }
}

struct RuntimeHealthDecision: Equatable {
    let violations: [RuntimeHealthViolation]
    let consecutiveViolationCount: Int

    var diagnosticDescription: String {
        violations.map(\.diagnosticDescription).joined(separator: ", ")
    }
}

@MainActor
final class RuntimeHealthMonitor {
    private let policy: RuntimeHealthPolicy
    private var consecutiveViolations: [UUID: Int] = [:]

    init(policy: RuntimeHealthPolicy = .standard) {
        self.policy = policy
    }

    func evaluate(
        state: RuntimeState,
        bootstrap: RuntimeBootstrap,
        metrics: RuntimeProcessMetrics,
        now: Date = .now
    ) -> RuntimeHealthDecision? {
        guard policy.isEnabled else {
            return nil
        }

        guard now.timeIntervalSince(bootstrap.createdAt) >= policy.minimumRuntimeAge else {
            reset(instanceID: state.instanceID)
            return nil
        }

        let violations = policy.violations(in: metrics)
        guard !violations.isEmpty else {
            reset(instanceID: state.instanceID)
            return nil
        }

        let nextCount = (consecutiveViolations[state.instanceID] ?? 0) + 1
        consecutiveViolations[state.instanceID] = nextCount

        guard nextCount >= policy.consecutiveViolationLimit else {
            return nil
        }

        return RuntimeHealthDecision(
            violations: violations,
            consecutiveViolationCount: nextCount
        )
    }

    func reset(instanceID: UUID) {
        consecutiveViolations.removeValue(forKey: instanceID)
    }
}

protocol RuntimeProcessMetricsProviding: AnyObject {
    func metrics(for pid: Int32, at now: Date) -> RuntimeProcessMetrics?
}

final class DarwinRuntimeProcessMetricsProvider: RuntimeProcessMetricsProviding {
    private struct CPUObservation {
        let timestamp: Date
        let totalCPUTimeNanoseconds: UInt64
    }

    private var previousCPUObservations: [Int32: CPUObservation] = [:]

    func metrics(for pid: Int32, at now: Date = .now) -> RuntimeProcessMetrics? {
        guard pid > 0 else {
            return nil
        }

        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }

        guard result == 0 else {
            previousCPUObservations.removeValue(forKey: pid)
            return nil
        }

        let totalCPUTime = info.ri_user_time + info.ri_system_time
        let cpuPercent = cpuPercent(for: pid, now: now, totalCPUTime: totalCPUTime)
        previousCPUObservations[pid] = CPUObservation(
            timestamp: now,
            totalCPUTimeNanoseconds: totalCPUTime
        )

        return RuntimeProcessMetrics(
            pid: pid,
            cpuPercent: cpuPercent,
            residentMemoryBytes: info.ri_resident_size,
            physicalFootprintBytes: info.ri_phys_footprint
        )
    }

    private func cpuPercent(for pid: Int32, now: Date, totalCPUTime: UInt64) -> Double? {
        guard let previous = previousCPUObservations[pid] else {
            return nil
        }

        let elapsedSeconds = now.timeIntervalSince(previous.timestamp)
        guard elapsedSeconds > 0, totalCPUTime >= previous.totalCPUTimeNanoseconds else {
            return nil
        }

        let cpuDelta = totalCPUTime - previous.totalCPUTimeNanoseconds
        let elapsedNanoseconds = elapsedSeconds * 1_000_000_000
        return (Double(cpuDelta) / elapsedNanoseconds) * 100
    }
}
