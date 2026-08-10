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

struct StoredWebAppPreference: Codable, Equatable, Sendable {
    var pageZoom: Double = 0.8
    var isPinned: Bool = false
    var isMobileUA: Bool = false
    var windowFrame: CGRect?
    var windowPlacement: StoredWindowPlacement?
    /// 必须是可选的：老版本存下来的偏好里没有这个字段，写成非可选会让整份偏好解码失败、
    /// 用户的缩放/置顶/窗口位置一起丢掉。
    var hiddenElements: [HiddenElementRule]?

    var resolvedHiddenElements: [HiddenElementRule] {
        hiddenElements ?? []
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

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
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
        guard let data = userDefaults.data(forKey: Key.preferences) else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: StoredWebAppPreference].self, from: data)) ?? [:]
    }

    private func persist(_ value: [String: StoredWebAppPreference]) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        userDefaults.set(data, forKey: Key.preferences)
    }
}
