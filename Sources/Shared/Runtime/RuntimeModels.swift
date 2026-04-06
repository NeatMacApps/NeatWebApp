import Foundation

enum RuntimeLaunchReason: String, Codable, Equatable, Sendable {
    case openFromLauncher
    case reopenExisting
}

enum RuntimePhase: String, Codable, Equatable, Sendable {
    case launching
    case windowVisible
    case collapsedToFloatingIcon
    case hidden
    case terminating
}

struct RuntimeBootstrap: Codable, Sendable {
    let instanceID: UUID
    let appID: String
    let definition: WebAppDefinition
    let launchReason: RuntimeLaunchReason
    let preferredDisplayID: UInt32?
    let runtimeBuildIdentifier: String?
    let restoredPhase: RuntimePhase?
    let restoredWindowFrame: CGRect?
    let restoredFloatingIconFrame: CGRect?
    let createdAt: Date
    let hostVersion: String
}

struct RuntimeState: Codable, Equatable, Sendable {
    let instanceID: UUID
    let appID: String
    let pid: Int32
    let phase: RuntimePhase
    let windowFrame: CGRect?
    let floatingIconFrame: CGRect?
    let lastUpdatedAt: Date
}

enum RuntimeCommandName: String, Codable, Equatable, Sendable {
    case showWindow
    case focusWindow
    case collapseWindow
    case expandWindow
    case hideWindow
    case reloadDefinition
    case terminateRuntime
    case increaseZoom
    case decreaseZoom
    case resetZoom
}

struct RuntimeCommand: Codable, Sendable {
    let instanceID: UUID
    let appID: String
    let sequence: Int
    let command: RuntimeCommandName
    let definition: WebAppDefinition?
}

enum RuntimeEventName: String, Codable, Equatable, Sendable {
    case runtimeStarted
    case windowShown
    case windowFocused
    case windowCollapsed
    case windowExpanded
    case windowHidden
    case runtimeTerminating
    case runtimeCrashed
}

struct RuntimeEvent: Codable, Sendable {
    let instanceID: UUID
    let appID: String
    let sequence: Int
    let event: RuntimeEventName
    let phase: RuntimePhase
    let windowFrame: CGRect?
    let floatingIconFrame: CGRect?
    let lastUpdatedAt: Date
}
