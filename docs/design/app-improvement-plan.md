# App improvement plan

Status: Resumed for implementation on 2026-09-21 at the user's direction (`继续`).
The 2026-09-20 "plan only" status is superseded. Prototype code from 2026-09-20 has been
adopted, repaired, and extended; build plus full unit tests pass on 2026-09-21.
Installed-app acceptance (real Quit linkage, real drag gestures, download/bookmark chrome,
management window screenshots, long-page comparison) is still pending and must be done on
the user's live app when it is idle — do not kill the user's running WebApps to verify.

## 0. Resumption log (2026-09-21)

## 1. Scope and evidence

Evidence timestamp: the table below mixes 2026-09-20 analysis baselines (installed 0.3.16,
HEAD `51e0935`) with 2026-09-21 resumption state (build + full tests green, installed-app
acceptance still pending). Rows marked [2026-09-21] supersede the plan-only limits.

The requested outcomes are:

- Quitting NeatWebApp also ends the WebApps it owns.
- A user can intentionally position a browser window partly outside a display without it snapping back.
- Bookmarking the current page and opening the bookmark list are visually distinct.
- Completed download notifications can be dismissed. The user corrected the initial report: clicking to reveal the download already works.
- Investigate and reduce container overhead on long, interactive pages, especially ChatGPT.
- Redesign the management window, make sorting discoverable and pleasant, and align settings.
- Include closely related usability defects found along these paths; avoid unrelated features or architectural rewrites.

Verified during analysis:

| Finding | Evidence | Limit |
|---|---|---|
| Installed application reports 0.3.16 / 3034; four runtime processes were present | Installed Info.plist and running process inspection | Version alone does not identify all source changes in a local development build |
| Repository HEAD is `51e0935`, tagged release 0.3.17 | Git, remote refs, and completed release log | This release was not installed in this session |
| Browser has an undismissable Download Complete pill and similar bookmark symbols | Real ChatGPT window screenshot; browser view/session source | Opening the download is confirmed by the user, not independently clicked in this analysis |
| Management view combines applications and all settings in one fixed 520 x 720 content layout | Actual screenshot, accessibility tree and Dashboard source | No new layout was implemented |
| Drag-enter changes the saved order before drop | `AppDropDelegate.dropEntered` calls `moveCustomApps`; that function saves and refreshes the runtime registry | Cancellation and drag animation were not recorded live |
| Browser position is clamped into a display/Dock reserve | Pre-change `WebAppBrowserWindow.constrainFrameRect` | Multi-display and all four edges remain to be exercised |
| Ordinary host termination did not invoke runtime cleanup | Pre-change AppDelegate and termination call chain | No destructive baseline quit was performed against current user pages |
| Theme observer does redundant style work and can enqueue redundant throttle timers | `BrowserThemeObserver` in BrowserWebView | Its contribution to actual ChatGPT lag is not yet measured |
| [2026-09-21] Build + full unit tests green with adopted prototypes | `xcodebuild ... build` + `... test` on 2026-09-21 (92 host + 77 runtime tests) | Installed-app acceptance still pending; user WebApps are running, do not kill them to verify |
| [2026-09-21] Prior build failure in adopted prototype fixed | `NeatWebAppApp.init` touched `appDelegate` before all `let` members were set | Fixed by constructing `AppUpdater` first; build green after fix |
| [2026-09-21] Prototype gaps closed during resumption | `windowDidChangeScreen` guard, transactional `AppDropDelegate`, settings row alignment, theme-script redundancy (§5 items 1–4), launcher debug file logging removed | Real-gesture and real-Quit acceptance still pending (see §8) |

Baseline screenshots were inspected at `/tmp/neatwebapp-browser-before.png` and `/tmp/neatwebapp-settings-before.png`. A three-second native runtime sample is at `/tmp/neatwebapp-runtime-sample-before.txt`: the sampled native main thread was mostly waiting. This does not characterize scrolling/typing latency or prove that WebKit, the network, or the site is responsible. These temporary evidence paths are not durable test fixtures.

