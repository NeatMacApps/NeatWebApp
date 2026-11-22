# ChatGPT Blank White Screen When Browser Works (`TYPE65` `ipv6hint` Leak)

## Symptom

Opening `https://chatgpt.com` in NeatWebApp (`WKWebView`), Safari, or `URLSession` fails with `NSURLErrorDomain` code `-1005` (`NSPOSIXErrorDomain` code `54`: `Connection reset by peer`), while Chrome and `curl` open `chatgpt.com` normally. Previously, NeatWebApp swallowed the provisional navigation failure silently, and `⌘R` / Reload was a no-op because `webView.url` remained `nil`.

## Root Cause

1. When the Mac holds a native global IPv6 address and default route (`en0`) alongside an IPv4-only TUN proxy (`utun0`):
   - The local DNS resolver strips `AAAA` (`ANCOUNT=0`) because IPv6 resolution is disabled, **but still answers DNS `TYPE65` (`HTTPS` RR)** containing Cloudflare `ipv6hint` addresses when strict `TYPE65` suppression is off.
   - **Chrome** follows RFC 9460 §7.3 and ignores `ipv6hint` when `AAAA` is absent, so it connects via IPv4 through `utun0`.
   - **Apple `Network.framework`** (`WKWebView`, `URLSession`, Safari) prioritizes `TYPE65` `ipv6hint` ahead of IPv4 even when `AAAA` is empty, connects directly to the IPv6 endpoint over `en0` (bypassing the IPv4-only TUN), and receives a TLS-handshake TCP RST (`Connection reset by peer`) on every retry.
2. macOS / `WKWebView` provides no public API to disable DNS `TYPE65` (`HTTPS` RR) lookups or `ipv6hint` dialing per view. See the shared [WebKit integration guide](../../../../_standards/workspace-docs/swift-docs/webkit-integration.md#provisional-load-failures-uncommitted-reload-and-networkframework-dns-2026-11-22) for the platform constraints and container recovery contract.

## Resolution

- **NeatWebApp container fixes (non-UI only; owner vetoed adding a custom load-error view in [browser-top-chrome.md](../design/browser-top-chrome.md#自定义加载失败占位页2026-11-22-已否决)):**
  1. Log non-cancelled main-frame navigation failures (`shouldLogLoadError(_:)`, `handleNavigationFailure(_:failingURL:)`) and WebContent terminations (`handleWebContentProcessDidTerminate(now:)`) via `os.Logger` (`com.geraltgraham.NeatWebAppRuntime`, category `BrowserNavigation`) in `Sources/NeatWebApp/Features/Browser/BrowserSession.swift` (wired from `BrowserWebView.Coordinator` in `Sources/NeatWebApp/Features/Browser/AppKitBridge/BrowserWebView.swift`), omitting query strings and credentials.
  2. Fix `reload()` and `reloadIgnoringCache()` to fall back to `load(_:)` when `lastFailedURL != nil` or `webView.url == nil` after an uncommitted provisional failure, while `attach(webView:)` guards auto-loading uncommitted `webView.url == nil` views behind `!alreadyAttached` so SwiftUI updates do not loop-reload a failed page.
  3. Recover from `webViewWebContentProcessDidTerminate(_:)` with a single automatic reload gated by `processTerminationLoopWindow` (15 seconds).
- **Host proxy/DNS resolution (verified 2026-11-22):** Enabling strict IPv6 / DNS `TYPE65` (`HTTPS`) suppression in the host TUN proxy/DNS resolver (`TYPE65` returning empty `NOERROR`) restored default-network-stack `WKWebView` loading of `https://chatgpt.com/` to HTTP `200`, `didFinish`, ~437 KB DOM, and zero JavaScript errors.
