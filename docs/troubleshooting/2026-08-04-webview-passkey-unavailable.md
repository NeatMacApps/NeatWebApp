# 内嵌网页用不了通行密钥（Passkey / WebAuthn）

排查「WebApp 里点通行密钥登录没反应」「网站说无法使用通行密钥」，或准备给内嵌网页补任何**由系统代管的凭据类能力**（通行密钥、密码自动填充、Apple Pay）之前先读本文。

## 结论

**不是本项目缺组件或漏配置，是苹果的平台限制。** `WKWebView` 里的网页只能对「本应用通过关联域名（Associated Domains 的 `webcredentials`）声明过的站点」使用 WebAuthn。NeatWebApp 是通用 WebApp 容器，装的是 claude.ai、github.com 这类**别人家的域名**，无法也不应该去声明关联，因此系统一律拒绝。

苹果对这条限制给的唯一正门是受限权限 `com.apple.developer.web-browser.public-key-credential`：持有它的应用可以对任意 relying party 发起通行密钥请求，Chrome、Firefox 在 macOS 上就是靠它用上 Apple Passwords 里的通行密钥的。该权限**只发给正式浏览器产品**，要单独向苹果提交申请审批（申请表的第一个问题就是「你的 App 是不是 macOS 上的浏览器」），不是加一行配置就能有的东西。

已确认与本项目实现无关的几点（排查时不用再查一遍）：

- 运行时没有声明 `WKAppBoundDomains`，也没有开 `limitsNavigationsToAppBoundDomains`，不存在自我设限。
- 每个 WebApp 用独立 `WKWebsiteDataStore` 做数据隔离，与通行密钥可用性无关。
- 移动版 UA 开关不影响可用性，只影响站点把哪种登录方式排在前面。

## 现在的行为

网页调用被系统拒绝时，容器会弹一次说明，并提供「用浏览器打开」直接把当前页面交给默认浏览器完成登录。实现见 `Sources/NeatWebApp/Features/Browser/BrowserPasskeySupport.swift`：

- 注入脚本只**包装**`navigator.credentials.get/create`，原方法照常调用、结果原样透传、错误按原样抛回站点，不改变任何站点行为。
- 只有 `NotAllowedError` / `NotSupportedError` / `SecurityError` 才判定为平台拒绝并上报；站点自身校验失败、用户主动取消不算。
- 每个窗口只解释一次，站点连续重试不会连弹。

## 三条可能的出路

1. **申请浏览器权限**（唯一能让通行密钥真正可用的路）：需要以「macOS 浏览器」身份向苹果申请 `com.apple.developer.web-browser.public-key-credential`，获批后配套 `ASAuthorizationWebBrowserPublicKeyCredentialManager` 使用。**批准前不要把这条权限写进 entitlements**，未获授权的受限权限会让签名/公证或启动直接失败。社区反馈该链路在 macOS 小版本升级后出现过整片失效的回归（错误码 1004），即便拿到也要留退路。
2. **改用其它登录方式**：绝大多数站点都还留着密码、验证码或第三方跳转登录，这是当前对用户成本最低的做法。
3. **换到默认浏览器完成登录**：会话留在浏览器里，回到容器仍需要该站点支持的其它登录方式，因此只对「登录一次拿长期 cookie」的站点有意义。

不要尝试用 `ASWebAuthenticationSession` 替代：它拉起的是默认浏览器的独立会话，登录结果回不到容器的 `WKWebView` 里，只适合自家 OAuth 回调，不适合通用容器。

## 参考

- [`com.apple.developer.web-browser.public-key-credential` 权限文档](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
- [`ASAuthorizationWebBrowserPublicKeyCredentialManager`](https://developer.apple.com/documentation/authenticationservices/asauthorizationwebbrowserpublickeycredentialmanager)
- [苹果工程师说明：WKWebView 的 WebAuthn 仅限关联域名](https://developer.apple.com/forums/thread/714785)
- [passkeys.dev：嵌入式 WebView 与系统 WebView 的能力边界](https://passkeys.dev/docs/reference/macos/)

<!-- 该文档整理/压缩于 2026-09-05 -->
