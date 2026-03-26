# Architecture

## Design Goals

- 内容优先：Web 内容尽量铺满窗口，控制条以 overlay 形式存在。
- AppKit 只负责 SwiftUI 难以直接处理的部分：屏幕几何、全局鼠标事件、窗口级行为。
- 状态尽量收束到 `AppModel` 和 `BrowserSession`，便于后续演进为多 profile / 多 workspace。

## Layers

### App

- `NeatWebAppApp.swift`
  - 创建主 Dashboard 窗口
  - 注入 `AppModel`
  - 注册菜单命令

### Models

- `WebAppDefinition`
  - WebApp 基础元数据
- `ScreenNotchGeometry`
  - 将 `NSScreen` 暴露的信息转换成 notch 几何与触发区
- `LauncherPresentationContext`
  - overlay panel 的尺寸与布局上下文

### Services

- `AppModel`
  - 应用主状态
  - 协调 notch monitor、overlay controller、web window coordinator
- `NotchActivationMonitor`
  - 同时注册 local/global mouse monitor
- `LauncherOverlayController`
  - 管理非激活式 launcher panel
- `WebAppWindowCoordinator`
  - 每个 WebApp 一个独立窗口控制器
- `WebAppPreferencesStore`
  - 持久化页面缩放、窗口置顶、窗口 frame

### Features

- `Dashboard`
  - 当前阶段用于调试、验证几何与快速打开 WebApp
- `Launcher`
  - 刘海两侧展开的 launcher UI
  - 横向溢出时根据真实滚动位置动态显示左右边缘渐隐反馈
- `Browser`
  - `BrowserSession`
  - `BrowserWebView`
  - `BrowserContainerView`

## Why WKWebView Instead of Newer WebKit-Only Swift Types

- 当前 Xcode 26 SDK 中确实已经出现了新的 Swift-first `WebPage` API。
- 但它要求更高平台版本，无法覆盖本项目的 `macOS 15` 最低支持目标。
- 因此底层仍然选择 `WKWebView`，上层则用 Swift 6 Observation、现代 SwiftUI 组织代码。

## Next Refactors

1. 把 launcher app catalog 从硬编码迁移到 JSON / 用户配置。
2. 为 `BrowserSession` 引入站点权限模型。
3. 将 overlay panel 的 hover 保活从 frame 判断升级为真正的 tracking area。
4. 为窗口状态增加多显示器恢复和空间恢复策略。
