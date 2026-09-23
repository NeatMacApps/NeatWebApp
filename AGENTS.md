<!-- managed:inherited-agents:start -->
<!-- source: /Users/geraltgraham/Codes/NeatWebApp/AGENTS.md -->
# NeatWebApp

macOS WebApp 容器（SwiftUI + AppKit + WebKit）。

通用工程规范：[Swift 规范](/Users/geraltgraham/Codes/_standards/swift.md)

Remote：`app-macos` → GitHub `NeatMacApps/NeatWebApp`（公开，https://github.com/NeatMacApps/NeatWebApp）；本产品文件夹不是 git 仓库。

## 文档导航

- [app-macos/AGENTS.md](/Users/geraltgraham/Codes/NeatWebApp/app-macos/AGENTS.md)：改、评审或排查 WebApp 容器功能前必读。
- [docs/design/dashboard-settings.md](docs/design/dashboard-settings.md)：改、评审或排查主窗口网页应用目录与内嵌设置布局前必读。

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

## 2026-08-31 菜单栏专项复核：已落地（待 Mac 验收）

已接入公共行为包 MacKit（from **0.1.4**）：开机自启走系统三态（待批准不能显示成已开启），菜单和主窗口设置可隐藏/恢复菜单栏图标。图标隐藏后再次从“应用程序”、Spotlight 打开应唤出主窗口。**【裁定 2026-09-07】** 菜单栏右键有的能力，主窗口设置区必须对等——含唤出启动器、**检查更新**、退出；菜单栏即主入口时，就绪后约 60 秒内再次打开须出主窗（`menubarIsPrimaryEntry`）。公开更新走 Sparkle，不走 `PersonalBuildUpdateChecker`。验收清单见公共包 `docs/MAC_ACCEPTANCE.md`；跨产品权威见 `~/.config/agentsync/docs/MACOS_APP_DEVELOPMENT_GUIDE.md`。

## 仓库结构
- `project.yml`：XcodeGen 配置，是工程结构的真实来源。
- `NeatWebApp.xcodeproj`：生成产物；除非 `project.yml` 无法表达，否则不要手改。
- `Sources/NeatWebApp/App`：应用入口、Scene、菜单命令、Info.plist。
- `Sources/NeatWebApp/Models`：WebApp 定义、刘海几何模型、launcher 与侧边 Dock 布局上下文。
- `Sources/NeatWebApp/Services`：应用状态、overlay/window 协调、事件监控、偏好持久化。
- `Sources/NeatWebApp/Features/Launcher`：刘海 launcher 相关 UI。
- `Sources/NeatWebApp/Features/SideDock`：侧边刘海 Dock、整块拖动与收纳图标 UI。
- `Sources/NeatWebApp/Features/Settings`：设置区块，内嵌在主窗口里，不是独立窗口。
- `Sources/NeatWebApp/Features/Browser`：浏览器会话、窗口内容、WebKit bridge。
- `Sources/NeatWebApp/Features/Dashboard`：主窗口（网页应用列表 + 设置区块）。
- `Tests/NeatWebAppTests`：宿主侧单元测试（屏幕几何、持久化、catalog、侧边 Dock 贴边与拐角换边）。
- `Tests/NeatWebAppRuntimeTests`：运行时侧单元测试（浏览器 chrome、收藏隔离、下载与外链策略、历史位置兼容、窗口自动收起判定、可见面积计算、**侧边 Dock 避让**）。

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
scripts/publish-release.sh --local-only # 只产出本地已公证的 dmg，不碰 git 与 GitHub
```
- 构建、签名、公证、装订、打 dmg、生成签名更新清单、提交打 tag、GitHub Release、appcast 入库、Homebrew cask、匿名终检全在里面，可重复执行。
- 发版前只改 `project.yml` 里的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`（两个 `Info.plist` 都从这里取值）；构建号只增不减，不递增就等于用户端永远提示「已是最新」。
- **【裁定 2026-09-23】工作完成且验证通过后，主动走完「升号 → 发版脚本 → 本机安装核验」全链路，不等用户说「发布」。** 公证排队是外部等待：进后台独立进程、日志可查，确认启动后即汇报，不轮询空等；跑完接着做匿名终检核对与覆盖安装验版本号。
- 只能在 macOS 本机跑；细节与排障「收不到更新」见 [docs/design/release-and-auto-update.md](docs/design/release-and-auto-update.md)。

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
- 启动这一次只为确认进程起来。主窗口是目录+设置，**不是**日常入口（刘海启动器才是）；冷启动不得自己弹出这扇窗。**禁止**马上再 `open` 一次去触发防呆出窗。全局规范见 `~/.config/agentsync/docs/MACOS_APP_DEVELOPMENT_GUIDE.md`「非主入口的配置窗禁止主动打开」。
- 跑宿主侧测试会另外拉起一个测试用宿主进程，和本机已安装的应用是同一个标识：菜单栏图标会闪、正在用的窗口可能被挤掉。要验证「点开网页应用」这类真实启动路径时，用覆盖安装再从 `/Applications` 打开，不要同时跑这组测试。
- 要对 WebApp 窗口截图验证时，必须让该窗口处于激活状态再截：窗口被终端等其他窗口挡住大约八成就会立刻收进侧边 Dock，随后窗口列表里直接消失，表现为「截不到窗口」而不是截图出错。用户正在用的网页窗口可以截；不要为此先打开主窗口/设置区。

