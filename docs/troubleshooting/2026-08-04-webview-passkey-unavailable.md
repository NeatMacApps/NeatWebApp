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

1. **申请浏览器权限**（唯一能让通行密钥真正可用的路）：见下一节「如何向苹果申请」。获批后配套 `ASAuthorizationWebBrowserPublicKeyCredentialManager` 使用。**批准前不要把这条权限写进 entitlements**，未获授权的受限权限会让签名/公证或启动直接失败。社区反馈该链路在 macOS 小版本升级后出现过整片失效的回归（错误码 1004），即便拿到也要留退路。
2. **改用其它登录方式**：绝大多数站点都还留着密码、验证码或第三方跳转登录，这是当前对用户成本最低的做法。
3. **跳到系统默认浏览器做通行密钥**：**只能在浏览器里完成验证，不能把登录态带回容器。** 系统浏览器与本应用的内嵌网页是两套互不共享的站点数据（本产品还按网页应用隔离数据仓），Safari / Chrome 里写上的登录 cookie **不会**出现在容器窗口。因此：
   - 用户若愿意改在默认浏览器里继续用那个网站 → 可行（当前提示里的「用浏览器打开」就是这条）。
   - 用户期望「浏览器里过完通行密钥，回到 NeatWebApp 已登录」→ **不可行**，不是漏接回调，是平台会话隔离。
   - 系统登录会话（`ASWebAuthenticationSession`）同样解决不了通用容器：它适合**自家** OAuth（用回调地址拿令牌再自己建会话），不适合把 claude.ai / github.com 这类第三方站点的网页会话灌进内嵌网页。苹果对「第三方域名要通行密钥」常指去用它，前提是应用自己掌控登录协议；本产品装的是任意第三方站，接不上。

不要把「跳浏览器做通行密钥」当成容器内登录的替代方案来做产品闭环；它只是逃生口，不是会话交接。

## 如何向苹果申请（2026-09 调研）

权限名：`com.apple.developer.web-browser.public-key-credential`（门户里常写作 *macOS Browsers Passkeys* / *Web Browser Public Key Credential*）。这是**受管能力**：苹果先批到开发者账号，再绑到具体 App ID，最后才能写进签名描述文件。

### 提交人与入口

- **必须由开发者账号的 Account Holder（账户持有人）提交。** 组织账号里 Admin / Developer 等其它角色打开申请页会看到 “Your account can't access this page”；苹果 DTS 已确认这是持有人角色限制，不是选错表单。
- 专用表单：[macOS Browsers Passkeys](https://developer.apple.com/contact/request/macos-browsers-passkeys/)（文档页上的链接；勿走通用 system-extension 申请页）。
- 另一条官方路径：Certificates, Identifiers & Profiles → 选中对应 **App ID** → **Capability Requests** → 找到该项 → Request → 填表。提交后同一页可看 Status。

### 苹果写明的硬门槛（缺一可能拒）

1. Info.plist 声明能处理 **HTTP 与 HTTPS** 方案。
2. 启动后提供：**地址栏**、**搜索**，或 **整理过的书签列表**（三者满足其一即可）。
3. 打开 HTTP/HTTPS 时，默认配置下应**直接前往目标并渲染该页内容**；不得偷偷改址或改内容（家长控制 / 锁定模式可例外）。

同类产品可做「给苹果审的预览包」：显式注册 http/https、准备可下载的评测构建（社区里 cmux 等走了这条）。**获批前仍禁止**把受限权限写进正式发版 entitlements。

### 对本产品的符合度（申请前现状）

| 门槛 | 现状 |
| --- | --- |
| 声明 http / https | **未满足。** 宿主与运行时 Info.plist 都没有 `CFBundleURLTypes` 注册这两种方案。 |
| 启动入口像浏览器 | **勉强可辩。** 主窗口网页应用列表可按「整理过的书签」表述；没有通用地址栏/搜索。 |
| 打开链接直达目标 | **部分。** 已登记的网页应用会直开对应站；产品不是系统默认浏览器，也不接任意外链。 |
| 产品定位 | 分类是 productivity、菜单栏常驻；对外是「网页应用容器」，不是通用浏览器。 |

### 难度判断（有证据，不是猜）

- **手续不难**：持有人打开专用表、选 App ID、说明产品是 macOS 上的浏览器式应用即可。审期公开 SLA 没有；社区常见「先等几周，没有再催支持」。
- **批下来难，对本产品偏高风险。** Mozilla Thunderbird 正式申请后，苹果以「不符合浏览器要求」拒绝，并指去用系统登录会话；Thunderbird 连 Gecko 内核都有，仍卡在「像不像浏览器」的 UI / 方案声明上。与本产品极像的「多网页应用 WKWebView 外壳」在论坛上也在问申请路径，未见公开获批案例。
- 文字上「整理过的书签」给我们一点辩护空间，但**现缺 http/https 声明 + 非浏览器定位**会明显削弱说服力；为过审去加「可被设为默认浏览器」会改变产品形态，成本远大于填表本身。
- **即便获批，工程成本也不小**：须在苹果网站注册 App ID、启用受管能力、改用带描述文件的签名（当前发版刻意留空 `PROVISIONING_PROFILE_SPECIFIER`）；权限应落在真正跑网页的运行时；还要接通行密钥授权管理，并保留现有降级提示。未批就写入权限会导致签不了 / 启不来。

### 建议

若只想「试试会不会批」：先由 Account Holder 用专用表提交，材料里强调「启动后是整理过的网页应用列表、点开即直达目标站」；可另备带 http/https 声明的评测构建。**不要为申请先改正式发版权限。**  
若目标是「用户在容器里稳定用通行密钥」：把批准当作不确定的外部依赖；在批下来之前，继续引导密码 / 验证码或「用浏览器打开」。

## 参考

- [`com.apple.developer.web-browser.public-key-credential` 权限文档](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
- [申请受管能力（Capability Requests）](https://developer.apple.com/help/account/capabilities/capability-requests/)
- [专用申请表 macOS Browsers Passkeys](https://developer.apple.com/contact/request/macos-browsers-passkeys/)
- [`ASAuthorizationWebBrowserPublicKeyCredentialManager`](https://developer.apple.com/documentation/authenticationservices/asauthorizationwebbrowserpublickeycredentialmanager)
- [苹果工程师说明：WKWebView 的 WebAuthn 仅限关联域名](https://developer.apple.com/forums/thread/714785)
- [DTS：须 Account Holder + 专用表单（非通用 entitlement 表）](https://developer.apple.com/forums/thread/829169)
- [Thunderbird：苹果以「不是浏览器」拒绝后改走系统浏览器登录](https://bugzilla.mozilla.org/show_bug.cgi?id=1864920)
- [passkeys.dev：嵌入式 WebView 与系统 WebView 的能力边界](https://passkeys.dev/docs/reference/macos/)

<!-- 该文档整理/压缩于 2026-09-05；申请流程与难度于 2026-09-10 增补 -->