## 2. Host and WebApp lifetime

### Intended behavior

- Explicit Quit from either menu or management window closes the host and all its owned runtime sessions.
- Closing the management window, hiding the host, or collapsing a WebApp keeps the intended background behavior. These actions must not be confused with Quit.
- Host failure must not leave orphaned WebApps indefinitely.
- Preserve website cookies, local storage, bookmarks and accepted preferences. Only ephemeral runtime registration/launch/lock state is cleaned up.

### Implementation work

1. Route all allowed termination paths through one idempotent shutdown entry. Stop new launches and health-driven relaunches before ending children.
2. Request cooperative runtime exit, and let each runtime save placement and remove its own ephemeral state. Audit the existing `terminateAll` helper: it sends a command and calls `NSRunningApplication.terminate`; it does not currently acknowledge completion.
3. Use a bounded asynchronous completion period where appropriate; never block the main thread waiting for children. Define how an unresponsive owned runtime is handled before adding force-termination logic.
4. Bind a runtime to the host instance that launched or adopted it. Cover the race where the host dies before the runtime installs supervision, and old runtimes discovered after a restart. A launch PID alone is insufficient as a durable identity.
5. Prefer an event-driven process/application termination observation over a permanent 500 ms poll where feasible. The current prototype polls; review it, do not accept it merely because it exists.
6. Revalidate executable identity and launch identity before any process-directed termination. Never kill all WebKit processes or all processes sharing a short name.
7. Keep Sparkle update teardown and normal Quit consistent, and ensure shutdown does not trigger runtime recovery/relaunch.

Files: `AppDelegate.swift`, `NeatWebAppApp.swift`, `AppModel+WebApps.swift`, `WebAppRuntimeCoordinator.swift`, `RuntimeLauncher.swift`, runtime bootstrap/app/window coordinator files; lifecycle tests.

### Acceptance

Test zero, one, and several open/collapsed WebApps. Test both Quit entry points, close-window, hide, host abnormal termination, launch/quit race, restart and update teardown. Verify process exit and registry/lock cleanup separately. Reopen and verify persistent website state. Any timeout/force path must prove it cannot target an unrelated process.

## 3. Window placement without snap-back

### Root cause and unresolved interactions

The original frame constraint unconditionally clamps to the display's usable rectangle after Dock avoidance. That treats deliberate positioning like recovery from an invalid saved frame. Other placement paths also clamp: Dock reserve updates, initial restoration and screen changes must be checked together.

The prototype removes one clamp but still calls AppKit's superclass constraint; Apple documents that this can adjust the top edge and height. It therefore does not yet prove that dragging beyond every edge works. A one-pixel display intersection also does not guarantee that a window is usable.

### Proposed rules

| Situation | Proposed behavior |
|---|---|
| User is dragging a visible window | Preserve the requested position; do not repeatedly resize or recenter it |
| User releases with a usable portion on screen | Keep the position, including negative coordinates |
| Pointer moves through the area reserved for the side Dock | Avoid repeatedly rewriting the full frame; retain access to the Dock and explicitly test the chosen overlap policy |
| Window is restored or a display is disconnected | Recover only when necessary for reachability; choose a current display from actual intersection/history |
| User explicitly requests maximize/zoom | Fit the usable area and honor the Dock reserve |
| User deliberately drags most of the window out | Preserve the existing 80% invisible-area policy unless separately changed; test this threshold explicitly and do not silently promise unlimited off-screen parking |

The 80% auto-collapse rule and the existing 'never cover the side Dock' rule intersect with the new request. Resolve these as separate policies, not by deleting all geometry checks. The safe initial target is useful partial off-screen placement while keeping recovery and collapse behavior predictable. Do not persist a zoomed desktop-sized frame as the user's normal window size.

Files: `WebAppBrowserWindow.swift`, `WebAppWindowController` and its placement extensions, `RuntimeWindowCoordinator.swift`, shared placement/Dock avoidance utilities and geometry tests.

