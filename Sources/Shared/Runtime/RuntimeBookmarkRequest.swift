import Foundation

/// Cookies stay in WebKit. Only the destination definition crosses the process boundary.
struct RuntimeBookmarkRequest: Codable, Sendable {
    let instanceID: UUID
    let sourceAppID: String
    let definition: WebAppDefinition
}

struct RuntimeBookmarkResult: Codable, Sendable {
    let instanceID: UUID
    let destinationAppID: String
    let succeeded: Bool
}
