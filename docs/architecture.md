# Architecture

This document describes the current structure of NeatWebApp after the host/runtime split landed.

## Goals

- Keep browser content front and center instead of wrapping it in a heavyweight shell
- Use SwiftUI for application UI and AppKit only for macOS-specific window and screen behavior
- Isolate each web app window in its own helper process so one runtime does not disturb another
- Preserve persistent browsing state through the system WebKit data store

## Process Model

### `NeatWebApp`

The host app owns:

- the main window, which also hosts every app-level setting (there is no separate Settings window)
- the menu bar entry and commands
- launcher presentation and notch activation monitoring
- the side notch Dock, its left/right setting, and edge position persistence
- the custom web app catalog（包括已配置 URL 的编辑）
- favicon caching
- runtime discovery, launch, takeover, and command dispatch

### `NeatWebAppRuntime`

The helper app owns:

- a single web app runtime identified by `WebAppDefinition.id`
- `WKWebView` and browser session state
- the browser window lifecycle and collapse-state publication
- runtime event publication back to the host

### `Sources/Shared`

Shared code contains:

- runtime bootstrap and state models
- distributed notification names and payload helpers
- runtime support-directory helpers and lock management
- window placement utilities used by both targets

## Launch Flow

Product rulings, overturned approaches, and acceptance for the covering lid: [launch-cover.md](design/launch-cover.md).

1. `AppModel` starts, loads the app catalog, restores cached favicons, refreshes screen state, and refreshes the runtime registry.
2. When the user opens a web app, `WebAppRuntimeCoordinator` checks whether a runtime for that `appID` is already available.
3. If this is a **new** process launch (not expanding or focusing an already-running runtime), the host resolves the window frame **once**, immediately shows a placeholder at that exact frame, and writes the same frame into the runtime bootstrap. This covers the wait while Launch Services starts `NeatWebAppRuntime`.
4. `RuntimeLauncher` writes a bootstrap payload and launches `NeatWebAppRuntime`.
5. The runtime reads its bootstrap, creates `BrowserSession`, applies the host-provided frame as-is (it must not re-resolve placement, nudge the window, or let SwiftUI / window restoration change the frame on first show), and publishes runtime state. A frame that fills the usable desktop is treated as a zoom artifact, not the user's size.
6. The runtime keeps the covering lid in place until the real window has painted its first frame. Only then does it report itself visible; the host lifts the lid with no fade and no scale. Collapse, hide, crash, or launch failure also lifts it immediately. Already-running windows never go through this cover.
7. The host observes runtime changes to update launcher state, diagnostics, and helper takeover behavior.

Placeholder windows live in the host process only as a **covering lid** while Launch Services starts the helper: same outer frame and window style, white content, no second chrome, no transition animation, no own shadow (the real window’s shadow is the only one). The runtime window disables AppKit’s default appear zoom, sits at that exact frame underneath, and does **not** tell the host it is visible until the webpage has painted a frame. The host then orders the lid out. They must not look like two different screens swapping. The host is a menu-bar extra, so the cover must bring the app forward or it appears behind other apps and looks like a missed click. The lid sits on a higher window layer so it is not treated as covering the real window for auto-collapse. Background health restarts do not show a cover.

Host and runtime are separate processes with separate preference domains. Window size and position therefore live in a shared Application Support file both processes read, and the host still passes the exact frame in the bootstrap so the first appearance cannot drift even if the two processes would otherwise pick different screens.

## Runtime Window Lifecycle

- The top chrome band's `×` button and `Command W` collapse the browser into the side notch. The old separate circle collapse button has been removed.
- Ending a WebApp is a deliberate side-notch gesture: drag its icon toward the screen center past the close threshold and release. The host then asks that runtime to terminate; it removes its state/bootstrap files and exits.
- Hiding and side-notch collapse remain window-lifecycle actions. They keep the runtime process alive so the host can show, focus, expand, or recover the same web app without launching a replacement.
- Each runtime process owns exactly one browser window. There is no way to spawn extra windows for the same web app.
- Invisibility is the only auto-collapse trigger. Once at least 80% of the browser window is actually hidden (covered by opaque same-layer windows, off-screen, or not on the active Space), the runtime collapses immediately and the host places that WebApp in the shared side Dock. System overlays such as Mission Control are ignored, so there is no debounce delay. There is deliberately no idle/unfocused timeout: a window the user can still see stays open no matter how long it goes untouched.
- macOS's own `occlusionState` only reports "any pixel visible" versus "fully covered", which is too coarse here. Hidden area is computed from the on-screen window list by subtracting overlapping same-layer opaque frames (and any portion outside all displays). A window missing from the current Space's list counts as fully hidden. Being covered, sitting on an inactive Space, and another app going full-screen all still count. Only two cases are excluded, in `WebAppWindowController.shouldCollapseWindowWhenOccluded`: miniaturized to the Dock (the user put it there) and a window that is not on screen at all (already collapsed or hidden — collapsing again would be a no-op that fires spurious runtime events).
- Collapse is immediate. Mission Control and similar system overlays sit on a higher window layer and are skipped, which replaces the old 2-second debounce. Eligibility is still re-checked at the moment of collapse instead of trusting an earlier snapshot.
- A user-initiated show (launcher, side Dock, or focus command) suppresses auto-collapse briefly so a window that just came on screen is not treated as fully hidden while the on-screen window list is still catching up. After that grace, the 80% rule applies again. This is not the old occlusion delay. The covering lid sits on a higher window layer and is only lifted after the first painted frame (or on failure / timeout), so it must not be treated as same-layer occlusion that collapses the real window.
- Because the side Dock joins every Space, the browser window carries `.moveToActiveSpace`. Without it, opening an item from another Space would drag the user back to the Space the window was left on instead of bringing the window to them.
- Pinned windows never auto-collapse.

