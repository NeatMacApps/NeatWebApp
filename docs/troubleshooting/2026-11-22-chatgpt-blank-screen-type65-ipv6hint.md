# ChatGPT Blank White Screen When Browser Works (`TYPE65` `ipv6hint` Leak)

## Symptom

Opening `https://chatgpt.com` in NeatWebApp (`WKWebView`), Safari, or `URLSession` fails with `NSURLErrorDomain` code `-1005` (`NSPOSIXErrorDomain` code `54`: `Connection reset by peer`), while Chrome and `curl` open `chatgpt.com` normally. Previously, NeatWebApp swallowed the provisional navigation failure, showed a blank white `about:blank` window, and `⌘R` / Reload was a no-op because `webView.url` remained `nil`.

## Root Cause

1. When the Mac holds a native global IPv6 address and default route (`en0`) alongside an IPv4-only TUN proxy (`utun0` with `strictIpv6: false` / IPv6 TUN capture off):
   - The local DNS resolver strips `AAAA` (`ANCOUNT=0`) because `dns.ipv6: false`, **but still answers DNS `TYPE65` (`HTTPS` RR)** containing Cloudflare `ipv6hint` addresses.
   - **Chrome** follows RFC 9460 §7.3 and does not dial `ipv6hint` when `AAAA` is absent, so it connects via IPv4 through `utun0`.
   - **Apple `Network.framework`** (`WKWebView` / `URLSession` / Safari) prioritizes `TYPE65` `ipv6hint` ahead of IPv4 even when `AAAA` is empty, connects directly to the IPv6 endpoint over `en0` (bypassing the IPv4-only TUN), and receives a TLS-handshake TCP RST (`Connection reset by peer`) on every retry.
2. macOS / `WKWebView` provides no public API to disable DNS `TYPE65` (`HTTPS` RR) lookups or `ipv6hint` dialing per view.

## Resolution

- **NeatWebApp container fixes:**
  1. Surface a native `ContentUnavailableView` error overlay with `Retry` and `Open in Browser` actions on non-cancelled main-frame navigation failures, plus `os.Logger` diagnostics (`BrowserNavigation`).
  2. Fix `reload()` and `reloadIgnoringCache()` to fall back to `load(_:)` when `loadError != nil` or `webView.url == nil` after a provisional failure.
  3. Recover from `webViewWebContentProcessDidTerminate(_:)` with a single automatic reload and a 15-second loop guard.
- **Host proxy/DNS requirement:** To let `WKWebView` / `URLSession` / Safari connect to dual-stack hosts through an IPv4-only TUN, suppress DNS `TYPE65` (`HTTPS`) / enable strict IPv6 protection in the proxy configuration (`proxy-agent leak set strictIpv6 on`).