## 项目专有约定

> 通用代码风格见工作区规范，此处只列 NeatWebApp 独有的要求。

### SwiftUI / AppKit / WebKit 约定
- 修改应用入口或命令菜单时，同时检查 `Sources/NeatWebApp/App/NeatWebAppApp.swift` 与 `Sources/NeatWebApp/App/AppCommands.swift`。
- **不做独立的设置窗口**：全部应用级设置都放在主窗口里（`Features/Settings` 只提供内嵌区块）。菜单栏、启动器加号、⌘, 三个入口都打开同一个主窗口，窗口标识统一取 `AppWindowID.main`，不要新增第二个窗口标识或恢复 `Settings` scene。
  - **基线 B4 的产品豁免（已登记）**：虽然本应用有三项以上可调设置，但它是“网页应用目录 + 启动器 + 运行时窗口”一体化管理工具，所有设置都直接影响同一主界面的内容和行为；另开设置窗口会把同一条工作流拆散，且会和菜单栏、启动器加号、⌘, 三个既有入口产生重复路径。因此本应用不使用独立 `Settings` scene，统一以主窗口内嵌设置区替代。这个豁免**不**免除 ⌘, 可达、键盘焦点、VoiceOver、持久化与中英本地化要求。
- **主窗口只放用户要操作的东西**：不摆产品介绍、路线图、诊断读数、屏幕几何等开发者信息；设置项的补充说明一律走悬停提示，界面上只留一句话标题。唯一例外是必须解释否则用户会误判的状态（如开机自启被系统挂起）。刷新几何、调试覆盖层这类开发用动作只保留快捷键，不进界面。
- App 图标与菜单栏图标共享“三层卡片落入带凹口托盘”的品牌语义：菜单栏版本必须保留三层卡片、托盘凹口和必要负空间，禁止把彩色 App 图标直接灰度化、阈值化或整块填黑。模板图的通用规格与验收步骤见 [Apple 应用图标与品牌资产基线](../../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md)。
- 修改 launcher 行为时，同时检查 `Sources/NeatWebApp/Services/AppModel.swift`、`AppModel+Launcher.swift`、`Sources/NeatWebApp/Services/LauncherOverlayController.swift`、`Sources/NeatWebApp/Services/NotchActivationMonitor.swift`。
- 修改侧边 Dock 行为时，同时检查宿主状态、侧边 Dock 窗口协调、布局模型、设置持久化和对应测试；Dock 必须贴在当前屏幕的可用边界，不能覆盖系统程序坞或抢占其触发边缘。网页应用窗口也不得挡住这块侧边刘海（不是系统程序坞）：Dock 正在显示时，该屏窗口的可用区域是 `visibleFrame` 再扣掉 Dock 所在边的整条厚度。改、评审或排查「窗口压住侧边 Dock / 玻璃里透出网页」前先读 [窗口自动收起设计说明](docs/design/window-auto-collapse.md) 里 2026-09-01 的裁定。
- 侧边 Dock 上下不留死边距：可以一路拖到贴住可用区域的上下边缘（边距常量在放置解析器里统一管理，不要在别处再写死数值）。贴的是 `visibleFrame`，底部有系统程序坞时自然停在它内侧。
- 侧边 Dock 拖到可用区域拐角后继续拖，会绕到相邻边（左/右 ↔ 底），上边不贴。只在已经顶到尽头且还在拐角附近时才换边，中间朝屏幕内侧拖仍是关闭手势。
- 侧边 Dock 选屏**禁止使用 `NSScreen.main`**（它是键盘焦点所在屏，不是主显示器，会导致 Dock 跟着焦点在多显示器之间乱跳）；兜底一律用 Dock 当前所在屏或屏幕列表第一块。Dock 图标不画焦点描边。详见 [侧边 Dock 跨显示器跳动排查记录](docs/troubleshooting/2026-08-01-side-dock-jumps-between-displays.md)。
- launcher 图标行两侧的 fade / 阴影反馈必须与真实可滚动方向一致：某一侧还有被裁切内容时保留该侧过渡，某一侧已经滑到尽头时关闭该侧过渡，避免给出错误提示。
- launcher 图标必须保持固定紧凑间距；1、2、3、4 个图标以及更多图标的默认排布都不要按剩余宽度做均分拉伸，禁止出现为了“铺满”而把中间间隔拉得很大的排布。
- 修改刘海识别逻辑时，同时检查 `Sources/NeatWebApp/Models/ScreenNotchGeometry.swift` 和相关测试。
- 无刘海屏幕（外接显示器、Mac mini / Studio、旧款 MacBook）由虚拟刘海兜底：顶部中央合成一块与硬件刘海同构的热区，指针停留约 260ms 才展开，热区内的点击让给菜单栏。**硬件刘海也不是一碰就开**：指针移入后等 100ms，仍在区内才弹出启动器，避免路过误开。改虚拟刘海几何、悬停判定、开关或诊断文案前先读 [刘海触发说明](docs/notch-activation-research.md)，里面记了「屏幕刷新无差别取消悬停等待会让虚拟热区彻底失灵」这个坑，以及覆盖层无法用截图 skill 验证时的替代手法。
- 修改浏览器行为时，同时检查 `Sources/NeatWebApp/Features/Browser/BrowserSession.swift`、`Sources/NeatWebApp/Features/Browser/AppKitBridge/BrowserWebView.swift`、`Sources/NeatWebApp/Services/WebAppWindowController.swift`。
- 浏览器窗口顶部是无边框的「让位带」，不是标题栏：不画横条与分割线，图标裸放，网页内容从带子下方开始。左上角是收起、置顶、收藏当前页与这个网页应用自己的收藏列表。改这块前先读 [浏览器顶栏无界样式](docs/design/browser-top-chrome.md)，里面记了液态玻璃胶囊、悬停淡入等已被推翻的方案和推翻理由。
- 注入网页的用户脚本（页面取色、通行密钥提示、元素隐藏）统一在 `BrowserUserScripts.install` 里装配。WebKit 只能整批清空用户脚本、不能单独摘掉一条，新增注入脚本必须加进这个入口，否则隐藏规则变更时重装会把它弄丢。**禁止**再注入「长列表卸屏 / 屏外跳过绘制 / 整树重绑」一类脚本；用户 2026-09-19 已否决。改长页面卡顿前先读 [长页面把窗口卡死](docs/troubleshooting/2026-09-18-long-page-webview-jank.md)。
- 修改网站数据、缩放、置顶、窗口恢复、已隐藏元素、**按网页应用隔离的收藏**时，要连同偏好持久化一起验证；偏好里新增字段一律写成可选，老版本存档缺字段会让整份偏好解码失败。

