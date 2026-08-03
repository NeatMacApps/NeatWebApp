<!-- managed:inherited-agents:start -->
<!-- source: /Users/geraltgraham/Codes/NeatWebApp/AGENTS.md -->
# NeatWebApp

macOS WebApp 容器（SwiftUI + AppKit + WebKit）。

通用工程规范：[Swift 规范](../_standards/swift.md)

## 文档导航

- [app-macos/AGENTS.md](app-macos/AGENTS.md)：改、评审或排查 WebApp 容器功能前必读。

<!-- managed:inherited-agents:end -->

# AGENTS.md
本文件是 NeatWebApp 仓库内 agent 的工作手册。
在本仓库中工作时，优先遵守这里的约定，再结合通用编码常识执行。

## 工作区规范引用

在阅读本文件的同时，也要先参考 Swift 工作区级规范：[../../_standards/swift.md](../../_standards/swift.md)。

**通用的代码风格（导入 / 格式化 / 命名 / 建模 / 并发 / 错误处理 / 注释 / 依赖）、macOS 应用的构建与覆盖安装验证闭环、以及 Linux 侧无法编译时的处理方式，均以工作区规范为准，本文件不再重复。** 本文件只写 NeatWebApp 专有的结构、命令、产品约定与实现提示。

如果项目内规则与外层工作区规则有冲突，以当前仓库内的 `AGENTS.md` 为准；外层文档作为通用基线。

## 适用范围
- 平台：macOS 15.0+
- 语言：Swift 6
- UI：SwiftUI + AppKit bridge
- 浏览器内核：WebKit（`WKWebView`）
- 工程管理：XcodeGen（`project.yml`）
- Xcode：16.2+

## 已检查的额外规则文件
- 已检查 `.cursor/rules/`：未找到规则文件。
- 已检查 `.cursorrules`：未找到规则文件。
- 已检查 `.github/copilot-instructions.md`：未找到规则文件。
- 因此当前仓库没有额外的 Cursor/Copilot 本地规则；本文件即仓库内 agent 约定的主要来源。

## 仓库结构
- `project.yml`：XcodeGen 配置，是工程结构的真实来源。
- `NeatWebApp.xcodeproj`：生成产物；除非 `project.yml` 无法表达，否则不要手改。
- `Sources/NeatWebApp/App`：应用入口、Scene、菜单命令、Info.plist。
- `Sources/NeatWebApp/Models`：WebApp 定义、刘海几何模型、launcher 与侧边 Dock 布局上下文。
- `Sources/NeatWebApp/Services`：应用状态、overlay/window 协调、事件监控、偏好持久化。
- `Sources/NeatWebApp/Features/Launcher`：刘海 launcher 相关 UI。
- `Sources/NeatWebApp/Features/SideDock`：侧边刘海 Dock、整块拖动与收纳图标 UI。
- `Sources/NeatWebApp/Features/Settings`：宿主级设置 UI。
- `Sources/NeatWebApp/Features/Browser`：浏览器会话、窗口内容、WebKit bridge。
- `Sources/NeatWebApp/Features/Dashboard`：当前阶段的调试/配置首页。
- `Tests/NeatWebAppTests`：宿主侧单元测试（屏幕几何、持久化、catalog）。
- `Tests/NeatWebAppRuntimeTests`：运行时侧单元测试（浏览器 chrome、下载与外链策略、历史位置兼容、窗口自动收起判定）。

## 动手前
- 先读相关文件，不要凭猜测做大改。
- 仅修改与任务直接相关的文件，避免顺手重构无关代码。
- 如果改动影响 `project.yml`，必须重新生成工程。
- 所有代码改动完成后，必须重新编译。
- 如果改动影响运行流程、窗口行为、launcher、浏览器交互或状态持久化，必须将新构建出的 App 替换到 `/Applications/NeatWebApp.app` 后再启动验证。
- 本仓库要求的默认收尾不是“只 build 不运行”，而是“build，然后启动 app 验证新产物至少能拉起”。

## 常用命令
### 工程生成
```bash
xcodegen generate
```
- 在修改 `project.yml`、新增/删除源文件、调整 target/scheme 后必须运行。
- 当前环境已验证 `xcodegen` 可用，版本为 `2.44.1`。

### 构建
```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData.noindex build
```
- 这是当前仓库最可靠的编译检查方式。
- 固定使用 `build/DerivedData.noindex`，便于后续启动 App 和排查产物，同时避免编译副本被 Spotlight 元数据索引。
- `.noindex` 不能代替 LaunchServices 清理；共享 Scheme 的构建后动作必须继续注销主程序、独立 Runtime 和内嵌 Runtime 三个编译产物。改 Scheme、安装流程或应用标识时先读 [系统搜索重复 App 与图标缓存排查记录](docs/troubleshooting/2026-07-26-spotlight-duplicate-app-and-icon-cache.md)。

