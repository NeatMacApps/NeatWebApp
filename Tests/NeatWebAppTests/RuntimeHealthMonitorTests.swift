import Foundation
import XCTest
@testable import NeatWebApp

@MainActor
final class RuntimeHealthMonitorTests: XCTestCase {
    func testEvaluateRequiresConsecutiveViolationsBeforeRecovery() {
        let monitor = RuntimeHealthMonitor(policy: testPolicy(consecutiveViolationLimit: 2))
        let bootstrap = makeBootstrap(createdAt: Date(timeIntervalSince1970: 0))
        let state = makeState(instanceID: bootstrap.instanceID)
        let metrics = RuntimeProcessMetrics(
            pid: state.pid,
            cpuPercent: 125,
            residentMemoryBytes: 200 * 1024 * 1024,
            physicalFootprintBytes: 300 * 1024 * 1024
        )

        let firstDecision = monitor.evaluate(
            state: state,
            bootstrap: bootstrap,
            metrics: metrics,
            now: Date(timeIntervalSince1970: 180)
        )
        let secondDecision = monitor.evaluate(
            state: state,
            bootstrap: bootstrap,
            metrics: metrics,
            now: Date(timeIntervalSince1970: 210)
        )

        XCTAssertNil(firstDecision)
        XCTAssertEqual(secondDecision?.consecutiveViolationCount, 2)
        XCTAssertEqual(secondDecision?.violations, [.cpu(percent: 125)])
    }

    func testEvaluateResetsAfterHealthySample() {
        let monitor = RuntimeHealthMonitor(policy: testPolicy(consecutiveViolationLimit: 2))
        let bootstrap = makeBootstrap(createdAt: Date(timeIntervalSince1970: 0))
        let state = makeState(instanceID: bootstrap.instanceID)
        let unhealthyMetrics = RuntimeProcessMetrics(
            pid: state.pid,
            cpuPercent: 125,
            residentMemoryBytes: 200 * 1024 * 1024,
            physicalFootprintBytes: 300 * 1024 * 1024
        )
        let healthyMetrics = RuntimeProcessMetrics(
            pid: state.pid,
            cpuPercent: 5,
            residentMemoryBytes: 200 * 1024 * 1024,
            physicalFootprintBytes: 300 * 1024 * 1024
        )

        _ = monitor.evaluate(
            state: state,
            bootstrap: bootstrap,
            metrics: unhealthyMetrics,
            now: Date(timeIntervalSince1970: 180)
        )
        XCTAssertNil(
            monitor.evaluate(
                state: state,
                bootstrap: bootstrap,
                metrics: healthyMetrics,
                now: Date(timeIntervalSince1970: 210)
            )
        )
        XCTAssertNil(
            monitor.evaluate(
                state: state,
                bootstrap: bootstrap,
                metrics: unhealthyMetrics,
                now: Date(timeIntervalSince1970: 240)
            )
        )
    }

    func testEvaluateFlagsPhysicalFootprintViolation() {
        let monitor = RuntimeHealthMonitor(policy: testPolicy(consecutiveViolationLimit: 1))
        let bootstrap = makeBootstrap(createdAt: Date(timeIntervalSince1970: 0))
        let state = makeState(instanceID: bootstrap.instanceID)
        let metrics = RuntimeProcessMetrics(
            pid: state.pid,
            cpuPercent: nil,
            residentMemoryBytes: 200 * 1024 * 1024,
            physicalFootprintBytes: 2 * RuntimeHealthPolicy.gibibyte
        )

        let decision = monitor.evaluate(
            state: state,
            bootstrap: bootstrap,
            metrics: metrics,
            now: Date(timeIntervalSince1970: 180)
        )

        XCTAssertEqual(decision?.violations, [.physicalFootprint(bytes: 2 * RuntimeHealthPolicy.gibibyte)])
    }

    func testEvaluateIgnoresYoungRuntime() {
        let monitor = RuntimeHealthMonitor(policy: testPolicy(consecutiveViolationLimit: 1))
        let bootstrap = makeBootstrap(createdAt: Date(timeIntervalSince1970: 100))
        let state = makeState(instanceID: bootstrap.instanceID)
        let metrics = RuntimeProcessMetrics(
            pid: state.pid,
            cpuPercent: 125,
            residentMemoryBytes: 200 * 1024 * 1024,
            physicalFootprintBytes: 300 * 1024 * 1024
        )

        let decision = monitor.evaluate(
            state: state,
            bootstrap: bootstrap,
            metrics: metrics,
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertNil(decision)
    }

    private func testPolicy(consecutiveViolationLimit: Int) -> RuntimeHealthPolicy {
        RuntimeHealthPolicy(
            checkInterval: .seconds(1),
            minimumRuntimeAge: 60,
            consecutiveViolationLimit: consecutiveViolationLimit,
            cpuPercentLimit: 100,
            residentMemoryLimitBytes: RuntimeHealthPolicy.gibibyte,
            physicalFootprintLimitBytes: RuntimeHealthPolicy.gibibyte
        )
    }

    private func makeBootstrap(createdAt: Date) -> RuntimeBootstrap {
        RuntimeBootstrap(
            instanceID: UUID(),
            appID: "gemini",
            definition: WebAppDefinition(
                id: "gemini",
                name: "Gemini",
                homeURL: URL(string: "https://gemini.google.com/app")!,
                accentColorName: "WebAppAccentBlue",
                shortDescription: "gemini.google.com"
            ),
            launchReason: .openFromLauncher,
            preferredDisplayID: nil,
            runtimeBuildIdentifier: "test-runtime",
            restoredPhase: nil,
            restoredWindowFrame: nil,
            restoredFloatingIconFrame: nil,
            createdAt: createdAt,
            hostVersion: "0.1.0"
        )
    }

    private func makeState(instanceID: UUID) -> RuntimeState {
        RuntimeState(
            instanceID: instanceID,
            appID: "gemini",
            pid: 123,
            phase: .windowVisible,
            windowFrame: CGRect(x: 10, y: 20, width: 460, height: 900),
            floatingIconFrame: nil,
            lastUpdatedAt: Date(timeIntervalSince1970: 120)
        )
    }
}