Acceptance: left/right/bottom/top-edge behavior, slow drag and quick drag, narrow/large windows, 10–50% off-screen placement, 80% threshold, pinning, collapse/reopen, quit/relaunch, mixed display scales, negative-coordinate displays, display unplug and Dock movement. Record actual drags and read back final geometry; unit geometry tests alone are insufficient.

## 4. Download status and bookmarks

### Downloads

- Keep the currently functioning reveal-in-Finder action.
- Add a separate visible close control for completed or failed status. Dismissal affects UI state only and must never delete the downloaded file.
- Keep an active download visible; do not make dismiss look like cancel. Download cancellation is outside this repair unless separately designed.
- For multiple terminal records, dismissal must not strand the user in an unexplained sequence of old notifications. Define whether the compact presentation dismisses the current item or a finished batch, and make the accessible label match.
- Check completed, failed, concurrent, missing-file and repeated-dismiss cases. If a file was moved/deleted, give useful feedback instead of silently doing nothing.
- Keep the indicator compact in the observed 423-point browser window. Preserve stable click targets for nearby browser actions, and provide filename/details on demand.

### Bookmarks

- Keep a star for add/remove current-page bookmark, with filled/unfilled state.
- Use a clearly list-shaped icon for opening saved bookmarks, such as `list.bullet.rectangle`.
- Provide distinct localized help and accessibility names, plus a readable empty state.
- Preserve per-WebApp isolation and the existing keyboard shortcut.

Files: `BrowserContainerView.swift`, `BrowserSession.swift`, browser string catalog and `BrowserDownloadStatusTests.swift`.

Acceptance: download a real disposable fixture, reveal it, dismiss the status, verify the file still exists, and repeat with several downloads. Inspect both light and dark pages, narrow windows, keyboard focus and bookmarks isolation. This remains unverified for the current prototype.

## 5. Long-page performance

### What must be measured first

Treat loading delay, input delay, scrolling frame stalls and native-window lag as different symptoms. Record the actual installed build/configuration, page length, viewport, zoom, user agent, hidden-element rules and whether content is streaming. Compare like-for-like conditions before attributing a result.

Use a repeatable local long-page/streaming fixture to isolate container overhead, followed by an actual existing ChatGPT conversation. Where possible compare the same workload in Safari and Chrome without changing account/session state or sending messages. The local fixture is a controlled diagnostic, not a substitute for the user's page.

Measure frame durations and long frames, input-to-render latency, native and web-content CPU samples, style/layout time and theme callback counts. Run multiple short repetitions under comparable system load; do not claim a percentage from a single idle sample. Only collect the relevant Web Inspector timelines, because profiling itself adds overhead.

### Confirmed code-level opportunities

1. `parseColor` writes a probe style and reads computed style even for colors already returned as RGB by computed style. Parse valid RGB directly and use a cached/contained normalization fallback only when necessary.
2. Top-edge sampling parses a color, returns its string, then parses that color again. Return the parsed value instead.
3. After a valid top-edge color is found, the code still reads body/html/main and theme metadata. Return immediately; evaluate fallback candidates lazily.
4. The 280 ms throttle can create multiple pending ordinary delay callbacks. Keep at most one ordinary throttle timer. Preserve deliberate navigation/load resynchronization and cancel outstanding callbacks on teardown.

Validate color correctness for transparent ancestors, RGB/RGBA and supported CSS color formats, dark/light theme changes, route changes and page load. Test callback bounds under rapid mutations. Preserve the documented priority of actual top-edge background over theme-color metadata.

### Restrictions and stop criteria

- Do not reintroduce off-screen list parking, whole-document rescanning, ChatGPT-specific selectors, content detachment, forced reload/unload, shared content processes, or private GPU flags.
- Do not change proxies/network configuration without evidence of a network fault.
- Ship a performance change only if it removes proven redundant work and passes appearance/interaction regressions. Claim improvement in ChatGPT only after measuring it there.
- If native/container work is small and page layout dominates, document that boundary and the remaining symptom instead of promising a complete fix.

