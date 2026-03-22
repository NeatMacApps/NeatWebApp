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
