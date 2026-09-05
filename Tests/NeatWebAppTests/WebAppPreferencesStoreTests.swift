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

    func testSavingOneAppDoesNotClobberSiblingPreferenceWrittenEarlier() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppPreferenceMerge-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let hostDefaults = UserDefaults(suiteName: "NeatWebAppPreferenceMergeHost-\(UUID().uuidString)")!
        let runtimeDefaults = UserDefaults(suiteName: "NeatWebAppPreferenceMergeRuntime-\(UUID().uuidString)")!
        let hostStore = WebAppPreferencesStore(
            userDefaults: hostDefaults,
            rootDirectoryURL: tempRoot
        )
        let runtimeStore = WebAppPreferencesStore(
            userDefaults: runtimeDefaults,
            rootDirectoryURL: tempRoot
        )

        var hostPreference = StoredWebAppPreference()
        hostPreference.pageZoom = 1.2
        hostPreference.windowFrame = CGRect(x: 10, y: 20, width: 800, height: 600)
        hostStore.save(hostPreference, for: "claude")

        var runtimePreference = StoredWebAppPreference()
        runtimePreference.pageZoom = 0.9
        runtimePreference.bookmarks = [
            WebAppBookmark(title: "对话", urlString: "https://claude.ai/chat/1")
        ]
        runtimeStore.save(runtimePreference, for: "notion")

        XCTAssertEqual(hostStore.load(for: "claude").pageZoom, 1.2, accuracy: 0.001)
        XCTAssertEqual(
            hostStore.load(for: "claude").resolvedWindowPlacement?.frame,
            CGRect(x: 10, y: 20, width: 800, height: 600)
        )
        XCTAssertEqual(runtimeStore.load(for: "notion").pageZoom, 0.9, accuracy: 0.001)
        XCTAssertEqual(runtimeStore.load(for: "notion").resolvedBookmarks.map(\.urlString), [
            "https://claude.ai/chat/1"
        ])
    }
}
