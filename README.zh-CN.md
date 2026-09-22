**语言：** [English](README.md) | 简体中文

# NeatWebApp

<p align="center">
  <img src="docs/images/app-icon.png" width="128" height="128" alt="NeatWebApp 应用图标">
</p>

**把常用网站装成独立的 macOS 应用。** 每个网站一扇窗、一份 Cookie 和数据，鼠标往刘海上一停就能打开——没有标签页，也没有浏览器边框碍事。

**需要 macOS 15 或更高版本，Apple 芯片或 Intel。** MIT 开源。网站和数据只留在这台 Mac 上——没有账号、没有同步。

<!-- 截图：将启动器、浏览器窗口、管理窗存入 docs/images/ 后取消注释
<p align="center">
  <img src="docs/images/launcher.png" width="360" alt="NeatWebApp 刘海启动器，列出已装网站">
  <img src="docs/images/browser.png" width="360" alt="NeatWebApp 浏览器窗口，显示某个网站">
</p>
<p align="center">
  <img src="docs/images/dashboard.png" width="480" alt="NeatWebApp 管理窗，管理网站与设置">
</p>
-->

## 安装

### Homebrew（推荐）

```sh
brew tap x0c/tap
brew install --cask neatwebapp
```

### 直接下载

从 [Releases](https://github.com/NeatMacApps/NeatWebApp/releases/latest) 页面下载最新的**已签名并公证**的 `NeatWebApp-x.y.z.dmg`，把 NeatWebApp 拖进「应用程序」即可。

NeatWebApp 会自动检查更新（内置 [Sparkle](https://sparkle-project.org)）；菜单栏菜单里也有「检查更新…」入口。

### 从源码构建

需要 Xcode 16.2+ 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```sh
git clone https://github.com/NeatMacApps/NeatWebApp.git
cd NeatWebApp
xcodegen generate
xcodebuild -project NeatWebApp.xcodeproj -scheme NeatWebApp -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
rm -rf /Applications/NeatWebApp.app
ditto build/DerivedData/Build/Products/Release/NeatWebApp.app /Applications/NeatWebApp.app
open /Applications/NeatWebApp.app
```

NeatWebApp 常驻菜单栏，没有程序坞图标。鼠标停到刘海（无刘海屏幕停到顶部中央热区）即打开启动器。

## 用法

1. 点启动器上的 **+** 打开管理窗，加网站：名字加网址。
2. 鼠标停到刘海打开启动器，点网站，用一扇独立窗口打开。
3. 每个网站有自己独立的 Cookie、本地存储、缩放和收藏，和浏览器、和其他网站互不串味。
4. 把窗口拖到屏幕外大半，它会收进侧边栏；点侧边栏图标再叫回来。

## 功能

- 刘海启动器：悬停即现，点击即开；无刘海屏幕有顶部中央热区
- 隔离的浏览器窗口：Cookie、存储、缩放、收藏按网站隔离存放
- 收起窗口用的侧边栏，可沿屏幕边缘拖动摆放
- 按网站隐藏页面元素、下载自动存并可在访达中查看、文件上传与摄像头/麦克风授权
- 菜单栏常驻，Sparkle 自动更新，无程序坞图标

## 支持的平台

macOS 15 或更高版本，Apple 芯片或 Intel。没有 Windows、Linux、iOS 或网页版——NeatWebApp 用的 WebKit 与 AppKit 能力只有 Mac 上有。

## 明确不做

标签页浏览、扩展、多配置、云同步、共享浏览会话、App Store 版、网站目录的导入导出（目录目前只存在应用本地存储里）。

## 许可证

[MIT](LICENSE)
