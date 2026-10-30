# 无交互桌面时打开网页应用窗口做截图验收

适用：显示器睡眠/锁屏、没有可点可键入的桌面，但需要验证已安装构建的浏览器窗口真窗像素
（顶栏、标题、窄窗行为）。常规截图流程见所用截图 skill；本篇只记本产品验证链路里
非显而易见的三件事：合成输入到不了应用、自举 bootstrap 文件能拉起真窗、WebKit
页面像素在这种环境下永远画不出来。

## 能用的手段（已验证）

- AppleScript System Events 的**菜单点击**可用（如点 `Launcher > Reveal Launcher`、
  `NeatWebApp > Settings…` 打开管理窗）。钥匙串/屏幕录制权限以截图 skill 的判定为准。
- `winshot list`（Quartz 窗口列表）始终可见窗口；`capture --wake --window-id` 能取到
  AppKit/SwiftUI 铬像素。`wake --seconds N` 需在截图期间保持运行，过期重开。
- 伪造 `RuntimeBootstrap` JSON 并拉起 `NeatWebAppRuntime`，可绕过一切点击/键盘直达真窗。
  目录：`~/Library/Application Support/NeatWebApp/RuntimeBootstrap/<大写 UUID>.json`。
  关键字段：`appID`、`definition{id,name,homeURL,accentColorName,shortDescription}`、
  `instanceID`（同文件名 UUID）、`launchReason: "openFromLauncher"`、
  `hostVersion`（当前展示版本）、`createdAt`（`Date.timeIntervalSinceReferenceDate`
  双精度）。`CGRect` 的 Codable 形状是 `[[x, y], [w, h]]`，不是字典。
  传 `restoredWindowFrame` 且 `restoredPhase` 留空会**锁住该框**（`windowWillResize`
  直接返回），可做出小于 390 最小宽度的窄窗探针；不传则走默认布局。
- 直接执行 runtime 二进制会秒退（exit 0），窗由宿主侧接管拉起、实例 ID 与文件不同。
  机制未完全查明：只认「窗起来了且属签名构建」这一结果，不要依赖自拉起进程常驻。
  验收用的探针 `appID` 用 `xxx_local` 这类一眼可辨的名字，`definition.homeURL` 可指向
  本地探针页；`name` 写要验证的标题文本（含超长名）。

## 已验证走不通的路（别重试）

- cliclick/Quartz 合成点击与悬停：`cliclick p` 显示指针动了，但显示器睡眠时事件到不了
  应用——管理窗行 hover 不出 Open 按钮、双击不开应用、切页签无效。
- System Events `keystroke`（如 Cmd+,）：无效果。
- AX `tell process ... to return every window`：宿主与 runtime 均返回 0，Quartz 明明看得到窗。
  不要用 AX 枚举窗口做断言或 `set size` 窄窗；窄窗走上面的锁框 bootstrap。

## 已知限制

- WebKit 页面像素在这种环境下**永远是白的**：远程 https 与本地 file:// 探针页都不绘制，
  `pageColor` 走不出白色兜底，深色翻转触发不了。这与 0.3.32 记录的捕获限制是同一条，
  不是回归。铬（标题/图标/渐变）是 CPU 绘制，不受影响，可正常验收；深色翻转靠
  `BrowserChromeTheme` 单测与「标题复用图标同一 `foregroundColor`」兜底，有交互桌面时补拍。
- 管理窗/启动器面板的唤醒截图只证明静态内容；动画与焦点行为不由截图确立。

## 收尾清理（探针不许留给用户）

1. 按窗主进程号杀探针 runtime（`ps` 对窗 pid，**不要** `pkill`，别碰用户正在用的窗）。
2. 删自建的 `RuntimeBootstrap/<uuid>.json`（正常退出 runtime 自己会删，double-check）、
   `RuntimeState` 里探针实例文件、`RuntimeLocks/<probe>.lock`。
3. `Preferences/web-apps.json` 里删掉探针 `appID` 条目（窗口持久化会写进去）。
4. 探针 HTML 删掉；确认 `winshot list` 里无探针窗后再走。
