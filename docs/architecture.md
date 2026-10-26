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
- the floating activity Dock, its initial placement presets, and two-axis position persistence
- the custom web app catalog（包括已配置 URL 的编辑）
- favicon caching
- runtime discovery, launch, takeover, and command dispatch

### `NeatWebAppRuntime`

The helper app owns:

- a single web app runtime identified by `WebAppDefinition.id`
- `WKWebView` and browser session state
- the browser window lifecycle and collapse-state publication
- host-lifecycle supervision (implemented 2026-09-21, unit-tested, installed-app acceptance pending): a normally quitting host asks runtimes to terminate cooperatively, while an unexpectedly terminated host is detected by the runtime through a captured host application identity before the runtime performs its own registry/lock cleanup and exits
- runtime event publication back to the host

### `Sources/Shared`

Shared code contains:

- runtime bootstrap and state models
- distributed notification names and payload helpers
- runtime support-directory helpers and lock management
- window placement utilities used by both targets

## Launch Flow

### Xcode 27 diagnostic corrections

Window launch-isolation mutations run on the main actor. Side Dock animation completion returns to the main actor before touching its panel. Updating a runtime definition reports bootstrap persistence failures through host diagnostics or the runtime system log; the active definition still applies and the runtime command still proceeds.

The actor-isolated favicon-store test fixture uses XCTest's asynchronous setup/teardown overrides so its temporary-directory state stays on the main actor. The full-test command in `AGENTS.md` continues to cover this fixture. Apple specifies this isolation route in [Set Up and Tear Down State in Your Tests](https://developer.apple.com/documentation/xctest/set-up-and-tear-down-state-in-your-tests).

The host's AppIntents metadata tool emits `Metadata extraction skipped, no AppIntents.framework dependency found` under Xcode 27.2. Neither application declares App Intents, so there is no metadata to extract and no affected user action. Keep the tool diagnostic visible; reassess it when adding an App Intent rather than adding a dependency or disabling extraction just to remove the warning.

The macOS 27 test runner also emitted WebContent shutdown diagnostics after all 165 tests
passed: missing private preference files, sandbox-denied pasteboard/Launch Services/audio
connections, missing tracking-query data, and a RunningBoard assertion for an already-ended
WebContent PID. These originate in WebKit processes, not compiler/static-analysis warnings.
The installed Dock path did not exercise these APIs. No private entitlement or log suppression
was added. Their exact SDK cause is unconfirmed; investigate with a focused WebKit harness if
pasteboard, audio, or process lifecycle failures occur in the installed app.

Product rulings, overturned approaches, and acceptance for the covering lid: [launch-cover.md](design/launch-cover.md).

1. `AppModel` starts, loads the app catalog, restores cached favicons, refreshes screen state, and refreshes the runtime registry.
2. When the user opens a web app, `WebAppRuntimeCoordinator` checks whether a runtime for that `appID` is already available.
3. If this is a **new** process launch (not expanding or focusing an already-running runtime), the host resolves the window frame **once**, immediately shows a placeholder at that exact frame, and writes the same frame into the runtime bootstrap. This covers the wait while Launch Services starts `NeatWebAppRuntime`.
4. The host writes a bootstrap payload. For a user open it hands the bootstrap to the pre-warmed standby runtime when one is ready (see [warm-standby-runtime.md](design/warm-standby-runtime.md)); otherwise, and for health restarts, `RuntimeLauncher` launches a new `NeatWebAppRuntime`.
5. The runtime reads its bootstrap, creates `BrowserSession`, applies the host-provided frame as-is (it must not re-resolve placement, nudge the window, or let SwiftUI / window restoration change the frame on first show), and publishes runtime state. A frame that fills the usable desktop is treated as a zoom artifact, not the user's size.
6. The runtime keeps the covering lid in place until the real window has painted its first frame. Only then does it report itself visible; the host lifts the lid with no fade and no scale. Collapse, hide, crash, or launch failure also lifts it immediately. Already-running windows never go through this cover.
7. The host observes runtime changes to update launcher state, diagnostics, and helper takeover behavior.

Placeholder windows live in the host process only as a **covering lid** while Launch Services starts the helper: same outer frame and window style, white content, no second chrome, no transition animation, no own shadow (the real window’s shadow is the only one). The runtime window disables AppKit’s default appear zoom, sits at that exact frame underneath, and does **not** tell the host it is visible until the webpage has painted a frame. The host then orders the lid out. They must not look like two different screens swapping. The host is a menu-bar extra, so the cover must bring the app forward or it appears behind other apps and looks like a missed click. The lid sits on a higher window layer so it is not treated as covering the real window for auto-collapse. Background health restarts do not show a cover.