## Main Components

### App

- `Sources/NeatWebApp/App/NeatWebAppApp.swift`
- `Sources/NeatWebApp/App/AppCommands.swift`
- `Sources/NeatWebAppRuntime/App/NeatWebAppRuntimeApp.swift`

### Models

- `Sources/NeatWebApp/Models/WebAppDefinition.swift`
- `Sources/NeatWebApp/Models/ScreenNotchGeometry.swift`
- `Sources/NeatWebApp/Models/LauncherPresentationContext.swift`
- `Sources/NeatWebApp/Models/SideDockPresentationContext.swift`

### Host Services

- `Sources/NeatWebApp/Services/AppModel.swift`
- `Sources/NeatWebApp/Services/NotchActivationMonitor.swift`
- `Sources/NeatWebApp/Services/LauncherOverlayController.swift`
- `Sources/NeatWebApp/Services/SideDockOverlayController.swift`
- `Sources/NeatWebApp/Services/AppPreferencesStore.swift`
- `Sources/NeatWebApp/Services/WebAppRuntimeCoordinator.swift`
- `Sources/NeatWebApp/Services/RuntimeLauncher.swift`
- `Sources/NeatWebApp/Services/LaunchPlaceholderController.swift`
- `Sources/NeatWebApp/Services/WebAppPreferencesStore.swift`
- `Sources/NeatWebApp/Services/WebAppFaviconStore.swift`

### Runtime Services

- `Sources/NeatWebAppRuntime/Services/RuntimeAppModel.swift`
- `Sources/NeatWebAppRuntime/Services/RuntimeWindowCoordinator.swift`
- `Sources/NeatWebAppRuntime/Services/RuntimeCommandListener.swift`
- `Sources/NeatWebAppRuntime/Services/RuntimeEventPublisher.swift`

### Browser Runtime

- `Sources/NeatWebApp/Features/Browser/BrowserSession.swift`
- `Sources/NeatWebApp/Features/Browser/AppKitBridge/BrowserWebView.swift`
- `Sources/NeatWebApp/Features/Browser/BrowserContainerView.swift`
- `Sources/NeatWebApp/Services/WebAppWindowController.swift`
- `Sources/NeatWebApp/Services/WebAppFloatingIconSupport.swift`

The browser bridge owns daily browser capabilities that WebKit does not enable by default in an embedded `WKWebView`:

- camera and microphone requests are passed through to the system/WebKit prompt from the runtime process
- file upload uses the native macOS file picker
- downloads are saved to the user's Downloads folder with sanitized filenames and collision-safe suffixes
- download progress and final status are surfaced in the browser top chrome band, and completed downloads can be revealed in Finder
- external URL schemes stay out of the web view; direct user clicks open the system app, while script-triggered external schemes require confirmation
- JavaScript alert, confirm, prompt, and `window.close()` are mapped to native window behavior
- browser-level keyboard shortcuts are resolved by `BrowserKeyCommand` and consumed in the web view's `performKeyEquivalent`

`NeatWebAppRuntime` is `LSUIElement`, so it never shows a menu bar and only inherits the standard menu suite SwiftUI creates implicitly (Cut/Copy/Paste/Select All/Undo, Hide, Quit). Those keep working through that hidden menu, but no browser action has a menu item to hang a key equivalent on, so the web view owns them:

