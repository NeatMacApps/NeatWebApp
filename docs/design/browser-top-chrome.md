# 浏览器顶栏：无界样式

记录 WebApp 浏览器窗口顶部控件区的产品决策与被否决的方案。代码位置见 `Sources/NeatWebApp/Features/Browser/BrowserContainerView.swift` 与 `BrowserChromeTheme.swift`。

## 当前规则

顶部是一条 40 点高的**让位带**，不是横条：

- 整条只铺网页自己的背景色（由页面 `theme-color` / 背景色推断），**不画底色横条、不画分割线**，所以看不出是一条独立的栏。
- 带内叠一层从上到下由浅入透明的**渐变**，给图标托底；页面是纯色时渐变几乎不可见，页面顶部是深色或大图时才显出层次。
- 图标**裸放**在带上；常驻入口按下文的渐进式菜单规则排列。没有胶囊底板、没有描边；圆形反馈只在悬停或已有动作选中时出现。
- 网页内容从让位带**下方**开始，网页自己的顶部导航永远不会被盖住。
- 让位带没有任何网页内容，整条都是窗口拖动区域，双击等同系统的窗口放大／还原。

图标前景色按页面明暗自动翻转（深色页面用近白色，浅色页面用近黑色），与渐变起始色一起构成对比度防御，不依赖任何系统材质。

## Cross-display window dragging

The pointer must keep the same grab point in the top band while crossing displays,
including a destination shorter than the window. Preserve the proposed frame when
it intersects any connected display; reserve off-screen recovery for a frame outside
every display. Explicit zoom and initial placement retain their existing fitting rules.

