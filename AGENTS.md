# AGENTS.md
本文件是 NeatWebApp 仓库内 agent 的工作手册。
在本仓库中工作时，优先遵守这里的约定，再结合通用编码常识执行。

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
- `Sources/NeatWebApp/Models`：WebApp 定义、刘海几何模型、launcher 布局上下文。
- `Sources/NeatWebApp/Services`：应用状态、overlay/window 协调、事件监控、偏好持久化。
- `Sources/NeatWebApp/Features/Launcher`：刘海 launcher 相关 UI。
- `Sources/NeatWebApp/Features/Browser`：浏览器会话、窗口内容、WebKit bridge。
- `Sources/NeatWebApp/Features/Dashboard`：当前阶段的调试/配置首页。
- `Tests/NeatWebAppTests`：基础单元测试。

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
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build
```
- 这是当前仓库最可靠的编译检查方式。
- 推荐固定使用 `build/DerivedData`，便于后续启动 App 和排查产物。

### 测试
全量测试：
```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

构建并测试：
```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build test
```

单个测试类：
```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:NeatWebAppTests/ScreenNotchGeometryTests test
```

### 分析 / 近似 lint
```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' analyze
```
- 当前仓库没有 SwiftLint、SwiftFormat、`swift-format` 或 `.swiftlint.yml` 配置。
- 当前最接近 lint 的命令是 `xcodebuild ... analyze`。
- 不要假设 `swiftlint` 已安装。

### 运行 App
先执行上面的构建命令，然后关闭旧进程，用新构建产物替换 `/Applications/NeatWebApp.app`，再从 `/Applications` 启动：
```bash
pkill -x "NeatWebApp" || true
rm -rf "/Applications/NeatWebApp.app"
ditto "build/DerivedData/Build/Products/Debug/NeatWebApp.app" "/Applications/NeatWebApp.app"
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
- 启动验证时，以 `/Applications/NeatWebApp.app` 作为唯一准入版本，不要直接打开 `build/DerivedData` 下的产物。
- 如果 `open` 失败，必须继续重试 2 次；只有连续 3 次都失败时，才可以向用户报告无法启动。

## 代码风格
### 导入（Imports）
- 每个 import 单独一行。
- 不保留未使用 import。
- 优先按语义分层排列：基础框架在前，UI 框架在后。
- 常见顺序：`Foundation` -> `Observation` -> `AppKit` -> `SwiftUI` -> `WebKit`。
- 只有用到 macOS 专属 API 时才引入 `AppKit`；纯 View 文件通常只需要 `SwiftUI`。

### 格式化
- 使用 4 空格缩进，不使用 tab。
- 使用 UTF-8 + LF。
- 类型、函数、条件语句的大括号与声明同行。
- 主要声明块之间保留一个空行；长表达式优先拆为局部变量。
- 不要为了“整洁”重排无关代码，避免制造大 diff。

### 命名
- 类型名使用 `UpperCamelCase`。
- 变量、属性、函数、参数使用 `lowerCamelCase`。
- 布尔值使用 `is`、`has`、`can`、`should` 前缀。
- 标识符主键或关联字段使用 `...ID` 后缀。
- 动作函数用动词开头，例如 `openWebApp(_:)`、`refreshScreenState()`。

### 类型与建模
- 纯数据优先用 `struct`。
- 共享可变状态优先放在 `@Observable` 类型中。
- 引用语义确有必要时使用 `final class`，不要默认可继承。
- UI 相关状态或副作用入口尽量标记为 `@MainActor`。
- 能用 `some` / `any` 表达的地方遵循 Swift 6 语义明确写法。

### 并发与状态管理
- 默认按 Swift 6 严格并发思维写代码。
- 新代码优先使用 `async` / `await`，避免继续扩散回调风格。
- 需要保护可变共享状态时，优先考虑 actor 或清晰的 MainActor 隔离。
- 当前项目采用 Observation：优先使用 `@Observable`、`@Environment`、`@Bindable`。
- 不要在新代码中引入 `ObservableObject`、`@Published`、`@StateObject`、`@ObservedObject`，除非必须兼容外部 API。

### SwiftUI / AppKit / WebKit 约定
- View 负责声明 UI，不负责承载大块业务逻辑。
- AppKit 只用于 SwiftUI 不擅长的部分，例如窗口级行为、屏幕几何、事件监控。
- 修改应用入口或命令菜单时，同时检查 `Sources/NeatWebApp/App/NeatWebAppApp.swift` 与 `Sources/NeatWebApp/App/AppCommands.swift`。
- 修改 launcher 行为时，同时检查 `Sources/NeatWebApp/Services/AppModel.swift`、`Sources/NeatWebApp/Services/LauncherOverlayController.swift`、`Sources/NeatWebApp/Services/NotchActivationMonitor.swift`。
- 修改刘海识别逻辑时，同时检查 `Sources/NeatWebApp/Models/ScreenNotchGeometry.swift` 和相关测试。
- 修改浏览器行为时，同时检查 `Sources/NeatWebApp/Features/Browser/BrowserSession.swift`、`Sources/NeatWebApp/Features/Browser/AppKitBridge/BrowserWebView.swift`、`Sources/NeatWebApp/Services/WebAppWindowController.swift`。
- 修改网站数据、缩放、置顶、窗口恢复时，要连同偏好持久化一起验证。

### 错误处理
- 不要新增 `!`、`try!`、强制 `as!`。
- 可恢复错误优先通过 `throws`、显式错误状态或用户可见反馈处理。
- 不要只 `print(error)` 然后吞掉错误。
- 文件 IO、保存、加载、窗口恢复这类逻辑必须考虑失败路径。

### 注释与文档
- 只在“意图不明显”或“约束容易误解”时加注释。
- 公共 API、复杂算法、重要状态机优先使用 `///` 文档注释。
- 注释描述“为什么”，不要机械复述“代码做了什么”。
- 不保留过期 TODO；如果留下 TODO，要具体说明缺什么。