| Shortcut | Action |
| --- | --- |
| `Command =` / `Command +` / `Command -` / `Command 0` | zoom in, zoom out, actual size |
| `Command R` / `Command Shift R` | reload, reload ignoring cache |
| `Command [` / `Command ]` | back, forward |
| `Command Shift H` | return to the configured home URL |
| `Command P` | print the current page |
| `Command W` | collapse into the side notch (same action as the top chrome band's `×`) |
| `Command D` | bookmark or unbookmark the current page for this web app only |

Two deliberate exclusions: `Command ←`/`Command →` stay with the page because they mean "start/end of line" inside a web text field, and `Command H` stays the system hide command, so home is only reachable with Shift. Interception has to happen in `performKeyEquivalent` rather than `keyDown` — a focused web input would otherwise swallow the key first.

The host app intentionally does not receive browser media entitlements. Only `NeatWebAppRuntime` owns camera and microphone capability because it is the process that hosts webpage content.

Both the host and runtime Info.plist files keep camera and microphone usage descriptions. This is required because macOS privacy attribution for embedded helper apps can still validate the containing app's usage-description keys even though the actual media entitlement remains runtime-only.

## Notch And Launcher Behavior

- `ScreenNotchGeometry` derives notch, activation, and retention rectangles from public `NSScreen` geometry APIs.
- `NotchActivationMonitor` combines local and global mouse monitors so reveal behavior still works when the pointer moves over other apps.
- `LauncherOverlayController` presents a non-activating panel for the launcher UI.
- Launcher edge fades are driven by actual scroll headroom so the visual affordance always matches the remaining hidden content.

## Side Notch Dock

- Collapsed WebApps are collected into one host-owned vertical Dock instead of creating independent floating circles in each runtime.
- The collapsed WebApps live directly inside a compact, pure-black side notch. It stays one stable piece attached to the edge; there is no hover drawer, second-stage expansion, or dedicated drag handle. Its black fill, restrained white stroke, and corner language match the top-notch launcher.
- Dragging anywhere on the notch, including directly over an icon, moves it along the attached edge and can transfer it between displays. Dragging past a usable corner wraps to the adjacent edge (left/right ↔ bottom; the top edge is not used). A short click still opens the WebApp, while a completed drag suppresses the click. Position along the current edge is stored as a normalized value so it remains valid when resolution or available screen area changes.
- Settings offers explicit left, right, and bottom placement. On first use, the default side avoids the larger system-reserved inset; once chosen, the user's setting is authoritative. Dragging around a corner updates that same setting.
- Placement is computed from `NSScreen.visibleFrame`, not the physical display edge. A right-side Dock therefore sits immediately inside a right-side system Dock instead of covering it or stealing its reveal boundary. Screen geometry is refreshed after display configuration changes and must not be cached indefinitely.
- Web app windows must not cover this host-owned Dock. While the Dock is visible, window placement, resize, zoom, and the launch cover all use `visibleFrame` minus the Dock's full edge strip on that display. The Dock is inside `visibleFrame`, so treating the system desktop as the window's max frame would slide the window under the glass Dock. Rationale in [window-auto-collapse.md](design/window-auto-collapse.md).
- Only the visible black panel receives pointer events. No transparent full-height window is allowed along the edge because that would block other edge interactions.
- System focus rings are disabled on the Dock and Settings controls. Keyboard users receive the app's own restrained white focus treatment instead.

## Persistence

- `CustomWebAppStore` 持久化用户管理的 app catalog，包括主窗口中对每个 app 的名称、URL 与底色编辑。
- `WebAppPreferencesStore` persists zoom, pinned state, saved window placement, hidden-element rules, and **per-web-app bookmarks**. Each web app's bookmark list is stored under that app's own preference record and never mixed with another app.
- `AppPreferencesStore` persists the side Dock edge, normalized vertical position, and target display.
- Side-dock occupancy for window avoidance is a shared Application Support file both host and runtime read (`side-dock-reserve.json`). The host writes it whenever the Dock appears, moves, or hides.
- `WebAppFaviconStore` persists site icons and is shared by the host and runtime targets.
- `RuntimeRegistryStore` tracks active runtime bootstrap/state files and cleans stale entries.

## Testing

Tests are split by ownership:

- `Tests/NeatWebAppTests` covers host-side geometry, persistence, catalog-related behavior, and side-dock corner wrapping.
- `Tests/NeatWebAppRuntimeTests` covers runtime-side browser chrome, per-web-app bookmarks, legacy placement compatibility, auto-collapse eligibility, visible-area coverage math, and side-dock window avoidance.
- Auto-collapse eligibility is kept in a pure static function precisely so it stays testable without a live window; keep new window-lifecycle rules factored the same way.

## Design Constraints

- Memory footprint: UX-first rules (keep collapsed runtimes alive, borrow the system compressor, never unload pages under pressure) live in [design/memory-footprint.md](design/memory-footprint.md). Do not reintroduce unload-on-collapse or custom full-page heap compression.
- The project targets macOS 15, so it stays with `WKWebView` instead of newer WebKit APIs that require newer OS versions.
- AppKit bridges are intentionally narrow and only used where SwiftUI cannot fully express the required behavior.
- The host process must never own browser windows. It does own the shared side Dock because that is cross-runtime navigation UI; each runtime only owns its browser window and publishes lifecycle state.
- Browser-like capabilities belong in the runtime process. Keep file download, upload, media permission, and external scheme handling close to the `WKWebView` bridge instead of routing them through the host.
- One runtime process means one browser window. Multi-window / duplicate-window support for a single web app was removed deliberately and should not come back.
- Auto-collapse is driven by invisibility alone. Do not reintroduce an idle or unfocused timeout: a window the user can still see must never disappear on its own. Rationale in [docs/design/window-auto-collapse.md](design/window-auto-collapse.md).
