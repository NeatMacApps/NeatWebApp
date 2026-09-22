# Long pages freeze the WebApp window

When to read: any WebApp becomes unusable as on-page content grows — typing lags, scrolling stutters, the window feels frozen. Also read before assuming the Mac is too slow, before adding GPU / unload-page “fixes”, or before injecting scripts that hide, skip-paint, or re-scan long lists.

## Conclusion

NeatWebApp is a **generic** WebApp container. Long-page jank is a WebKit + site-frontend problem that shows up in chats, feeds, and similar lists. The same cliff is widely reported in Safari on fast Apple silicon. A fresh short page is immediately smooth; that rules out “the chip cannot keep up.”

Do **not** add a host allowlist or a ChatGPT-only selector.

## Veto (2026-09-19): no off-screen list parking

Do **not** inject a page script that parks, skip-paints, or re-scans off-screen list blocks (`content-visibility`, `data-neat-parked`, subtree mutation observers that re-bind the whole tree, or any rename of the same idea).

That approach was shipped as a container-wide display optimization. Streaming chats (Gemini-class) mutate the DOM constantly; the extra scan made NeatWebApp feel far slower than Chrome on the same machine and network. The user rejected it: delete it, do not debounce it, do not bring it back under another name.

## What the container still does

Silent, no extra chrome. Do not “fix” lag by unloading the page or killing the runtime; collapsed windows must stay instant. See [memory-footprint.md](../design/memory-footprint.md).

1. **Theme sampling no longer watches `main`.** Hit-testing the top edge is coalesced (~280ms). Streaming UIs mutate `main` constantly; observing it was extra layout work on a huge document.
2. **No-op web-view re-attach.** Chrome-state SwiftUI updates no longer re-sync navigation state into the session.

Hardware composition is already the system default on Apple silicon. Extra GPU / 120 Hz flags do not fix a blocked page thread.

## How to tell it apart

| Observation | Read as |
|---|---|
| Short page is fine; the long one is not | Site is rendering a huge live list |
| Same page is also bad in Safari | Engine + site; container is not uniquely broken |
| Same page is fine in Chrome, bad here / Safari | WebKit handles this DOM worse than Chromium |
| Top-bar collapse / pin still clickable, page itself dead | Page thread is blocked; native chrome is not |
| Every WebApp stutters, even a short static site | Different bug — do not use this note |

## Remaining limits

- Site composers (rich text boxes) stay the site’s.
- Do not detach nodes from the document, share content processes, chase GPU / 120 Hz flags, or re-introduce list parking for this symptom.

## Evidence

- Same family of client-side freezes on long chat threads in Safari (example reports on ChatGPT web; the mechanism is not unique to that site).
- 2026-09-19: parking script removed after it made Gemini in NeatWebApp worse than Chrome. Guard: `BrowserUserScriptsInstallTests`.
- 2026-09-22: ChatGPT typing/resize jank traced mostly to the container, not the engine. The user's own hide-rules on `chatgpt.com` included site-wide bombs (`.visible`, bare `li:nth-of-type(1/2/3)`, `.agent-turn > div:nth-of-type(3)`) injected as `display: none !important` on every load — every streamed token and every resize tick re-matched them against a huge DOM. Deleted 9 rules across `chatgpt`/`chatgpt2` (backup `/tmp/web-apps.json.bak-20260922`). Container taxes fixed in the same pass: idempotent `BrowserSession.attach` (no repeated pageZoom/UA/background IPC), debounced window-frame persist off the drag hot path, cheap checks before the WindowServer snapshot + 100ms→250ms coverage poll, head childList observer narrowed to META/STYLE/LINK + skip sampling while `document.hidden`. New hide-rules over the broad-match limit post back a `broad` message so the panel can point at restore. Guards: `testThemeScriptIgnoresIrrelevantHeadInsertionsAndHiddenDocuments`, `testHidingScriptReportsBroadRules`.