Host and runtime are separate processes with separate preference domains. Window size and position therefore live in a shared Application Support file both processes read, and the host still passes the exact frame in the bootstrap so the first appearance cannot drift even if the two processes would otherwise pick different screens.

## Application switching

Owner correction (2026-10-24): each running web app may appear in the system Dock
and Command-Tab, but its icon must be the website's own favicon, not the generic
NeatWebApp icon. This supersedes the earlier single-host-entry implementation.
The host remains an accessory menu-bar app; only helpers assigned to real web apps
become regular applications. Warm standby helpers stay hidden until adoption.

A runtime uses native `NSApplication.setActivationPolicy(.regular)` and
`applicationIconImage`, loading the existing per-web-app favicon cache and updating
it when the website icon becomes available. Owner correction (2026-10-24): all
system Dock icons use one Apple-style continuous rounded-rectangle silhouette,
with consistent scale and margins, preserving each website's mark and colors.
Do not reuse the launcher's circular crop as the source for new Dock icons.
The host retains an uncropped favicon alongside the existing launcher cache;
older circular cache entries are an offline fallback until the normal refresh.
Render the temporary Dock image with SwiftUI's public continuous `RoundedRectangle`
path and a neutral opaque backing for transparent site marks. This is runtime
website-image presentation, not a redesign/replacement of the product's AppIcon
or a claim that arbitrary website images are layered Icon Composer assets.
Assign `applicationIconImage` after promoting the helper to `.regular`: installed
macOS 27.2 acceptance showed that the promotion recreated the tile with the generic
bundle icon when the website image was assigned only beforehand. A post-promotion
assignment changed the actual native Dock tile; tests retain this ordering.
Do not redraw website branding or copy the host icon into each running tile. The native app switcher and Dock remain
system-owned; no custom switcher or global shortcut interception is needed.
A runtime keeps its entry while its window is collapsed or hidden. Selecting that
entry restores the same window/page/session on the current Space through the
existing `showAndFocus` path. Its own `applicationDidBecomeActive` and reopen
callbacks handle restoration; internal activation during launch or expansion must
not restart presentation or reveal the launch cover early. Ending that runtime
removes its entry. The existing 80% auto-collapse rule and manual collapse remain.

The host passes the last real external application's identity (PID, launch date and
bundle identifier) during launch/focus handoff. The runtime validates it before
retaining a collapse return target and never chooses the host itself as that target.
The management `Settings` scene explicitly suppresses launch and restoration;
application switching never opens settings. Its explicit menu/Command-comma path
and the host's existing Finder/Spotlight recovery behavior remain available.