### 测试
全量测试：
```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData.noindex test
```

构建并测试：
```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData.noindex build test
```

单个测试类：
```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData.noindex -only-testing:NeatWebAppTests/ScreenNotchGeometryTests test
```

### 发版
```bash
scripts/publish-release.sh              # 完整发版
scripts/publish-release.sh --local-only # 只产出本地已公证的 dmg，不碰 git 与 Forgejo
```
- 构建、签名、公证、装订、打 dmg、生成签名更新清单、提交打 tag、两仓发布、匿名终检全在里面，可重复执行。
- 发版前只改 `project.yml` 里的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`（两个 `Info.plist` 都从这里取值）；构建号只增不减，不递增就等于用户端永远提示「已是最新」。
- 只能在 macOS 本机跑；细节与首次发版的人工前置步骤见 [docs/design/release-and-auto-update.md](docs/design/release-and-auto-update.md)。

### 分析 / 近似 lint
```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' analyze
```
- 本仓库没有 lint 配置，`xcodebuild ... analyze` 是最接近 lint 的手段（工作区通例）。

### 运行 App
先执行上面的构建命令，然后关闭旧进程，用新构建产物替换 `/Applications/NeatWebApp.app`，再从 `/Applications` 启动：
```bash
pkill -x "NeatWebApp" || true
rm -rf "/Applications/NeatWebApp.app"
ditto "build/DerivedData.noindex/Build/Products/Debug/NeatWebApp.app" "/Applications/NeatWebApp.app"
for attempt in 1 2 3; do
    if open "/Applications/NeatWebApp.app"; then
        break
    fi
    if [ "$attempt" -eq 3 ]; then
        echo "Failed to launch NeatWebApp after 3 attempts" >&2
        exit 1
    fi
    sleep 1