## 与当前代码保持一致的实现提示
- launcher 的顶层状态由 `AppModel` 驱动。
- 刘海检测基于 `NSScreen.safeAreaInsets`、`auxiliaryTopLeftArea`、`auxiliaryTopRightArea` 的组合推断。
- 鼠标触发目前由 `NSEvent` 的 global/local monitor 组合实现。
- 浏览器容器当前基于 `WKWebView`，并使用**按网页应用隔离**的 `WKWebsiteDataStore(forIdentifier:)` 做站点数据持久化（不是共享的 `default()`）。
- 页面缩放当前走 `WKWebView.pageZoom`。
- 浏览器级快捷键（刷新、前进后退、缩放、打印、关闭窗口等）由 `Sources/NeatWebApp/Features/Browser/BrowserKeyCommand.swift` 映射、在 WebView 的 `performKeyEquivalent` 阶段消费。运行时是 `LSUIElement`，永远没有菜单栏，不要试图用菜单项挂浏览器快捷键；也不要下沉到 `keyDown`，网页输入框会先把按键吃掉。新增绑定前先读 [docs/architecture.md](docs/architecture.md) 里的快捷键表，确认不会抢走网页自己的编辑按键。
- 每个 WebApp 运行时进程只拥有一个浏览器窗口，由 `Sources/NeatWebAppRuntime/Services/RuntimeWindowCoordinator.swift` 协调；同一个 WebApp 无法再开出第二个窗口。
- 用户新打开一个尚未运行的 WebApp 时，宿主立刻用一扇和真窗同框的白窗把启动空白盖住。这不是第二套界面：不要另做顶栏、图标或淡出/缩放交接。真窗必须关掉系统默认的弹出缩放，**等网页第一帧画完再揭盖**；还没画完就揭，会闪一下空窗。盖着的首次出现期间，窗口聚焦也不得揭盖。已经在运行的唤出、从侧边 Dock 展开、后台健康重启都不走这层盖。宿主是菜单栏常驻：不把应用带到前面的话盖子会画在别的应用下面，看起来像没点中。盖子层级必须比真窗高，否则会被当成「挡住了」而把真窗立刻收进侧边栏。**占位与真窗必须是同一框**：宿主只算一次，既用来盖住也原样写进启动参数；运行时禁止再算一遍，也禁止刚出现时再挪位置。**铺满可用桌面的框不能当作用户窗口**：那是系统缩放/贴边，写进记忆会让下次打开先全屏白屏再缩成小窗。真窗挂上网页后必须锁住宿主给的那一框，禁止系统窗口记忆和页面内容反推窗口大小。窗口位置偏好两边读同一份（不能各写各的），否则上次拖过的大小宿主看不见。量默认窗口尺寸用内容尺寸本身（本窗内容铺满外框），禁止为了量尺寸临时建一扇窗再关掉，会在稍后释放对象时闪退。改、评审、优化或排查这条链路（含打开闪一下、盖子和真窗对不齐、先全屏白屏再变成小窗）前**必读** [启动盖](docs/design/launch-cover.md)；机制步骤见 [docs/architecture.md](docs/architecture.md) 的 Launch Flow。不读会把已被否决的闪屏、假顶栏或淡出再做一遍。
- `Sources/NeatWebApp/Services/WebAppWindowCoordinator.swift` 是历史遗留的死文件：`project.yml` 把它从所有 target 排除，且它调用的构造签名早已不存在。不要参照它写代码；一旦把它加回 target，编译会立刻失败。
- 窗口自动收进侧边 Dock 的触发条件是「看不见的面积达到 80%」，立刻收起，没有闲置超时。用户刚从刘海或侧边栏点开/唤出时有短暂保护，避免窗口列表还没跟上就误收。改这块前先读 [窗口自动收起设计说明](docs/design/window-auto-collapse.md)。
- 置顶窗口行为通过 `NSWindow.Level.floating` 实现，并由偏好持久化保存。
- 应用内自动更新由 `Sources/NeatWebApp/Services/AppUpdater.swift` 持有，只装在宿主上；更新覆盖安装前会调用 `AppModel.prepareForApplicationUpdate()` 收掉全部运行时进程，漏网的靠既有的运行时版本迁移逻辑在下次启动时重启。改运行时生命周期、`WebAppRuntimeCoordinating` 协议或菜单栏菜单时，一并确认这条链路没断。**「能否检查更新」必须挂在这个更新器上、整个生命周期只订阅一次**；禁止在检查更新按钮初始化时新建观察对象，否则菜单会被系统反复合成、主线程打满。排障见 `~/.config/agentsync/docs/troubleshooting/2026-09-01-swiftui-menubar-main-thread-spin.md`。
- 开机自启由公共行为包的登录项单元封装，主窗口的设置区与菜单栏各有一个入口。**只有系统真正会在登录时拉起才算启用**：待批准不能显示成已开启，也不能靠注销再登记救回来，只能由用户去系统设置里重新打开。界面必须如实解释并给出跳系统设置的入口。正常机器上首次开启不需要任何放行，不要把放行写成常规步骤。
- 触碰这些逻辑时，要连同构建、测试、替换 `/Applications/NeatWebApp.app`、再启动验证一起执行。