Files: primarily `BrowserWebView.swift`/`BrowserThemeObserver`, existing script installation tests, a focused script behavior/performance fixture and the long-page troubleshooting record. BrowserSession changes only if tracing demonstrates a separate invalidation problem.

## 6. Management window redesign

Detailed visual direction: [Dashboard and Settings proposal](../../../docs/design/dashboard-settings.md). The requirements are confirmed; the exact dimensions and two-pane layout below remain proposed, not user-approved artwork.

### Layout

- One existing management window. Narrow navigation containing Web Apps and Settings; detail pane shows one page at a time. Do not add a second settings window.
- Proposed starting size 880 x 620 points, minimum around 760 x 520, subject to real-screen acceptance. Permit resizing. Preserve a visible native close control.
- Web Apps header: page title and Add action. List rows: drag handle, site icon, name/domain, always-visible Open and More actions. Keep ordinary text untruncated where feasible; long domains truncate without displacing actions.
- Settings groups: General (login/menu bar), Launcher (Dock position/non-notch activation/reveal), Application (updates/quit). Use plain localized labels, not internal 'runtime' terminology.
- One leading label column and one trailing control column. Same control sizes; switches share a trailing edge, buttons have consistent sizing, and multi-line labels expand row height without shifting the control column.
- Use restrained solid backgrounds, native controls, consistent spacing and content hierarchy. No decorative cards within cards, outer focus rings, marketing copy or debugging controls.

### Sorting behavior

1. A persistent grip clearly identifies reordering. Its drag hit area must not compete with Open/More or accidentally launch the WebApp.
2. Lift a compact recognizable preview containing the icon and name, not the full row/card and not an invisible preview.
3. Show one insertion line between rows. Handle the first and last positions and both halves of each row. Avoid changing row heights as the pointer crosses them.
4. Keep the original order and transient insertion target while dragging. Do not call the current save-and-refresh path on `dropEntered`.
5. Commit once on a validated internal drop; persist once. A no-op drop does not save. Escape, invalid/external drop, window closure, or cancellation leaves the original order intact.
6. Clear stale drag state reliably even if drop happens outside the view. Add edge autoscrolling for lists longer than the viewport, and an accessible move-up/move-down alternative.
7. Preserve focus/selection by stable app identity. Reordering the catalog should not reload active webpages or repeatedly refresh runtime state.

### Forms, language and task costs

- Preferences apply immediately; no Save button is added. Invalid incomplete input must not replace the last accepted value.
- Add/Edit remains a deliberate form submission; preserve entered data on validation failure. Deletion retains confirmation because it can affect user setup.
- Make list actions keyboard reachable without requiring mouse hover. Review the current accessibility tree, which exposed repeated row buttons, and ensure each action has one meaningful label.
- Move edited user-facing text into the proper host string catalog and cover English/Simplified Chinese. Keep browser and host catalogs separate.
- Preserve legitimate login-item blocked-state recovery and update availability. Do not show a fake 'up to date' state.
- Cold start and replacement install remain silent. Open the management window only for the specifically authorized design/interaction inspection, then close it after acceptance.

Files: `DashboardView.swift`, `SettingsSectionView.swift`, related panel style helpers, host string catalog, scene sizing in `NeatWebAppApp.swift`, and reorder persistence entry points only as required.

Acceptance: inspect both pages, Add/Edit/cancel, list Open/More, top-to-bottom and reverse sorting, cancellation and outside drop, long-list autoscroll, one-save semantics, restart persistence, narrow/wide sizes, long English labels, Chinese, light/dark appearance and full keyboard navigation. Record the drag animation, not just the final list screenshot. Restore the user's original test ordering/preferences afterward.

## 7. Delivery sequence and gates