Inspected references: `WindowDragHandleView.mouseDown` in
`BrowserContainerView.swift` already passes the original mouse-down to the public
[`NSWindow.performDrag(with:)`](https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:)).
Keep this native interaction. `WebAppBrowserWindow.constrainFrameRect` currently calls
the superclass before checking display intersection. Apple's
[`constrainFrameRect(_:to:)`](https://developer.apple.com/documentation/appkit/nswindow/constrainframerect(_:to:))
may adjust the top edge and shrink a resizable window to the destination display.
Both APIs are present in the installed Xcode 27.2 SDK. Check the original proposed
frame before calling the superclass, rather than accepting an already altered frame.

Installed acceptance showed that this constraint change alone is insufficient on
macOS 27.2: AppKit's screen-layout adjustment separately calls the public
[`setFrame(_:display:)`](https://developer.apple.com/documentation/appkit/nswindow/setframe(_:display:))
with a remembered destination frame during native dragging. LLDB traced this call
through AppKit's screen adjustment and move-event handling, with launch-frame hold
already released. Ignore programmatic frame replacement only during the native
drag session; Window Server remains the sole owner of drag motion. Reuse the
20 ms pressed-button completion check inspected in
`SideDockOverlayController.beginNativeDragging`, because `performDrag` returns
immediately and may consume mouse-up. Clear the guard on release so normal resizing,
zoom and off-screen recovery continue to use the public frame API. No private API
or replacement mouse-tracking loop is used.

Baseline installed 0.3.30 evidence: dragging a 642 × 1247 window from the external
display to the lower built-in display changed the grab offset from (321, 18) to
(407, 132), with a simultaneous resize to 642 × 949. The actual held-drag context
capture showed the pointer in page content. Fixed-build acceptance must repeat that
path in both directions and inspect held-drag frames and returned geometry.

## Hover feedback

Owner decision (2026-10-13): hovering More Actions shows the same circular shading as the left controls, indicating that it is clickable. Leaving clears the shading. Reuse the inspected `BrowserChromeButton` treatment in `BrowserContainerView.swift`: `Circle`, `theme.highlightedFillColor`, SwiftUI `onHover`, and the existing 0.12-second ease-out animation with Reduce Motion respected. Keep the native `NSPopUpButton` and its menu interaction; do not replace it with a custom menu. This is transient feedback, not a persistent circle or focus frame. Public APIs: [onHover](https://developer.apple.com/documentation/swiftui/view/onhover(perform:)) and [NSPopUpButton](https://developer.apple.com/documentation/appkit/nspopupbutton).

## Progressive actions menu

Owner decision (2026-10-11): keep exactly three persistent controls on the left: close/collapse to the side Dock, pin, and bookmark the current page. Keep one vertical three-dot Kebab Menu control on the right. Clicking it directly opens the native AppKit `NSMenu`; set `NSMenuItem.image` explicitly so every action displays an icon followed by its label. Use a borderless `NSPopUpButton` in pull-down mode with no arrow. The installed Xcode 27.2 macOS SDK provides these APIs; see Apple's [NSPopUpButton](https://developer.apple.com/documentation/appkit/nspopupbutton) and [NSMenuItem.image](https://developer.apple.com/documentation/appkit/nsmenuitem/image).

Installed-app acceptance of the earlier SwiftUI `Menu` showed horizontal dots and text-only rows despite the label's rotation and `Label` content. Do not reuse that rendering path for this requirement. The installed system has no `ellipsis.vertical` SF Symbol; render the existing `ellipsis` symbol with a 90-degree transform into the native button's template image.

On macOS 27 and later, AppKit's automatic menu image visibility typically hides action images even when `NSMenuItem.image` is set. Every action must set [`preferredImageVisibility`](https://developer.apple.com/documentation/appkit/nsmenuitem/preferredimagevisibility) to `.visible` under a macOS 27 availability check. Earlier systems retain the normal explicit-image behavior. The requirement is a visible icon beside each label; accessibility descriptions and tooltips do not satisfy it. Acceptance must inspect the opened menu on the installed system.

Move Bookmarks, element hiding, reload and website identity switching into More Actions. Bookmarks uses the ribbon-shaped `bookmark` SF Symbol; the current-page action keeps `star` / `star.fill`. Selecting Bookmarks or element hiding opens the existing native popover anchored to More Actions. Each web app retains its own bookmark list and persistence boundary. Download status follows the separate compact presentation below.

Owner correction (2026-10-11): each menu row uses a short action label, with no more than two English words. The labels are `Bookmarks`, `Hide Element` / `Cancel Selection`, `Reload`, and `Mobile Site` / `Desktop Site`. Simplified Chinese uses `收藏夹`, `隐藏元素` / `取消选取`, `刷新`, and `移动版` / `桌面版`. Do not put behavior explanations such as "Return to Configured Address and Reload" in menu rows. Download labels obey the same limit, including `Dismiss Download` and a count followed by `Downloads`.

### Bookmark actions (owner decision, 2026-10-29)

Each bookmark row supports a native right-click context menu with Open, Rename,
Add WebApp and Delete. Rename edits only that bookmark's title, preserving its ID,
URL, creation date, order and web-app scope. Prefill the current title, reject
whitespace-only names, and support Return to save and Escape to cancel.

Add WebApp uses the bookmark's current title and complete saved URL without opening
the management window or requiring the user to re-enter either value. Copy a
one-time snapshot of the source runtime's HTTP cookies, including HttpOnly and
session cookies, into a fresh per-app persistent WebKit store before registering
that new app with the host catalog. Preserve cookie attributes; never serialize
cookie values into IPC, preferences or logs. New and source apps retain separate
store IDs and do not synchronize subsequent changes. This copies cookies, not
localStorage, IndexedDB, passkeys or a guarantee that every website stays signed in.

Only the host writes the catalog. Registration uses a correlated acknowledgement;
show pending, success and failure in the bookmark panel and prevent duplicate
submissions. A retry after a missing acknowledgement reuses the same destination
ID rather than making another app. The original bookmark and source cookies remain.

Inspected references: the existing `BrowserBookmarkListPanel` provides the anchored
popover, title/host rows and open/delete actions; the dashboard and Side Dock use
SwiftUI's native `contextMenu`. Apple's [RenameButton example](https://developer.apple.com/documentation/swiftui/renamebutton)
provides `renameAction` and native text-field focus; reuse that interaction rather
than a custom menu or editor. The installed Xcode 27.2 SDK provides these APIs for
macOS 15. Cookie transfer uses public [`WKHTTPCookieStore`](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
`allCookies()` and `setCookie`, awaiting each write. Do not use the newer bulk
`setCookies` API, which requires macOS 26.

Acceptance covers the opened right-click menu, rename save/cancel/blank input and
persistence, registration acknowledgements and retries, and a new app loading a
cookie-protected fixture URL with a distinct store. Check English/Chinese and long
names, plus source/destination independence. Build/test evidence does not substitute
for installed interaction and screenshots.

Verification (2026-10-29): a clean Debug build, 112 host tests and 115 runtime
tests, a universal (arm64/x86_64) Developer ID Release build and clean-derived-data
Debug static analysis passed on Xcode 27.2. Native WebKit tests read the copied
persistent/HttpOnly/secure and session cookies before registration, then deleted a
destination cookie and verified the source remained unchanged. Tests cover rename
identity/order/persistence, blank names, repeated submissions, missing acknowledgements,
same-ID retries without recopying, client shutdown and host request validation.
The existing AppIntents metadata diagnostic remains as assessed in
[architecture.md](../architecture.md); WebContent pasteboard/Launch Services/TCC
connection diagnostics occurred after successful test-host teardown, not as failed
product assertions. No diagnostic was suppressed.

Installed UI acceptance remains pending: the session is locked, capture access is
available, and the native display initially reports inactive/asleep. There is no
visible runtime window in the fresh window list. Right-click, editor focus,
Return/Escape, opened-menu appearance and English/Chinese/pseudolanguage layouts
are not established by the tests. A separate runtime actually loading a protected
URL using the copied cookies also remains unverified; the current cookie evidence
covers native stores in one runtime process, not every site's login behavior.

### Compact downloads (owner correction, 2026-10-21)

Restore the visible download status beside More Actions. The earlier download dot and
download rows inside the kebab menu are superseded. With no download records, More
Actions remains the only right-side control. With records, a compact status capsule
shows active progress, completion or failure and opens a small native popover anchored
to that capsule. This is an upper-right menu-sized presentation, never a separate
window, large modal or download-management page. Keep the close, pin and bookmark
controls unchanged.

The list shows filenames, native progress bars and percentages when a total is known,
and transferred bytes when supplied by WebKit. Unknown totals remain indeterminate;
do not invent percentages. Active downloads take precedence over a newer completed
record in the capsule. Each completed file can be revealed in Finder. Missing files
produce visible feedback. Finished records can be dismissed individually or cleared
as a batch without deleting files; active records cannot be dismissed. The capsule's
close action clears the finished batch, avoiding a sequence of old completion notices.
Keep records scoped to the current web app/runtime; no new persistent history or
pause/resume/cancellation feature is introduced. The popover has an explicit close
button and native Escape/outside dismissal.

Inspected implementation references: the pre-kebab `BrowserDownloadIndicator`
(`git show d24c80f^:Sources/NeatWebApp/Features/Browser/BrowserContainerView.swift`)
supplies the compact status location and Finder workflow; the current
`BrowserBookmarkListPanel` supplies the native anchored popover and restrained row
spacing. Reuse these patterns without the old focus outline. Apple's
[Safari download list](https://support.apple.com/en-gb/guide/safari/sfri40598/27.0/mac/27)
confirms the upper-right list/reveal/clear interaction; Safari's persistence and
pause/resume policies are not adopted. Public APIs checked against official
[popover](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)),
[ProgressView](https://developer.apple.com/documentation/swiftui/progressview) and
[WKDownload](https://developer.apple.com/documentation/webkit/wkdownload) documentation,
and present in the installed Xcode 27.2 SDK: SwiftUI `popover`, `ProgressView`,
`Button`, `ScrollView`, and `WKDownload.progress` via `NSProgressReporting`.
Keep the system popover appearance; use existing SF Symbols for interface actions.

Verification (2026-10-21): Debug build, 92 host tests, 101 runtime tests and clean
derived-data static analysis passed with Xcode 27.2 on arm64. Regression coverage
includes active-transfer priority, unknown totals, queued progress after completion
or failure, batch clearing without file deletion, and missing-file feedback. Only
the existing AppIntents metadata tool warning remains; its assessment is in
[architecture.md](../architecture.md). WebKit's XPC/pasteboard connection errors
occurred during test-host teardown after the runtime suite passed, with no failed
assertions; they do not establish installed pasteboard behavior.

Installed acceptance is limited by the locked session. Native probing confirmed
capture access, an initially inactive/asleep display, then active/awake output after
a bounded wake. A local fixture page automatically initiated an actual WebKit
download: Debug captures showed 3%, 15% and completion; the final signed 0.3.32
installation showed 60% and `Download Complete` in the restored capsule at a
423-point window width. Both resulting 8 MiB files matched the fixture bytes.
Simplified Chinese also showed the translated progress capsule. The byte-count,
unknown-total and late-callback mechanism is documented in the shared
[WebKit integration guide](../../../../_standards/workspace-docs/swift-docs/webkit-integration.md#download-progress).

WebKit page pixels remain blank and Accessibility exposes no interactive window.
The attempted dark-page launch therefore does not establish dark-page contrast.
The opened download list, pseudolanguage layouts, Finder interaction and
Escape/outside dismissal remain unverified. Repeat those paths on the installed
signed build when an interactive desktop is available; do not treat compilation
or the blank page as visual acceptance.

置顶窗跟随鼠标聚焦：图钉置顶后，鼠标进入窗口即抢回 key 焦点并聚焦网页，便于并排多应用快速切换输入。无悬停延迟；拖拽/缩放、盖子未揭、有模态或鼠标按住时不抢。

Overlapping pinned windows must not alternate key-window ownership: only the frontmost opaque window at the pointer in the same window layer may take focus. Convert AppKit pointer coordinates into the Core Graphics window-list coordinate system before testing coverage. If the window list or target ID is unavailable, keep the current focus. Higher-layer system overlays remain excluded under the existing coverage policy.

## 被否决的方案

### 悬浮胶囊 + 系统液态玻璃（已实现后推翻）

按侧边 Dock 的做法给左右两组按钮套液态玻璃胶囊，实测有两个硬伤：

1. **系统玻璃采不到网页画面**。网页由独立进程渲染，玻璃只会铺一层固定明暗的材质，背后的网页文字既不模糊也不被遮住。更糟的是这层材质在深色页面上偏亮，叠在最上层会**反向压低对比度**——深色网页上出现浅色底板托着浅色图标。若要保留玻璃，只能把它垫在最底层出质感、再用按页面明暗反算的底色盖在上面兜对比度，层序不能颠倒。
2. 视觉上是给每组按钮额外套了一圈，比裸图标更重、更碎。

结论：本场景不用液态玻璃。侧边 Dock 能用是因为它悬浮在桌面之上，玻璃采样的是**窗口背后**的画面，与这里的窗口**内部**叠加是两回事，不要照搬。

> 这条根因已上收为工作区通用判据（「背后画面系统采不采得到」是用不用玻璃的必要条件之一），见 [液态玻璃跨平台实践](../../../../_standards/workspace-docs/swift-docs/liquid-glass-practices.md)。本节保留本项目的裁定与实测细节。

### 悬浮控件常驻在网页之上（无让位带）

真正的"零占位"无界，但左右上角必然压住网页自己的站点标题和操作按钮，实测直接盖掉了导航元素。

### 鼠标靠近顶部才淡入

用来救上一条的遮挡问题，但逻辑上不成立：**鼠标移向顶部，恰恰说明用户想点的是网页顶部的元素**，浮出来的控件和用户意图正面冲突。

### 半透明遮罩盖在网页内容之上

把让位带去掉、网页顶到窗口最上沿，顶部盖一层由浓到透的半透明遮罩，让网页从遮罩里透出来。已被明确否决：

**渐变区不承载网页内容，它只是拖动区。** 网页内容一旦进入渐变范围，就会被压暗、被图标压住，且那块区域还要兼顾窗口拖动，点击归属永远说不清。渐变的作用是让让位带和网页背景之间没有硬边界，不是"给网页加一层滤镜"。

## 页面色取色规则（让位带的成败全在这里）

让位带的颜色就是页面色。取错色，带子立刻退化成一条突兀的横条——这是本设计最容易踩的坑，规则不可随意调整：

1. **优先取页面顶端真正被绘制出来的颜色**：从视口最上沿中点用 `elementFromPoint` 往上找第一个不透明背景，命中的通常就是站点自己的顶部导航底色，这样带子和页面顶端严丝合缝。
2. **站点声明的主题色（`theme-color`）只能当兜底，绝不能优先**。它是给浏览器界面用的提示色，经常故意和页面背景不同（Google 系站点页面是白的、主题色却是品牌蓝或深灰），优先用它会得到一条蓝色或深灰的带子配白页面。
3. **所有候选都拿不到时必须退回白色**。网页不设背景时浏览器实际画的就是白色；历史上这里退回的是深色，导致任何取色失败的站点都顶着一条黑条（实测 Google 翻译整条带子是纯黑、页面是纯白）。
4. 半透明颜色不能直接比较亮度：`relativeLuminance` 会先把它合成到兜底背景上，判断前必须 `resolved(over:)` 到真正的底色。

## 实现约束

- **让位带内的阴影必须收在带高以内**。网页视图紧贴让位带下沿且不透明，任何溢出到带子以外的阴影都会被它切掉，看起来是一道断口。悬停反馈使用圆形填色，不额外添加会溢出的投影。
- 顶栏配色全部从页面色推导，改 `BrowserChromeTheme` 时要保证：渐变起始色叠到页面色上之后，深色页面更暗、浅色页面更亮。对应断言在 `Tests/NeatWebAppRuntimeTests/BrowserChromeThemeTests.swift`。半透明颜色不能直接比较亮度——`relativeLuminance` 会把它合成到兜底深色背景上，必须先 `resolved(over:)` 到页面色再比。

## 验收

Verify the band has three controls on the left, and More Actions plus the conditional download capsule on the right. Open the native menu and inspect icon + label rows, the ribbon bookmark icon, both existing popovers, Escape/outside dismissal, and unchanged current-page bookmark and pin behavior. Exercise real downloads in the compact popover, including progress updates, concurrent active/completed records, failure, per-file Finder reveal and terminal-only clearing. Inspect English, Simplified Chinese, accented and double-length pseudolanguages; long labels must remain readable at a 423-point window width.

改顶栏后至少要在**浅色页面和深色页面**各截一次图，确认：网页自身顶部导航完整可见、看不出横条与分割线、图标对比度足够、阴影没有断口。

截图时注意：窗口一旦被别的窗口挡住大约八成就会立刻收进侧边 Dock（见 [window-auto-collapse.md](window-auto-collapse.md)），从终端截图必须让目标窗口处于激活状态，否则会截不到窗口。

<!-- 该文档整理/压缩于 2026-09-05 -->