### 当前基线缺口：中英本地化（A3，必须补齐）
- 宿主与内嵌网页运行时目前均没有各自的字符串目录；现有用户文案（包括权限恢复与无障碍标签）仍直接写在代码中，因此尚不具备英文覆盖。**这不是产品豁免，新增或修改用户可见文案前必读** [Apple 应用本地化共享基线](../../_standards/workspace-docs/swift-docs/apple-localization.md)，否则会继续累积不可翻译的文案。
- 后续整改必须为宿主和运行时分别建立语义键字符串目录，不可跨 target 共用；完成前不得把“已有中文文案”误报为双语支持。验收须包含目录无 `new` / `stale`、中英文真机检查和重音/双倍长度伪语言检查。

## Agent 工作方式
- 先读上下文，再改代码。
- 尽量小步提交，避免把“修功能”和“重排格式”混在一起。
- 本仓库的默认收尾比工作区基线更严：任意代码修改都要构建 + 覆盖安装 + 启动验证，不接受「只 build 不运行」。
- 若你改动了测试或新增了测试设施，请同步更新本文件中的命令示例。

## 文档导航

- [docs/design/app-improvement-plan.md](docs/design/app-improvement-plan.md): **Must read before resuming the 2026-09-20 app improvement work** (host quit, partial off-screen placement, downloads/bookmarks, long-page performance, management layout and sorting). Records confirmed causes, proposed behavior, acceptance gates and retained unverified prototypes; do not restart implementation or publish the prototypes merely because this plan exists.