| Order | Work | Completion gate |
|---|---|---|
| 1 | Review retained prototypes and freeze behavior contracts | Identify all unverified changes; resolve lifetime and geometry races before reuse |
| 2 | Lifecycle, download/bookmark fixes; management redesign in separate file ownership | Focused tests and one integrated build; no simultaneous builds on this Mac |
| 3 | Window placement and sorting | Real gestures, cancellation, persistence and recovery accepted |
| 4 | Performance baseline and bounded observer optimization | Controlled comparison plus actual-page evidence; no unmeasured speed claim |
| 5 | Combined installed-app acceptance | All affected user tasks work together on the actual installed application |
| 6 | Release, only after implementation is resumed and verified | Follow existing signed release workflow; independently report local installation and remote release |

Performance measurement can begin alongside UI work, but record which binary is running. Window changes and lifecycle changes share files and must have one owner. Do not split BrowserSession or scene entry-point editing between simultaneous writers. No new dependency or engine replacement is needed for the planned first pass.

The working tree on 2026-09-21 contains adopted-but-uncommitted implementation plus this
plan update. Commit, push, installation, and release are still separate gated steps (§7)
and require installed-app acceptance first. Do not discard or isolate colleagues'
working-tree changes in order to resume or publish.

## 8. Retained work and resumption risks (updated 2026-09-21)

2026-09-20 prototypes were adopted on 2026-09-21: build fixed, gaps closed (screen-change
guard, transactional drop, settings alignment, theme-script redundancy, launcher debug
logging removed), and full unit tests pass. What remains is installed-app acceptance on the
user's live app — it must wait until the user's WebApps are idle:

- Real Quit from menu/management window ends all owned runtimes; registry/lock cleanup;
  reopen preserves site state. Do NOT `pkill` the user's running WebApps to check this.
- Real drag gestures: partial off-screen placement on all four edges, 80% auto-collapse
  threshold, Dock-avoidance interaction, display-unplug recovery.
- Download fixture: reveal-in-Finder, dismiss status, file still exists, repeated dismiss.
- Management window: both pages, Add/Edit/cancel, sorting incl. cancellation and outside
drop, narrow/wide sizes, Chinese/English, light/dark, keyboard navigation, drag recording.
- Long-page comparison on the actual ChatGPT conversation (local fixture first, then the
  real page; Safari/Chrome comparison without changing account/session state).

Known residual risks before acceptance: exit during bootstrap before supervision attaches;
recovered/adopted runtimes from older builds without `--host-pid` (e.g. a runtime started
before the update keeps running with no supervision hint); shutdown-triggered relaunch via
health checks; top-edge superclass constraints; 80% auto-collapse firing while the user
drags mostly off-screen. Do not describe the work as finished before installed-app
acceptance passes.

## 9. Authority and references

- [Current architecture](../architecture.md), [browser chrome](browser-top-chrome.md), [window collapse](window-auto-collapse.md), [long-page troubleshooting](../troubleshooting/2026-09-18-long-page-webview-jank.md), [launch cover](launch-cover.md), [memory constraints](memory-footprint.md).
- [Apple: window frame constraints](https://developer.apple.com/documentation/appkit/nswindow/constrainframerect(_:to:)) — superclass behavior includes top-edge/height adjustments; verify it separately from custom constraints.
- [Apple: application termination observation](https://developer.apple.com/documentation/appkit/nsrunningapplication/isterminated) — termination state is observable; an event-driven design is available for evaluation.
- [Apple: DropDelegate](https://developer.apple.com/documentation/swiftui/dropdelegate) — entering, moving, leaving and performing a drop are distinct lifecycle stages.
- [WebKit: Timelines](https://webkit.org/web-inspector/timelines-tab/) and [Apple: webpage performance analysis](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/Web_Inspector_Tutorial/EnhancingyourWebpagesPerformance/EnhancingyourWebpagesPerformance.html) — distinguish script/layout/render/network work and profiling overhead.

External sources establish API semantics, not proof of this application's performance or correctness. Existing implementation supplies the reference pattern for this bounded repair; no outside project's code is adopted.
