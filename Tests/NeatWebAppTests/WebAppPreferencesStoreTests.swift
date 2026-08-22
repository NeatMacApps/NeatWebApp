import CoreGraphics
import Foundation
import XCTest
@testable import NeatWebApp

@MainActor
final class WebAppPreferencesStoreTests: XCTestCase {
    func testHostAndRuntimeReadTheSameSavedWindowFrame() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppPreferenceShare-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let hostDefaults = UserDefaults(suiteName: "NeatWebAppPreferenceHost-\(UUID().uuidString)")!
        let runtimeDefaults = UserDefaults(suiteName: "NeatWebAppPreferenceRuntime-\(UUID().uuidString)")!
        let hostStore = WebAppPreferencesStore(
            userDefaults: hostDefaults,
            rootDirectoryURL: tempRoot
        )
        let runtimeStore = WebAppPreferencesStore(
            userDefaults: runtimeDefaults,
            rootDirectoryURL: tempRoot
        )
        let frame = CGRect(x: 120, y: 80, width: 649, height: 751)
        hostStore.save(
            StoredWebAppPreference(
                windowFrame: frame,
                windowPlacement: StoredWindowPlacement(frame: frame, display: nil)
            ),
            for: "gemini"
        )

        XCTAssertEqual(runtimeStore.load(for: "gemini").resolvedWindowPlacement?.frame, frame)
    }

    func testBookmarksStayIsolatedBetweenWebApps() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppBookmarkIsolation-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let defaults = UserDefaults(suiteName: "NeatWebAppBookmarkIsolation-\(UUID().uuidString)")!
        let store = WebAppPreferencesStore(
            userDefaults: defaults,
            rootDirectoryURL: tempRoot
        )
        var claude = StoredWebAppPreference()
        claude.bookmarks = [
            WebAppBookmark(title: "对话", urlString: "https://claude.ai/chat/1")
        ]
        var notion = StoredWebAppPreference()
        notion.bookmarks = [
            WebAppBookmark(title: "笔记", urlString: "https://www.notion.so/page")
        ]

        store.save(claude, for: "claude")
        store.save(notion, for: "notion")

        XCTAssertEqual(store.load(for: "claude").resolvedBookmarks.map(\.urlString), [
            "https://claude.ai/chat/1"
        ])
        XCTAssertEqual(store.load(for: "notion").resolvedBookmarks.map(\.urlString), [
            "https://www.notion.so/page"
        ])
        XCTAssertTrue(store.load(for: "github").resolvedBookmarks.isEmpty)
    }
}
