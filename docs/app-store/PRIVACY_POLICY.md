# NeatWebApp Privacy Policy

**Effective Date:** November 24, 2026

NeatWebApp is a native macOS web-app container developed by Zhichao Cao.

## Data Collection by NeatWebApp

NeatWebApp does **not** collect, transmit, sell, or share any personal data, usage analytics, crash telemetry, or browsing history.

- **No developer account or backend:** NeatWebApp has no user accounts, cloud synchronization, advertising SDKs, or tracking frameworks.
- **Local-only app data:** Your configured web-app list, window placements, per-app zoom levels, per-app bookmarks, and cached website icons are stored locally on your Mac within the system sandbox container.
- **Isolated website storage:** Each web app uses its own isolated `WKWebsiteDataStore` so cookies and website storage remain separated across apps on your Mac.
- **One-time cookie handoff:** When you explicitly choose **Add WebApp** from a bookmark, cookies for that web app are temporarily staged in your local macOS Keychain for the newly created app and removed immediately after import.

## Third-Party Websites and Permissions

- **Direct connections to websites you open:** Websites you add and browse load directly in Apple WebKit (`WKWebView`) from their respective servers. Any information you submit to those websites is governed by each website’s own privacy policy and terms.
- **Camera and microphone:** Access is requested only when a website initiates a media capture request and only after you grant explicit macOS permission.
- **Downloads and file uploads:** File uploads use the standard macOS file chooser for files you explicitly select. Downloads requested inside a web app are saved directly to your Downloads folder.

## Contact

If you have questions about this Privacy Policy or NeatWebApp, please contact:
- Email: support@caozc.com
- Support: https://github.com/NeatMacApps/NeatWebApp/issues

---

# NeatWebApp 隐私政策

**生效日期：** 2026 年 11 月 24 日

NeatWebApp 是一款由 Zhichao Cao 开发的原生 macOS 网页应用容器。

## NeatWebApp 的数据收集

NeatWebApp **不会**收集、上传、出售或共享任何个人数据、使用统计、崩溃遥测或浏览历史。

- **无开发者账号或后端服务：** NeatWebApp 不提供账号系统、云同步、广告 SDK 或任何追踪框架。
- **应用数据仅保存在本地：** 你添加的网页应用列表、窗口位置、单应用页面缩放、单应用收藏夹以及缓存的网站图标，均仅保存在本机 macOS 沙盒容器内。
- **按应用隔离的网站数据：** 每个网页应用使用独立的 `WKWebsiteDataStore`，使各应用之间的 Cookie 与网站存储在本机保持隔离。
- **一次性 Cookie 交接：** 当你主动通过收藏菜单选择「添加 WebApp」时，当前应用的 Cookie 会临时存入本机 macOS 钥匙串供新创建的应用导入，并在导入后立即清除。

## 第三方网站与系统权限

- **直连你打开的网站：** 你添加并浏览的网站直接通过 Apple WebKit（`WKWebView`）从对应站点加载；你在这些网站中输入或提交的数据受各网站自身的隐私政策与条款约束。
- **摄像头与麦克风：** 仅在网页主动发起媒体采集请求并经你明确同意系统授权后才会启用。
- **文件下载与上传：** 网页上传仅通过系统文件选择器访问你明确选中的文件；网页触发的下载会保存到你的「下载」文件夹。

## 联系方式

如对本隐私政策或 NeatWebApp 有任何疑问，请联系：
- 邮箱：support@caozc.com
- 支持页：https://github.com/NeatMacApps/NeatWebApp/issues
