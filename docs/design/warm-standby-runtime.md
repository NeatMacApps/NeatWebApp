# Warm standby runtime: fast first open

How a web app that is **not running yet** opens without paying a cold process start. Covering-lid rules stay in [launch-cover.md](launch-cover.md); the launch steps are in [architecture.md](../architecture.md#launch-flow).

## Requirement (2026-10-07)

Opening a not-yet-running web app must feel like a native browser: the app's own work between the click and the page request leaving the machine is measured in tens of milliseconds, not seconds. Whatever remains is the site's own server time, which no client can remove.

## Diagnosis (2026-10-07, ChatGPT, this Mac, Debug build 0.3.20)

Real launch traced from the unified log (WebKit `Loading` / `Network` categories):

| Step | Time |
|---|---|
| Click → Launch Services starts the runtime | ~0.35 s |
| Runtime check-in → app init → web view created | ~0.65 s |
| Web content process launch, system font registration (~0.3 s on the main thread), first request on the wire | ~0.75 s |
| **Client subtotal: click → request sent** | **~2.0 s** |
| ChatGPT server time for the logged-in page (connection already open) | 4.5 s in that run; 0.6–3.9 s across repeated runs |

Ruled out by measurement:

- **User agent.** Default WebKit identity vs. Safari identity (`applicationNameForUserAgent`) gave the same server times, logged in and logged out. Do not change the user agent for speed.
- **Injected scripts, isolated data store, covering lid occlusion.** Turning each off did not change time to a usable input box.
- **Network setup.** Connection + TLS were ready in ~0.3 s, before the request; the wait was the server.

Why a browser feels faster: its processes, fonts, and connections are already warm, so it pays only server time. Each NeatWebApp web app is its own process, so a first open paid ~2 s of cold start **in series** before the server wait even began.

## Decision

The host keeps **one** pre-launched, app-agnostic runtime in standby:

- The standby runtime starts in the background shortly after the host starts and again a few seconds after it is consumed. It creates no window, registers no runtime state, and warms WebKit (network, GPU, and web content processes, font registration) with a throwaway blank page that never touches any web app's data store.
- When the user opens a not-running web app, the host writes the bootstrap with the standby's instance ID and sends an adopt command. The standby loads that bootstrap and continues on the normal runtime path (same covering lid, same locked frame, same per-app data store). It is indistinguishable from a freshly launched runtime afterwards.
- If no standby is ready, or the adopted standby does not report start-up within a short deadline, the host terminates it and launches a runtime the old way. The covering lid stays up throughout; the user never sees a failure.
- Only the user's explicit open uses the standby. Health restarts and version migrations keep using a fresh launch.
- Memory: the standby is a rebuildable cost (one runtime shell plus WebKit helper processes). On critical system memory pressure the host terminates it and does not replace it until the next open; this matches the "pressure only drops rebuildable things" rule in [memory-footprint.md](memory-footprint.md). App updates terminate it together with all runtimes. A standby exits by itself when its host is gone.

## Result (2026-10-07, same Mac, two real opens through the launcher)

| | Before | With standby |
|---|---|---|
| Click → main request on the wire | ~2.0 s | 0.39 s and 0.51 s |
| Server time (not ours) | 4.5 s | 1.0 s and 1.2 s |

What is left on the client side is WebKit launching a web content process for the adopted web app's own data store (~0.2–0.3 s). WebKit has no public API to pre-launch a content process for a data store that is not known yet, so the standby cannot remove it without first knowing which web app the user will pick.

Not adopted yet (product decisions, each costs memory for pages the user may not open): starting the load when the pointer rests on a launcher icon, and reopening recently used web apps in the background after login.

## Acceptance

- From a not-running state, open ChatGPT: the unified log shows the main-resource request leaving within ~0.1 s of the click (previously ~2 s).
- Covering lid, frame lock, per-app login state, and side-Dock behaviour are unchanged.
- Kill the standby before opening: the open still succeeds through the fallback launch.
- Activity Monitor shows at most one idle standby runtime.