References inspected: the existing `WebAppWindowController.showAndFocus`, runtime
App delegate, per-app `WebAppFaviconStore`, MacKit's `AccessoryActivationSession`,
and [Helm's activation-policy implementation](https://www.polpiella.dev/keep-menu-bar-running-after-quitting-app).
Reuse their applicable native policy/focus behavior and cached website images;
do not use MacKit's temporary session, which activates immediately and hides an
entry when a window closes. Official contracts:
[activation policy](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum),
[application icon](https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage),
[activation callback](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdidbecomeactive(_:)).
The installed Xcode 27.2 SDK declares these public AppKit APIs; the product remains
macOS 15+. Icon/name behavior across multiple instances requires installed native
Dock/Command-Tab acceptance, not just a running-process policy readback.

## Runtime Window Lifecycle

The 2026-09-21 implementation passes the host process identifier only as a launch-time supervision hint. The runtime resolves that identifier to an `NSRunningApplication` object before starting its monitor, so a reused PID is not treated as the original host. The monitor is cancelled during normal runtime cleanup. Site data remains in the existing per-web-app WebKit data store; lifecycle cleanup removes only runtime registry/bootstrap/lock artifacts. Build plus full unit tests pass; installed-app acceptance (real Quit linkage, abnormal-termination drill) is still pending.

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

- `Sources/NeatWebApp/Services/AppModel.swift`（核心状态与 `startIfNeeded`；职责 extension：`AppModel+Launcher` / `+Favicon` / `+WebApps` / `+Preferences`）
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
- download progress and final status stay visible beside More Actions; a small native popover shows the current web app's transfers, byte counts and native progress bars, per-file Finder reveal and terminal-only clearing (presentation authority: [browser-top-chrome.md](design/browser-top-chrome.md#compact-downloads-owner-correction-2026-10-21))
- external URL schemes stay out of the web view; direct user clicks open the system app, while script-triggered external schemes require confirmation
- JavaScript alert, confirm, prompt, and `window.close()` are mapped to native window behavior
- browser-level keyboard shortcuts are resolved by `BrowserKeyCommand` and consumed in the web view's `performKeyEquivalent`

`NeatWebAppRuntime` starts as `LSUIElement`; an assigned web app then becomes a regular application with its website icon in the Dock/app switcher. Its SwiftUI menu supplies standard editing, Hide and Quit commands. Browser actions still belong to the web view's `performKeyEquivalent`, so focused page fields cannot swallow them:

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

The runtime's SwiftUI `App` still needs a `Scene` even though its only window is built by AppKit (`RuntimeWindowCoordinator`), so `NeatWebAppRuntimeApp` declares `Settings { EmptyView() }` purely as a placeholder. That placeholder implicitly binds `Command ,` to a blank Settings window, so it strips the binding back out with an empty `CommandGroup(replacing: .appSettings)`. The runtime must never grow a real Settings UI: preferences live in the host's main window, where `Command ,` intentionally opens that window instead.

The host app intentionally does not receive browser media entitlements. Only `NeatWebAppRuntime` owns camera and microphone capability because it is the process that hosts webpage content.

Both the host and runtime Info.plist files keep camera and microphone usage descriptions. This is required because macOS privacy attribution for embedded helper apps can still validate the containing app's usage-description keys even though the actual media entitlement remains runtime-only.

## Notch And Launcher Behavior

- `ScreenNotchGeometry` derives notch, activation, and retention rectangles from public `NSScreen` geometry APIs.
- `NotchActivationMonitor` combines local and global mouse monitors so reveal behavior still works when the pointer moves over other apps.
- `LauncherOverlayController` presents a non-activating panel for the launcher UI.
- Launcher edge fades are driven by actual scroll headroom so the visual affordance always matches the remaining hidden content.

## Activity Dock

- Collapsed WebApps share one host-owned floating clear-glass capsule. Left/right presets
  use a vertical layout; the bottom preset uses a horizontal layout. Presets set the initial
  placement, while subsequent dragging is free in both axes and between displays.
- The existing native `NSPanel` forwards a mouse-down to `NSWindow.performDrag(with:)`
  immediately on the grip, or after eight points of motion on app icons. Window Server owns
  tracking, Space switching and movement;
  short clicks still open apps. A completed drag suppresses the trailing click. Dragging
  never quits a runtime; the app icon's native context menu exposes Quit instead.
- The panel contains app icons and a persistent two-column dotted drag grip, with no
  collapse/expand controls or compact state. The grip remains outside the icon scroll view.
  It stays nonactivating and uses its existing level and all-Spaces behavior.
- Release clamps the panel to `NSScreen.visibleFrame` with twelve points of clearance,
  then saves normalized x/y coordinates and the display. Display fallback is the current
  panel screen or the first display, never `NSScreen.main`. Display changes resolve fresh
  geometry and recover the saved position inside a usable screen.
- Browser windows and the launch cover use the full system `visibleFrame`. The host
  clears the legacy edge reserve, so moving or growing the floating Dock cannot resize
  unrelated browser windows. The former attachment and inward-to-quit rules are
  superseded by [the floating Dock decision](design/window-auto-collapse.md).
- Glass, fallback fill and pointer hit geometry share the native `Capsule` shape.
  System focus rings are disabled. The Dock never takes keyboard focus.

## Website icon loading

Website icons must recover without restarting the host. A letter is only a temporary
fallback, not evidence that a site has no icon. AI Studio's public welcome page, for
example, advertises 32/64/96/512-pixel PNGs on `www.gstatic.com`; a local probe fetched
and decoded its 512-pixel source while the installed catalog had no cached image.
The original incident's transient request/pressure state was not logged and remains
unknown; both the session-long failed-ID blacklist and the shared prefetch pause
prevented recovery in the old implementation.

The host separates three responsibilities:

- `WebAppFaviconLoader` discovers/ranks HTML, manifest and origin candidates. It
  skips unsuccessful or undecodable candidates, respects cancellation between
  requests, and uses native `URLSession` connectivity waiting with a 20-second
  resource timeout. No reachability preflight, third-party favicon proxy or
  site-specific exception is needed. Before thumbnailing index zero, the shared
  decoder checks that the image source actually contains an image; malformed
  candidates must not be treated as a valid image container. See Apple's
  [image-count contract](https://developer.apple.com/documentation/imageio/cgimagesourcegetcount(_:)).
- `WebAppFaviconLoadCoordinator` owns per-app request identity, demand priority,
  deduplication, a two-load concurrency limit and retry scheduling. Demand comes
  from adding/opening an app or showing its icon. Failed demand loads retry after
  2, 10 and 60 seconds, then at most once every five minutes until successful or
  invalidated. Repeated view appearances cannot reset backoff. Startup refreshes
  are lower-priority, single-attempt prefetches. A demand request promotes an
  existing prefetch, including its recovery policy.
- The existing store, downsampling, normalization and cache-generation notification
  continue to own images and presentation. Failed refreshes never replace a good
  image with a letter. URL edits/deletion cancel and invalidate outstanding work;
  late completions must not repopulate a deleted or changed app's cache.

Memory pressure cancels/pauses only speculative prefetch and purges reconstructible
memory images. It never blocks requested icons or their bounded recovery. Do not
restore the old process-lifetime blacklist or make all icon requests depend on the
prefetch flag. Host activation rechecks due work without bypassing backoff; normal
termination cancels all scheduled work. No new settings, controls or icon artwork.

Reference inspected: [SDWebImageManager's cancellation/cache handling](https://github.com/SDWebImage/SDWebImage/blob/master/SDWebImage/Core/SDWebImageManager.m).
Reuse the separation of cancellation from failure and preservation of cached images,
not its optional failed-URL blacklist or dependency stack. The repository's existing
loader/store/normalizer are retained rather than replaced with a second image library.
Apple's [connectivity waiting contract](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity)
applies only to establishing connections; application backoff still handles failed
or dropped requests. The installed Xcode 27.2 Foundation SDK exposes that public API
from macOS 10.13, below this product's macOS 15 minimum.

Acceptance: deterministic coordinator tests cover transient recovery, capped backoff,
deduplication, concurrency/priority, pressure, promotion and stale completions;
URLProtocol fixtures cover real candidate parsing, bad image fallback and cancellation.
The installed signed Release must populate AI Studio's cache and display its real
website mark in the existing launcher/activity Dock. Build/test success alone is not
that visual evidence.

Verification (2026-10-26, Xcode 27.2 / macOS 27.2): 111 host + 109 runtime
Debug tests passed on arm64, including 17 new icon regressions. Clean universal
Debug and Release builds and static analysis passed for both host and runtime
(arm64 + x86_64). Complete diagnostics/result bundles are retained locally under
`build/favicon-recovery/`; both universal executables were confirmed with `lipo`.
No source/compiler/analyzer warning was found. The only build-tool warning was
AppIntents metadata extraction being skipped, separately emitted for the host,
runtime and test bundles: none declares App Intents, so no metadata-dependent
feature is lost. Keep it visible and reassess if an App Intent is introduced.
The first malformed-image fixture exposed an image source with zero images; the
index-count precondition above fixed the thumbnail diagnostic and the final full
run retained the failing input as a passing regression. WebKit sandbox/pasteboard
shutdown messages in the first run match the existing assessment under Launch
Flow; the final run did not emit them. Tests were not executed on Intel or macOS 15.

## Persistence

- `CustomWebAppStore` 持久化用户管理的 app catalog，包括主窗口中对每个 app 的名称、URL 与底色编辑。
- 正在跑的网页应用被改名或改首页时，宿主通过 `reloadDefinition` 把新定义推给对应运行时，并改写磁盘上的 bootstrap；只改名不打断当前页，首页变了才重新打开首页。健康重启必须读到更新后的 bootstrap，不能回到旧首页。
- `WebAppPreferencesStore` persists zoom, pinned state, saved window placement, hidden-element rules, and **per-web-app bookmarks**. Each web app's bookmark list is stored under that app's own preference record and never mixed with another app. 宿主与多个运行时共用同一份 `web-apps.json`：保存时在文件协调锁里重读，只替换当前网页应用这一条，禁止整份覆盖把别的应用刚写入的缩放/收藏/窗口框盖掉。
- `AppPreferencesStore` persists Dock presets, optional normalized floating x/y coordinates, and target display. Missing floating keys use the prior edge-only position without overwriting it during loading.
- The legacy shared `side-dock-reserve.json` is cleared by the host so older saved edge reservations no longer constrain browser windows. The compatibility reader remains available to older runtimes.
- `WebAppFaviconStore` persists site icons and is shared by the host and runtime targets.
- `RuntimeRegistryStore` tracks active runtime bootstrap/state files and cleans stale entries.
- 站点 Cookie / 本地存储按网页应用隔离：运行时使用 `WKWebsiteDataStore(forIdentifier:)`，标识由应用 ID 稳定派生，不是共享的 `default()`。

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

<!-- 该文档整理/压缩于 2026-09-05 -->