- [../../_standards/workspace-docs/swift-docs/macos-system-permissions.md](../../_standards/workspace-docs/swift-docs/macos-system-permissions.md)：新增全局按键监听、屏幕内容读取、摄像头或通知能力前必读；含权限被拒后的降级引导与开发期授权失效的根因。
- [../../_standards/workspace-docs/swift-docs/apple-app-preferences.md](../../_standards/workspace-docs/swift-docs/apple-app-preferences.md)：新增用户可调设置项、或纠结某个值该存哪之前必读。
- [../../_standards/workspace-docs/swift-docs/apple-localization.md](../../_standards/workspace-docs/swift-docs/apple-localization.md)：新增、修改、评审或排查任何用户可见文案、中英语言覆盖、字符串目录与伪语言验收前**必读**；否则宿主与运行时会继续把不可翻译的字面量写进代码，无法达到 macOS 基线 A3。
- [../../_standards/workspace-docs/swift-docs/liquid-glass-practices.md](../../_standards/workspace-docs/swift-docs/liquid-glass-practices.md)：改、评审或排查本应用任何位置的玻璃与半透明材质前必读；本项目两条玻璃裁定（顶栏不用玻璃、侧边 Dock 底板用玻璃）的通用部分已上收至此，其中还记录了非激活窗口玻璃变暗所依赖的私有方法风险。
- [../../_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md](../../_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md)：改、评审或排查签名、公证、安装包制作、应用内自更新、Homebrew 渠道时的**通用做法与踩坑速查**以此为准；本项目专有取值见下一条，两者不重复。
- [docs/design/release-and-auto-update.md](docs/design/release-and-auto-update.md)：发版、改发版脚本、改版本号、改签名或权限配置、改自动更新行为，或排查「别人机器装不上 / 装了升不了级 / 收不到更新提醒」前必读；含本项目专有取值、温和提醒不弹窗、先核公开 appcast 构建号。
- [../../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md](../../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md)：新做、更换、评审或排查应用图标与菜单栏图标前必读；含分层图标新格式的迁移裁定、母版规格、存放约定、模板图硬性要求与验收清单。**本项目的图标成品包与工程内资源目前是同一份资产的两个副本，按该文档应删掉成品包副本。**
- [docs/architecture.md](docs/architecture.md)：改、评审、优化或排查应用架构、模块边界、WebKit/AppKit 协作、进程划分，或浏览器窗口生命周期（关闭 / 隐藏 / 侧边 Dock / 跨桌面 / 启动盖）前**必读**。不读会把宿主与运行时职责拆错，或把窗口生命周期动作当成结束进程。
- [docs/design/memory-footprint.md](docs/design/memory-footprint.md)：改、评审、优化或排查宿主 / 运行时内存占用、收起后仍偏胖、系统压力下的缓存收缩前**必读**。不读会把卸页 / 关保活进程或自研整页压缩重新做进来，破坏收起秒开与会话保留；压力回调隔离写错还会整进程闪退（见排查索引）。
- [docs/design/launch-cover.md](docs/design/launch-cover.md)：改、评审、优化或排查「新打开尚未运行的网页应用」的启动盖（同框白窗、揭盖时机、打开闪一下、盖子和真窗对不齐、**先全屏白屏再变成小窗**）前**必读**；含已裁定不可推翻的产品决策与已被否决的闪屏 / 假顶栏 / 淡出方案。不读会把第二套界面或交接动画再做一遍。
- [docs/design/window-auto-collapse.md](docs/design/window-auto-collapse.md)：改、评审或排查「窗口自动收进侧边 Dock」的触发条件、延时、跨桌面表现、收起后焦点归属、左右侧设置、系统程序坞避让、**网页窗口挡住本应用侧边 Dock**，或顶部刘海 / 侧边栏图标单击打不开前**必读**。不读会把已否决的延时/阈值加回去，或让窗口压住侧边 Dock。
- [docs/design/element-hiding.md](docs/design/element-hiding.md)：改、评审或排查「手动隐藏网页元素」（魔法棒）的挑选交互、选中范围、规则持久化、还原入口，或新增／升级注入脚本前**必读**。不读会弄丢整批用户脚本重装，或把规则作用域写错。
- [docs/design/browser-top-chrome.md](docs/design/browser-top-chrome.md)：改、评审或排查浏览器顶栏控件区（收起 / 置顶 / **收藏** / 刷新 / 网页标识 / 下载指示、让位带、渐变与拖动区）前**必读**。不读会把已推翻的液态玻璃顶栏再做一遍；收藏必须按网页应用隔离。
- [docs/notch-activation-research.md](docs/notch-activation-research.md)：改、评审或排查刘海触发、屏幕几何、launcher 激活、**硬件 100ms / 虚拟 260ms 悬停**、路过误开，或无刘海屏虚拟热区前**必读**。不读会取消悬停等待导致虚拟热区失灵，或用截图 skill 误判覆盖层。
- [docs/webapp-runtime-isolation-refactor.md](docs/webapp-runtime-isolation-refactor.md)：改 WebApp 运行时隔离、窗口复用或站点数据边界前**必读**。不读会把多网页应用会话边界打穿。
- [docs/troubleshooting/TROUBLESHOOTING_INDEX.md](docs/troubleshooting/TROUBLESHOOTING_INDEX.md)：报错、闪退、进程突然消失、启动器点开网页应用宿主没了、Spotlight 重复图标、侧边 Dock 乱跳、通行密钥不可用、**长页面把窗口卡死**等**排查类**任务前**必读**；权威源在索引内各篇，根导航不再平铺。已知是设计取舍而非异常时跳过本索引，改读对应 `docs/design/`。
