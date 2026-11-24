# NeatWebApp Mac App Store Submission Pack

Ready-to-paste metadata, compliance notes, and build/upload/submission commands for the Mac App Store edition (`NeatWebAppAppStore`: single-process multi-window, sandboxed, no Sparkle, no element hiding).

## 1. Frozen Identifiers (Do Not Change After First Upload)

| Field | Value | Notes |
|---|---|---|
| Platform | `macOS` (add `iOS` later if adopting Universal Purchase) | Bundle ID registered as `UNIVERSAL` |
| Bundle ID Resource ID | `X34X8FUH4W` | Created 2026-11-24 via `asc bundle-ids create` |
| Bundle ID | `com.caozc.NeatWebApp` | Distinct from direct build `com.geraltgraham.NeatWebApp` |
| SKU | `neatwebapp` | Immutable after App creation |
| Primary Language | English (U.S.) | Add Simplified Chinese (`zh-Hans`) localization |
| Pricing | Free (No IAP in v1) | |
| Release Option | **Manually release this version** | Stops at `Pending Developer Release` after approval |

## 2. Storefront & Compliance Selections

- **Availability**: Uncheck **China mainland** for v1 (add later after ICP filing without rebuilding). Uncheck **"Make available in all future countries or regions"**.
- **EU DSA**: Declare non-trader if eligible for a free non-commercial app, or unselect EU storefronts to avoid publishing personal contact details.
- **Made for Kids**: **Unchecked** (irreversible once approved).
- **Age Rating**:
  - Answer **Yes** to **Unrestricted Web Access** (NeatWebApp lets users add and open arbitrary URLs in `WKWebView`).
  - Set all other content declarations to **None / No**, including the required **Shared Location = No** and **Dating & Relationships = No** fields.
- **App Privacy**: **No, we do not collect data from this app**.
- **Export Compliance**: `ITSAppUsesNonExemptEncryption` is set to `NO` in `Sources/NeatWebAppAppStore/Info-AppStore.plist`.

## 3. Store Listing Copy

> Accurately describes only capabilities present in the Mac App Store build (no element hiding, no Sparkle, no per-site Dock icon claim).

### English (U.S.)
- **Name**: `NeatWebApp`
- **Subtitle**: `Web apps from the notch` (23 chars)
- **Promotional Text**: `Turn everyday websites into focused native macOS windows launched from the notch, with isolated storage and an edge-tucking activity Dock.`
- **Description**:
  > NeatWebApp turns the websites you rely on every day into focused macOS windows—without cluttering your system Dock.
  >
  > - **Notch launcher**: Hover the MacBook notch (or the top-center hot zone on external and non-notched displays) to reveal your saved websites immediately.
  > - **Floating activity Dock**: Drag a window mostly off-screen and it tucks itself into a compact floating glass Dock. Click an icon to bring the same window back, or right-click to close that site.
  > - **Separate website data**: Each web app uses its own persistent, isolated WebKit data store for cookies and site storage—so work and personal accounts stay apart. Page zoom, window pinning, and bookmarks are saved per web app.
  > - **Create a site from a bookmark**: Right-click any saved bookmark inside a window and choose Add WebApp to spin up another isolated instance with a one-time copy of its cookies.
  > - **Native WebKit essentials**: Clean borderless top chrome, desktop/mobile user-agent toggle, Finder download management, native file uploads, printing, and per-site camera and microphone permissions.
  > - **Local-first & private**: No developer account, no cloud sync, no ads, and no tracking. Your site list and website data stay on your Mac.
- **Keywords**: `site wrapper,browser window,menubar launcher,activity dock,isolated cookies,session,productivity` (96 chars; zero overlap with Subtitle)
- **Support URL**: `https://github.com/NeatMacApps/NeatWebApp/issues`
- **Privacy Policy URL**: `https://github.com/NeatMacApps/NeatWebApp/blob/main/docs/app-store/PRIVACY_POLICY.md`