done
```
- 对 UI、窗口行为、launcher、浏览器导航、缩放、置顶、偏好持久化做了修改时，优先执行这组命令验证。
- 要对 WebApp 窗口截图验证时，必须让该窗口处于激活状态再截：窗口被终端等其他窗口遮住就会触发自动收进侧边 Dock，随后窗口列表里直接消失，表现为「截不到窗口」而不是截图出错。

## 项目专有约定

> 通用代码风格见工作区规范，此处只列 NeatWebApp 独有的要求。

### SwiftUI / AppKit / WebKit 约定
- 修改应用入口或命令菜单时，同时检查 `Sources/NeatWebApp/App/NeatWebAppApp.swift` 与 `Sources/NeatWebApp/App/AppCommands.swift`。
- App 图标与菜单栏图标共享“三层卡片落入带凹口托盘”的品牌语义：菜单栏版本必须保留三层卡片、托盘凹口和必要负空间，禁止把彩色 App 图标直接灰度化、阈值化或整块填黑。模板图的通用规格与验收步骤见 [Apple 应用图标与品牌资产基线](../../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md)。
- 修改 launcher 行为时，同时检查 `Sources/NeatWebApp/Services/AppModel.swift`、`Sources/NeatWebApp/Services/LauncherOverlayController.swift`、`Sources/NeatWebApp/Services/NotchActivationMonitor.swift`。
- 修改侧边 Dock 行为时，同时检查宿主状态、侧边 Dock 窗口协调、布局模型、设置持久化和对应测试；Dock 必须贴在当前屏幕的可用边界，不能覆盖系统程序坞或抢占其触发边缘。
- 侧边 Dock 选屏**禁止使用 `NSScreen.main`**（它是键盘焦点所在屏，不是主显示器，会导致 Dock 跟着焦点在多显示器之间乱跳）；兜底一律用 Dock 当前所在屏或屏幕列表第一块。Dock 图标不画焦点描边。详见 [侧边 Dock 跨显示器跳动排查记录](docs/troubleshooting/2026-08-01-side-dock-jumps-between-displays.md)。
- launcher 图标行两侧的 fade / 阴影反馈必须与真实可滚动方向一致：某一侧还有被裁切内容时保留该侧过渡，某一侧已经滑到尽头时关闭该侧过渡，避免给出错误提示。
- launcher 图标必须保持固定紧凑间距；1、2、3、4 个图标以及更多图标的默认排布都不要按剩余宽度做均分拉伸，禁止出现为了“铺满”而把中间间隔拉得很大的排布。
- 修改刘海识别逻辑时，同时检查 `Sources/NeatWebApp/Models/ScreenNotchGeometry.swift` 和相关测试。
- 无刘海屏幕（外接显示器、Mac mini / Studio、旧款 MacBook）由虚拟刘海兜底：顶部中央合成一块与硬件刘海同构的热区，指针停留约 260ms 才展开，热区内的点击让给菜单栏。改虚拟刘海几何、悬停判定、开关或诊断文案前先读 [刘海触发说明](docs/notch-activation-research.md)，里面记了「屏幕刷新无差别取消悬停等待会让虚拟热区彻底失灵」这个坑，以及覆盖层无法用截图 skill 验证时的替代手法。
- 修改浏览器行为时，同时检查 `Sources/NeatWebApp/Features/Browser/BrowserSession.swift`、`Sources/NeatWebApp/Features/Browser/AppKitBridge/BrowserWebView.swift`、`Sources/NeatWebApp/Services/WebAppWindowController.swift`。
- 浏览器窗口顶部是无边框的「让位带」，不是标题栏：不画横条与分割线，图标裸放，网页内容从带子下方开始。改这块前先读 [浏览器顶栏无界样式](docs/design/browser-top-chrome.md)，里面记了液态玻璃胶囊、悬停淡入等已被推翻的方案和推翻理由。
- 修改网站数据、缩放、置顶、窗口恢复时，要连同偏好持久化一起验证。

## 与当前代码保持一致的实现提示
- launcher 的顶层状态由 `AppModel` 驱动。
- 刘海检测基于 `NSScreen.safeAreaInsets`、`auxiliaryTopLeftArea`、`auxiliaryTopRightArea` 的组合推断。
- 鼠标触发目前由 `NSEvent` 的 global/local monitor 组合实现。
- 浏览器容器当前基于 `WKWebView`，并使用 `WKWebsiteDataStore.default()` 做站点数据持久化。
- 页面缩放当前走 `WKWebView.pageZoom`。
- 浏览器级快捷键（刷新、前进后退、缩放、打印、关闭窗口等）由 `Sources/NeatWebApp/Features/Browser/BrowserKeyCommand.swift` 映射、在 WebView 的 `performKeyEquivalent` 阶段消费。运行时是 `LSUIElement`，永远没有菜单栏，不要试图用菜单项挂浏览器快捷键；也不要下沉到 `keyDown`，网页输入框会先把按键吃掉。新增绑定前先读 [docs/architecture.md](docs/architecture.md) 里的快捷键表，确认不会抢走网页自己的编辑按键。
- 每个 WebApp 运行时进程只拥有一个浏览器窗口，由 `Sources/NeatWebAppRuntime/Services/RuntimeWindowCoordinator.swift` 协调；同一个 WebApp 无法再开出第二个窗口。
- `Sources/NeatWebApp/Services/WebAppWindowCoordinator.swift` 是历史遗留的死文件：`project.yml` 把它从所有 target 排除，且它调用的构造签名早已不存在。不要参照它写代码；一旦把它加回 target，编译会立刻失败。
- 窗口自动收进侧边 Dock 只有「系统判定窗口看不见」一个触发条件，没有闲置超时收起。改这块前先读 [窗口自动收起设计说明](docs/design/window-auto-collapse.md)。
- 置顶窗口行为通过 `NSWindow.Level.floating` 实现，并由偏好持久化保存。
- 应用内自动更新由 `Sources/NeatWebApp/Services/AppUpdater.swift` 持有，只装在宿主上；更新覆盖安装前会调用 `AppModel.prepareForApplicationUpdate()` 收掉全部运行时进程，漏网的靠既有的运行时版本迁移逻辑在下次启动时重启。改运行时生命周期、`WebAppRuntimeCoordinating` 协议或菜单栏菜单时，一并确认这条链路没断。
- 开机自启由 `Sources/NeatWebApp/Services/LaunchAtLoginService.swift` 封装 `SMAppService.mainApp`，设置窗口与菜单栏各有一个入口。**只有 `.enabled` 才算启用**：`.requiresApproval` 表示这台机器上它曾被关掉过，系统据此挂起，此时**应用无论怎么调都救不回来**——实测「注销后重新登记」同样无效，苹果是故意持久化这个「用户曾关掉它」的意图的，只能由用户去系统设置里重新打开。所以把 `.requiresApproval` 并进「已启用」是错的（会表现为开关看着开着、开机却不启动），在这里加重试也是错的，界面必须如实解释并给出跳系统设置的入口。正常机器上首次开启不需要任何放行，不要把放行写成常规步骤。
- 触碰这些逻辑时，要连同构建、测试、替换 `/Applications/NeatWebApp.app`、再启动验证一起执行。

## Agent 工作方式
- 先读上下文，再改代码。
- 尽量小步提交，避免把“修功能”和“重排格式”混在一起。
- 本仓库的默认收尾比工作区基线更严：任意代码修改都要构建 + 覆盖安装 + 启动验证，不接受「只 build 不运行」。
- 若你改动了测试或新增了测试设施，请同步更新本文件中的命令示例。

## 文档导航

- [../../_standards/workspace-docs/swift-docs/macos-system-permissions.md](../../_standards/workspace-docs/swift-docs/macos-system-permissions.md)：新增全局按键监听、屏幕内容读取、摄像头或通知能力前必读；含权限被拒后的降级引导与开发期授权失效的根因。
- [../../_standards/workspace-docs/swift-docs/apple-app-preferences.md](../../_standards/workspace-docs/swift-docs/apple-app-preferences.md)：新增用户可调设置项、或纠结某个值该存哪之前必读。
- [../../_standards/workspace-docs/swift-docs/liquid-glass-practices.md](../../_standards/workspace-docs/swift-docs/liquid-glass-practices.md)：改、评审或排查本应用任何位置的玻璃与半透明材质前必读；本项目两条玻璃裁定（顶栏不用玻璃、侧边 Dock 底板用玻璃）的通用部分已上收至此，其中还记录了非激活窗口玻璃变暗所依赖的私有方法风险。
- [../../_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md](../../_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md)：改、评审或排查签名、公证、安装包制作、应用内自更新、Homebrew 渠道时的**通用做法与踩坑速查**以此为准；本项目专有取值见下一条，两者不重复。
- [docs/design/release-and-auto-update.md](docs/design/release-and-auto-update.md)：发版、改发版脚本、改版本号、改签名或权限配置、改自动更新行为，或排查「别人机器装不上 / 装了升不了级」前必读；含本项目专有取值（两仓拓扑、为何不需要描述文件、更新签名密钥归属）、双程序签名的额外要求、以及**首次发版前必须人手做的两步**。
- [../../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md](../../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md)：新做、更换、评审或排查应用图标与菜单栏图标前必读；含分层图标新格式的迁移裁定、母版规格、存放约定、模板图硬性要求与验收清单。**本项目的图标成品包与工程内资源目前是同一份资产的两个副本，按该文档应删掉成品包副本。**
- [docs/architecture.md](docs/architecture.md)：改、评审或排查应用架构、模块边界、WebKit/AppKit 协作方式、进程划分，以及浏览器窗口生命周期（关闭 / 隐藏 / 收进侧边 Dock / 跨桌面空间行为）前阅读。
- [docs/design/window-auto-collapse.md](docs/design/window-auto-collapse.md)：改、评审或排查「窗口自动收进侧边 Dock」的触发条件、延时、跨桌面表现、收起后焦点归属、左右侧设置或系统程序坞避让前必读；含已裁定不可推翻的产品决策与真机验收清单。
- [docs/design/browser-top-chrome.md](docs/design/browser-top-chrome.md)：改、评审或排查浏览器窗口顶部控件区（收起 / 置顶 / 刷新 / 网页标识 / 下载指示的排布、顶部让位带高度、渐变、配色与对比度、窗口拖动区域）前必读；也是判断「该不该在窗口内部用液态玻璃 / 系统材质」的依据，含已实现后被推翻的方案与根因，以及顶栏改动的截图验收要求。
- [docs/notch-activation-research.md](docs/notch-activation-research.md)：改、评审或排查刘海触发、屏幕几何识别、launcher 激活逻辑前阅读；无刘海屏幕 / 外接显示器的虚拟刘海热区（几何推导、悬停停留判定、开关偏好、与菜单栏的冲突处理）也在这里，验证覆盖层是否真的唤出时同样先读本文的验证手法一节。
- [docs/webapp-runtime-isolation-refactor.md](docs/webapp-runtime-isolation-refactor.md)：改 WebApp 运行时隔离、窗口复用或站点数据边界前阅读。
- [docs/troubleshooting/2026-07-26-spotlight-duplicate-app-and-icon-cache.md](docs/troubleshooting/2026-07-26-spotlight-duplicate-app-and-icon-cache.md)：安装、构建、改 App 图标，或排查 Spotlight 出现多个 NeatWebApp、图标不刷新、旧副本残留时必读。
- [docs/troubleshooting/2026-08-01-side-dock-jumps-between-displays.md](docs/troubleshooting/2026-08-01-side-dock-jumps-between-displays.md)：改、评审或排查侧边 Dock 的选屏与定位（多显示器下乱跳、拔插显示器后跑偏、Dock 该出现却没出现），或需要在真机上验证 Dock 位置时必读；含 `NSScreen.main` 语义陷阱与验证手法。
