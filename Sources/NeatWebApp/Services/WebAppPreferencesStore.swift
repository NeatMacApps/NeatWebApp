import CoreGraphics
import Foundation

struct StoredDisplayIdentity: Codable, Equatable, Sendable {
    var displayID: UInt32?
    var localizedName: String
    var frame: CGRect
}

struct StoredWindowPlacement: Codable, Equatable, Sendable {
    var frame: CGRect
    var display: StoredDisplayIdentity?
}

/// 用户手动隐藏掉的一个网页元素。
///
/// 规则按**站点**归属而不是按页面：用户隐藏掉侧栏广告之后，翻到同一站点的下一页不该又冒出来。
struct HiddenElementRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// 归属站点，已归一化（小写、去掉开头的 `www.`）。
    var host: String
    /// 全页唯一的 CSS 选择器，由页面里的选择器生成库反推得到。
    var selector: String
    /// 给用户看的一句话描述，只用于「已隐藏」清单，不参与匹配。
    var label: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        host: String,
        selector: String,
        label: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.host = Self.normalizedHost(host)
        self.selector = selector
        self.label = label
        self.createdAt = createdAt
    }

    /// `www.example.com` 与 `example.com` 视为同一个站点，否则用户会觉得"刚隐藏过又回来了"。
    static func normalizedHost(_ rawHost: String?) -> String {
        guard var host = rawHost?.lowercased(), !host.isEmpty else {
            return ""
        }

        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }

        return host
    }

    func applies(toHost rawHost: String?) -> Bool {
        let normalized = Self.normalizedHost(rawHost)
        return !normalized.isEmpty && normalized == host
    }
}

/// 用户在某个网页应用里收藏的一页。
///
/// 列表按网页应用隔离：收藏存在该应用自己的偏好里，不会出现在别的网页应用窗口。
struct WebAppBookmark: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// 给用户看的标题，通常是收藏当时的页面标题。
    var title: String
    /// 已归一化的地址，用来判断当前页是不是已经收藏过。
    var urlString: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }

    var url: URL? {
        URL(string: urlString)
    }

    var displayHost: String {
        url?.host() ?? urlString
    }

    /// 只收普通网页。去掉锚点、去掉路径末尾多余斜杠，避免同一页被存两份。
    static func canonicalURLString(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.fragment = nil
        if let host = components.host {
            components.host = host.lowercased()
        }
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }

        let canonical = components.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return canonical.isEmpty ? nil : canonical
    }

    func matches(_ url: URL) -> Bool {
        guard let canonical = Self.canonicalURLString(url) else {
            return false
        }

        return urlString == canonical
    }
}

struct StoredWebAppPreference: Codable, Equatable, Sendable {
    var pageZoom: Double = 0.8
    var isPinned: Bool = false
    var isMobileUA: Bool = false
    var windowFrame: CGRect?
    var windowPlacement: StoredWindowPlacement?
    /// 必须是可选的：老版本存下来的偏好里没有这个字段，写成非可选会让整份偏好解码失败、
    /// 用户的缩放/置顶/窗口位置一起丢掉。
    var hiddenElements: [HiddenElementRule]?
    /// 同样必须是可选的：老版本没有收藏字段。
    var bookmarks: [WebAppBookmark]?

    var resolvedHiddenElements: [HiddenElementRule] {
        hiddenElements ?? []
    }

    var resolvedBookmarks: [WebAppBookmark] {
        bookmarks ?? []
    }

    var resolvedWindowPlacement: StoredWindowPlacement? {
        if let windowPlacement {
            return windowPlacement
        }

        guard let windowFrame else {
            return nil
        }

        return StoredWindowPlacement(frame: windowFrame, display: nil)
    }
}

@MainActor
final class WebAppPreferencesStore {
    private enum Key {
        static let preferences = "NeatWebApp.Preferences"
    }

    /// 宿主和运行时是两个进程，标准 UserDefaults 各写各的。
    /// 窗口位置必须两边读同一份，否则占位框会对不齐真窗。
    private static let siblingBundleIDs = [
        "com.geraltgraham.NeatWebApp",
        "com.geraltgraham.NeatWebAppRuntime"
    ]

    private let userDefaults: UserDefaults
    private let sharedFileURL: URL?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(userDefaults: UserDefaults = .standard, rootDirectoryURL: URL? = nil) {
        self.userDefaults = userDefaults
        let usesSharedFile = userDefaults === UserDefaults.standard || rootDirectoryURL != nil
        if usesSharedFile {
            self.sharedFileURL = try? RuntimeSupportDirectory.directoryURL(
                named: "Preferences",
                rootDirectoryURL: rootDirectoryURL
            ).appending(path: "web-apps.json")
        } else {
            self.sharedFileURL = nil
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(for appID: String) -> StoredWebAppPreference {
        storage[appID] ?? StoredWebAppPreference()
    }

    func save(_ preference: StoredWebAppPreference, for appID: String) {
        var nextStorage = storage
        nextStorage[appID] = preference
        persist(nextStorage)
    }

    private var storage: [String: StoredWebAppPreference] {
        if let shared = loadSharedFile(), !shared.isEmpty {
            return shared
        }

        let merged = mergedDefaultsStorage()
        if sharedFileURL != nil, !merged.isEmpty {
            persist(merged)
        }
        return merged
    }

    private func persist(_ value: [String: StoredWebAppPreference]) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        userDefaults.set(data, forKey: Key.preferences)
        if let sharedFileURL {
            try? data.write(to: sharedFileURL, options: .atomic)
        }
    }

    private func loadSharedFile() -> [String: StoredWebAppPreference]? {
        guard let sharedFileURL,
              let data = try? Data(contentsOf: sharedFileURL) else {
            return nil
        }

        return try? decoder.decode([String: StoredWebAppPreference].self, from: data)
    }

    private func mergedDefaultsStorage() -> [String: StoredWebAppPreference] {
        var merged: [String: StoredWebAppPreference] = [:]
        if sharedFileURL != nil {
            for bundleID in Self.siblingBundleIDs {
                guard let domain = UserDefaults.standard.persistentDomain(forName: bundleID),
                      let data = domain[Key.preferences] as? Data,
                      let decoded = try? decoder.decode([String: StoredWebAppPreference].self, from: data) else {
                    continue
                }

                merged.merge(decoded) { current, new in
                    new.resolvedWindowPlacement != nil ? new : current
                }
            }
        }

        if let data = userDefaults.data(forKey: Key.preferences),
           let decoded = try? decoder.decode([String: StoredWebAppPreference].self, from: data) {
            merged.merge(decoded) { current, new in
                new.resolvedWindowPlacement != nil ? new : current
            }
        }

        return merged
    }
}
