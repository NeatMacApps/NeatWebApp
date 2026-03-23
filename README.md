# NeatWebApp

> 一个面向 macOS 15+ 的 SwiftUI/WebKit WebApp 容器原型，参考 NeatEditor 的项目组织方式，并把交互重点放在刘海触发的 launcher 与 100% 内容优先窗口上。

## 愿景

- 参考 MenubarX 的使用感，但更强调内容优先和窗口极简。
- 基于系统浏览器内核 `WKWebView`，保留 Cookie 持久化、页面缩放、基础导航能力。
- 鼠标移入新款 MacBook 刘海区域后，在刘海两侧展开纯黑 launcher。
- 每个 WebApp 都可以独立开窗，并支持窗口置顶。

## 当前脚手架已包含

- `XcodeGen` 工程配置，最低支持 `macOS 15.0`
- Swift 6 / Observation 宏风格的应用状态管理
- `WKWebView` 容器与基础浏览器 overlay 控件
- 默认 `WKWebsiteDataStore`，用于持久化 Cookie / 网站数据
- 每个 WebApp 独立窗口管理与置顶状态持久化
- 基于 `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 的刘海几何推断
- 基于全局 + 本地鼠标事件监听的 launcher 触发管线
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
│   └── notch-activation-research.md
├── Sources/
│   └── NeatWebApp/
│       ├── App/                 # App 入口、命令菜单、Info.plist
│       ├── Models/              # WebApp 定义、刘海几何模型
│       ├── Services/            # overlay/window/事件监控/偏好持久化
│       ├── Features/
│       │   ├── Browser/         # Browser session、WebView bridge、内容窗口
│       │   ├── Dashboard/       # 调试和配置首页
│       │   └── Launcher/        # 刘海 launcher 视图
│       └── Assets.xcassets
└── Tests/
    └── NeatWebAppTests/
```

## 当前实现假设

- 当前 launcher 图标先用 SF Symbols 占位，后续再替换为真实网站 favicon。
- notch 触发使用 AppKit 暴露的安全区域和辅助区域几何信息推断，不依赖私有 API。
- 当前浏览器窗口先支持单站点单窗口复用；后续可以扩展成多 profile、多 workspace。

## 后续优先级建议

1. 接 favicon 管线，并允许用户增删 launcher 中的网站。
2. 增加 per-site 偏好：UA、权限、默认窗口尺寸、固定位置。
3. 给 launcher 增加 debug overlay，便于微调刘海触发热区。
4. 再决定是否演进成 menu bar agent / LSUIElement 风格产品。

## 待办事项 (Todo List)

- [ ] 1. **确认 UA 没问题**
- [ ] 2. **WebApps 配置支持删除、排序**：最好改成列表样式
- [ ] 3. **默认打开网页窗口位置**：应该在 notch 和 launcher 的下面
- [ ] 4. **launcher 支持鼠标滚动**
- [ ] 5. **launcher 图标排列居中对齐**：正中间一个图标，其余图标跟这个中间图标对齐。左右滚动时，要保证任意滚动幅度之后都按此方式对齐。
- [ ] 6. **launcher 边缘渐变效果**：因宽度不够显示不完全的图标左右有渐变过渡，提示用户可滑动。
