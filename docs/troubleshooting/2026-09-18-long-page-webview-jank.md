# Long pages freeze the WebApp window

When to read: any WebApp becomes unusable as on-page content grows — typing lags, scrolling stutters, the window feels frozen. Also read before assuming the Mac is too slow, before adding GPU / unload-page “fixes”, or before special-casing one website.

## Conclusion

NeatWebApp is a **generic** WebApp container. Long-page jank is a WebKit + site-frontend problem that shows up in chats, feeds, and similar lists. The same cliff is widely reported in Safari on fast Apple silicon. A fresh short page is immediately smooth; that rules out “the chip cannot keep up.”

Do **not** add a host allowlist or a ChatGPT-only selector. The display path must apply to every WebApp.

## What the container does now (2026-09-18)

Silent, no extra chrome. Do not “fix” lag by unloading the page or killing the runtime; collapsed windows must stay instant. See [memory-footprint.md](../design/memory-footprint.md).

1. **Off-screen block parking (all sites).** Homogeneous vertical lists with enough siblings skip paint for blocks well outside the viewport (`content-visibility: hidden` + reserved height). Nodes stay in the tree (React-safe). Newest siblings and the focused block stay live. Do **not** switch this to `content-visibility: auto` — WebKit can leave on-screen content blank.
2. **Theme sampling no longer watches `main`.** Hit-testing the top edge is coalesced (~280ms). Streaming UIs mutate `main` constantly; observing it was extra layout work on a huge document.
3. **No-op web-view re-attach.** Chrome-state SwiftUI updates no longer re-sync navigation state into the session.

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

- Lists shorter than the sibling threshold are left untouched.
- Site composers (rich text boxes) stay the site’s; parking cuts competing layout, it does not replace the input.
- Do not detach nodes from the document, share content processes, or chase GPU / 120 Hz flags for this symptom.

## Evidence

- Same family of client-side freezes on long chat threads in Safari (example reports on ChatGPT web; the mechanism is not unique to that site).
- Parking source: `BrowserOffscreenBlockParkingScript`. Install entry: `BrowserUserScripts.install`.
- Theme observer: `html` / `body` / `head` only; `main` is sampled when posting a color, not observed.
- Confirm on a long page in **any** affected WebApp after a window reload: scrolling and typing stay usable; a short page is unchanged.

<!-- reviewed: 2026-09-18 -->
