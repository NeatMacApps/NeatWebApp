# Architecture

## Design Goals

- 内容优先：Web 内容尽量铺满窗口，控制条以 overlay 形式存在。
- AppKit 只负责 SwiftUI 难以直接处理的部分：屏幕几何、全局鼠标事件、窗口级行为。
- Host 只负责 launcher、dashboard、全局状态与 runtime 调度；浏览器窗口和悬浮图标不再运行在 Host 进程。

## Runtime Split

- `NeatWebApp`
  - Host 进程，负责 launcher、dashboard、WebApp 定义、favicon 缓存、runtime 注册表与命令分发。
- `NeatWebAppRuntime`
  - 每个 WebApp 一个 helper 进程，负责 `WKWebView`、内容窗口、收起/展开动画和悬浮图标。
- `Sources/Shared`
  - Host / runtime 共用的运行时模型、状态持久化、IPC、锁文件与窗口摆放辅助代码。

## High-Level Flow

1. `AppModel` 启动时恢复 launcher 状态、加载网站定义和 favicon 缓存，并刷新 runtime 注册表。
2. 用户从 launcher 打开网站时，Host 侧通过 `WebAppRuntimeCoordinator` 查询当前 `appID` 是否已有活跃 runtime。
3. 若不存在活跃 runtime，Host 会写入 `RuntimeBootstrap` 并由 `RuntimeLauncher` 启动新的 `NeatWebAppRuntime` helper。
4. Runtime 读取 bootstrap 后创建 `BrowserSession`、`WebAppWindowController`，并持续写入 `RuntimeState` 与分布式事件。
5. Host 根据 runtime 状态变化更新 launcher 高亮、菜单命令和旧 helper 自动接管逻辑。

## Layers

### App

- `NeatWebAppApp.swift`
  - 创建主 Dashboard 窗口
  - 注入 `AppModel`
  - 注册菜单命令
- `NeatWebAppRuntimeApp.swift`
  - 作为 helper app 入口
  - 读取 `RuntimeBootstrap`
  - 交给 runtime 侧窗口协调器创建单个网页 app 运行时

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
  - 协调 notch monitor、overlay controller、runtime coordinator
- `NotchActivationMonitor`
  - 同时注册 local/global mouse monitor
- `LauncherOverlayController`
  - 管理非激活式 launcher panel
- `WebAppRuntimeCoordinator`
  - 按 `appID` 管理 runtime 注册表、命令分发和旧 helper 迁移
- `RuntimeLauncher`
  - 负责生成 bootstrap 并启动 `NeatWebAppRuntime`
- `RuntimeRegistryStore`
  - 负责 bootstrap/state 落盘、读取和 stale runtime 清理
- `RuntimeCommandBus`
  - 封装 host/runtime 之间的分布式通知命令与事件通道
- `WebAppPreferencesStore`
  - 持久化页面缩放、窗口置顶、窗口 frame
- `WebAppFaviconStore`
  - 统一 favicon 缓存目录；runtime 默认复用 Host 的缓存位置

### Features

- `Dashboard`
  - 当前阶段用于调试、验证几何与快速打开 WebApp
- `Launcher`
  - 刘海两侧展开的 launcher UI
  - 横向溢出时根据真实滚动位置动态显示左右边缘渐隐反馈
- `Browser`
  - `BrowserSession`、`BrowserWebView`、`BrowserContainerView` 现由 runtime target 持有

## Floating Icon Lifecycle

- 网页窗口收起发生在 runtime 内部的 `WebAppWindowController`，Host 只观察状态变化，不直接参与窗口层切换。
- `FloatingIconSnapResolver` 负责把悬浮图标吸附到屏幕上边缘，`FloatingWebAppIconView` 负责点击展开和拖拽移动。
- 悬浮图标素材优先读取 `WebAppFaviconStore` 的站点 favicon；若尚未缓存，再回退到基于站点首字母的默认图标。
- Runtime 默认复用 Host 的 favicon 缓存目录，因此 launcher 图标和收起后的悬浮图标读取的是同一份缓存。
- Host 刷新注册表时如果发现 runtime helper 构建版本过旧，会终止旧 helper 并带着原有窗口状态和悬浮图标位置重启。

## Why WKWebView Instead of Newer WebKit-Only Swift Types

- 当前 Xcode 26 SDK 中确实已经出现了新的 Swift-first `WebPage` API。
- 但它要求更高平台版本，无法覆盖本项目的 `macOS 15` 最低支持目标。
- 因此底层仍然选择 `WKWebView`，上层则用 Swift 6 Observation、现代 SwiftUI 组织代码。

## Next Refactors

1. 把 launcher app catalog 从硬编码迁移到 JSON / 用户配置。
2. 为 `BrowserSession` 引入站点权限模型。
3. 将 overlay panel 的 hover 保活从 frame 判断升级为真正的 tracking area。
4. 为旧 runtime helper 自动接管补一层集成验证，并继续完善多显示器恢复策略。
