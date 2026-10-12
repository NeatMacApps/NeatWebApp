import Foundation

struct WebAppDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let homeURL: URL
    let accentColorName: String
    let shortDescription: String

    static let examples: [WebAppDefinition] = [
        WebAppDefinition(
            id: "claude",
            name: "Claude",
            homeURL: URL(string: "https://claude.ai")!,
            accentColorName: "WebAppAccentOrange",
            shortDescription: "AI workspace"
        ),
        WebAppDefinition(
            id: "chatgpt",
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com")!,
            accentColorName: "WebAppAccentGreen",
            shortDescription: "OpenAI chat"
        ),
        WebAppDefinition(
            id: "notion",
            name: "Notion",
            homeURL: URL(string: "https://www.notion.so")!,
            accentColorName: "WebAppAccentGray",
            shortDescription: "Notes and wiki"
        ),
        WebAppDefinition(
            id: "figma",
            name: "Figma",
            homeURL: URL(string: "https://www.figma.com")!,
            accentColorName: "WebAppAccentRed",
            shortDescription: "Design workspace"
        ),
        WebAppDefinition(
            id: "linear",
            name: "Linear",
            homeURL: URL(string: "https://linear.app")!,
            accentColorName: "WebAppAccentBlue",
            shortDescription: "Issue tracking"
        ),
        WebAppDefinition(
            id: "github",
            name: "GitHub",
            homeURL: URL(string: "https://github.com")!,
            accentColorName: "WebAppAccentPurple",
            shortDescription: "Code hosting"
        )
    ]
}

extension Array where Element: Identifiable {
    /// Returns the array with the items in `sourceIDs` moved before `targetID`, or to the end when
    /// `targetID` is nil (the shape of a SwiftUI reorder difference). Moved items keep their
    /// current relative order; unknown IDs are ignored.
    func movingItems(withIDs sourceIDs: [Element.ID], before targetID: Element.ID?) -> [Element] {
        let moving = Set(sourceIDs)
        let movedItems = filter { moving.contains($0.id) }
        var remaining = filter { !moving.contains($0.id) }
        // Dropping before a moved item means "before the next item that stays put".
        let anchorID = targetID.flatMap { id -> Element.ID? in
            guard moving.contains(id), let index = firstIndex(where: { $0.id == id }) else {
                return id
            }
            return self[index...].first { !moving.contains($0.id) }?.id
        }
        let insertionIndex = anchorID.flatMap { id in remaining.firstIndex { $0.id == id } } ?? remaining.count
        remaining.insert(contentsOf: movedItems, at: insertionIndex)
        return remaining
    }
}