### 文件与工程变更
- 新增 Swift 文件后，如果工程未自动包含，更新 `project.yml` 并重新执行 `xcodegen generate`。
- 非必要不要提交 `.xcodeproj` 内部手工改动。
- 不引入第三方库，除非用户明确要求并确认；优先使用系统框架。

## 与当前代码保持一致的实现提示
- launcher 的顶层状态由 `AppModel` 驱动。
- 刘海检测基于 `NSScreen.safeAreaInsets`、`auxiliaryTopLeftArea`、`auxiliaryTopRightArea` 的组合推断。
- 鼠标触发目前由 `NSEvent` 的 global/local monitor 组合实现。
- 浏览器容器当前基于 `WKWebView`，并使用 `WKWebsiteDataStore.default()` 做站点数据持久化。
- 页面缩放当前走 `WKWebView.pageZoom`。
- 每个 WebApp 当前是单窗口复用，由 `WebAppWindowCoordinator` 协调。
- 置顶窗口行为通过 `NSWindow.Level.floating` 实现，并由偏好持久化保存。
- 触碰这些逻辑时，要连同构建、测试、替换 `/Applications/NeatWebApp.app`、再启动验证一起执行。

## Agent 工作方式
- 先读上下文，再改代码。
- 尽量小步提交，避免把“修功能”和“重排格式”混在一起。
- 完成任意代码修改后，至少执行一次构建。
- 完成任意代码修改后，默认还要执行一次 app 启动验证：先用新构建产物替换 `/Applications/NeatWebApp.app`，再启动该版本。
- 重启 App 时，必须从 `/Applications/NeatWebApp.app` 启动；如果 `open` 启动失败，必须再重试 2 次；只有连续 3 次都失败时，才可结束并明确说明启动失败。
- 若你改动了测试或新增了测试设施，请同步更新本文件中的命令示例。
