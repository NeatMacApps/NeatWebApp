# NeatWebApp

> 一个面向 macOS 15+ 的 SwiftUI/WebKit WebApp 容器原型，参考 NeatEditor 的项目组织方式，并把交互重点放在刘海触发的 launcher 与 100% 内容优先窗口上。

## 愿景

- 参考 MenubarX 的使用感，但更强调内容优先和窗口极简。
- 基于系统浏览器内核 `WKWebView`，保留 Cookie 持久化、页面缩放、基础导航能力。
- 鼠标移入新款 MacBook 刘海区域后，在刘海两侧展开纯黑 launcher。
- 每个 WebApp 都由独立 runtime helper 承载，支持窗口置顶与收起为悬浮图标。

## 当前脚手架已包含

- `XcodeGen` 工程配置，最低支持 `macOS 15.0`
- Swift 6 / Observation 宏风格的应用状态管理
- Host / Runtime 拆分：`NeatWebApp` 负责 launcher 与调度，`NeatWebAppRuntime` 负责网页窗口运行时
- `WKWebView` 容器与基础浏览器 overlay 控件
- 默认 `WKWebsiteDataStore`，用于持久化 Cookie / 网站数据
- 每个 WebApp 独立 runtime 窗口管理、收起为悬浮图标、窗口置顶状态持久化
- 基于 `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 的刘海几何推断
- 基于全局 + 本地鼠标事件监听的 launcher 触发管线
- launcher 横向滚动时基于真实滚动余量动态显示左右边缘渐隐提示
- launcher 图标和悬浮图标优先使用真实网站 favicon
- Host 启动后会刷新 runtime 注册表，并自动接管旧构建的 helper
- 用于验证刘海几何算法的基础单元测试

## 技术栈

| 项目 | 版本 |
|------|------|
| 平台 | macOS 15.0+ |
| 语言 | Swift 6 |
| UI 框架 | SwiftUI |
| 浏览器内核 | WebKit (`WKWebView`) |
| 项目管理 | XcodeGen |

## 开发环境

- Xcode 16.2+
- Swift 6.2+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+

## 快速开始

```bash
cd NeatWebApp
xcodegen generate
open NeatWebApp.xcodeproj
```

命令行构建校验：

```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build test
```

## 项目结构

```text
NeatWebApp/
├── project.yml
├── README.md
├── docs/
│   ├── architecture.md
│   ├── webapp-runtime-isolation-refactor.md
│   └── notch-activation-research.md
├── Sources/
│   ├── NeatWebApp/              # Host：App 入口、launcher、dashboard、runtime 调度
│   ├── NeatWebAppRuntime/       # Helper：浏览器窗口、悬浮图标、运行时入口
│   └── Shared/                  # Host / Runtime 共用模型、IPC、持久化
└── Tests/
    ├── NeatWebAppTests/
    └── NeatWebAppRuntimeTests/
```

## 当前实现假设

- launcher 图标和收起后的悬浮图标都会优先读取真实网站 favicon，缺失时才回退到默认字母图标。
- runtime 默认复用 Host 的 favicon 缓存目录，因此两处图标会命中同一份缓存。
- notch 触发使用 AppKit 暴露的安全区域和辅助区域几何信息推断，不依赖私有 API。
- 当前浏览器窗口按单站点单 runtime 单窗口复用；Host 刷新注册表时会自动接管旧构建的 helper。
- 后续仍可以扩展成多 profile、多 workspace。

## 后续优先级建议

1. 允许用户增删 launcher 中的网站，并把 app catalog 从硬编码迁到持久化配置。
2. 增加 per-site 偏好：UA、权限、默认窗口尺寸、固定位置。
3. 给 launcher 增加 debug overlay，便于微调刘海触发热区。
4. 为旧 helper 自动接管补更多集成验证，再决定是否演进成更强的 agent 化产品。

## 待办事项 (Todo List)

- [ ] 1. **确认 UA 没问题**
- [ ] 2. **WebApps 配置支持删除、排序**：最好改成列表样式
- [ ] 3. **默认打开网页窗口位置**：应该在 notch 和 launcher 的下面
- [ ] 4. **launcher 支持鼠标滚动**
- [ ] 5. **launcher 图标排列居中对齐**：正中间一个图标，其余图标跟这个中间图标对齐。左右滚动时，要保证任意滚动幅度之后都按此方式对齐。
- [ ] 6. **launcher 边缘渐变效果**：因宽度不够显示不完全的图标左右有渐变过渡，且只在对应方向仍可继续滑动时显示。