### 简体中文 (`zh-Hans`)
- **名称**: `NeatWebApp`
- **副标题**: `从刘海随手启动网页应用`
- **宣传文本**: `把常用网站变成专注的原生 macOS 窗口，从刘海一键呼出，支持站点数据隔离与自动贴边活动 Dock。`
- **描述**:
  > NeatWebApp 把你每天用到的网站变成专注的原生 macOS 窗口，不再淹没在杂乱的浏览器标签页中。
  >
  > - **刘海启动器**：鼠标轻触 MacBook 刘海（外接显示器或无刘海屏幕可使用顶部中央虚拟热区），随时展开你的常用网站。
  > - **悬浮活动 Dock**：将网页窗口大部分移出屏幕边缘时，它会自动收进通透的悬浮活动 Dock；轻点图标即可瞬间还原，右键可关闭对应网页应用。
  > - **独立网站数据**：每个网页应用拥有独立且持久化的 WebKit 存储空间，轻松分隔工作与个人账号；缩放比例、窗口置顶和收藏夹均按应用独立保存。
  > - **从收藏创建独立实例**：在窗口「收藏夹」中右键任意收藏条目并选择「添加 WebApp」，即可基于当前 Cookie 的一次性副本创建全新隔离实例。
  > - **原生 WebKit 体验**：简洁无界顶部控件、桌面/移动标识切换、下载进度与访达定位、原生文件上传、打印，以及按需授权的摄像头和麦克风支持。
  > - **本地优先、隐私纯净**：无需登录，无云端同步，无广告与追踪，你的站点配置与浏览数据只保留在自己的 Mac 上。
- **关键词**: `网站封装,独立浏览器,账户隔离,活动Dock,菜单栏工具,高效办公,多开`

## 4. App Review Notes

> NeatWebApp is a sandboxed WebKit web-app container with no developer user account, no analytics, and no in-app purchases.
>
> How to test:
> 1. Launch NeatWebApp. It runs as a menu bar utility until you open a web app. Click the menu bar icon (or hover the MacBook notch / top-center edge of the display; press Command+, or choose Settings from the menu bar to manage sites and enable the virtual notch on non-notched displays).
> 2. Open any built-in example web app or click "+" in the launcher to add a website URL.
> 3. Each web app opens in its own WebKit window with isolated cookies/storage (`WKWebsiteDataStore(forIdentifier:)`). Use the top-left buttons to collapse the window into the floating Activity Dock, pin it on top, or bookmark the current page.
> 4. Drag the window mostly off-screen (at least 80% hidden) to observe automatic collapse into the floating Activity Dock; click its icon in the Activity Dock to restore it.
> 5. Open the top-right More Actions menu (`⋮`) to view Bookmarks (right-click a bookmark -> Add WebApp to create a second isolated instance with copied cookies), reload, or switch Desktop/Mobile User-Agent.
>
> Entitlement justifications:
> - `com.apple.security.network.client`: Required by WKWebView and web browsing.
> - `com.apple.security.files.downloads.read-write`: Saves files downloaded by users inside websites directly to their Downloads folder with a live progress popover and "Show in Finder".
> - `com.apple.security.files.user-selected.read-write`: Supports standard macOS open panels (`NSOpenPanel`) for website file uploads.
> - `com.apple.security.device.camera` & `com.apple.security.device.audio-input`: Passed through to websites only when the user explicitly grants permission in a video call or voice tool.
> - `com.apple.security.print`: Supports printing the current web page (`Command+P`).

## 5. Build, Audit & Upload Commands

### Step 1: Web-Only Actions in App Store Connect (One-Time Setup)
1. **Apps → `+` → New App**: Platform `macOS`, Name `NeatWebApp`, Primary Language `English (U.S.)`, Bundle ID `com.caozc.NeatWebApp`, SKU `neatwebapp`.
2. **App Privacy**: Enter Privacy Policy URL, select `No, we do not collect data from this app`, Save, and **Publish**.

### Step 2: Local Universal Build, Audit & Upload
```bash
# Export ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID from your local App Store Connect API credentials first.
cd app-macos
xcodegen generate

# Universal Release archive for Mac App Store
xcodebuild -project NeatWebApp.xcodeproj \
  -scheme NeatWebAppAppStore \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath build/app-store/DerivedData.noindex \
  -archivePath build/app-store/NeatWebApp.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  archive
```

Create `build/app-store/ExportOptions-Upload.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>upload</string>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>SHZQ3MWP3B</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
```

Upload:
```bash
xcodebuild -exportArchive \
  -archivePath build/app-store/NeatWebApp.xcarchive \
  -exportOptionsPlist build/app-store/ExportOptions-Upload.plist \
  -exportPath build/app-store/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

### Step 3: Metadata & Submission via `asc`
After creating the App record in Step 1, fetch `APP_ID`, `VERSION_ID`, and localization IDs, configure metadata/screenshots (including Unrestricted Web Access = Yes and `sharedLocation`/`datingAndRelationships` = No), attach the processed build, run `asc validate --app "$APP_ID" --version-id "$VERSION_ID"`, test on TestFlight, and submit via `asc review submit --app "$APP_ID" --platform MAC_OS --version-id "$VERSION_ID" --build-id "$BUILD_ID" --confirm`.
