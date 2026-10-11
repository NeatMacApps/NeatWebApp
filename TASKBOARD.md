# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Browser top-bar progressive menu | 验证中 | Browser top bar + runtime/host warning fixes + favicon test fixture + docs + release | 12:24 | 2026-10-11 12:53 | Short icon+label menu installed and screenshot verified; all menu labels <=2 words, committed/pushed 13f0aa8. Existing build/export .22 still has OLD long browser strings: MUST fresh archive before publication. Browser verification fixture should not be killed during final locale acceptance |
| 继续执行 App 优化计划（退出联动/下载收藏/窗口越界/管理窗重画/长页性能） | 进行中 | Sources/NeatWebApp/App、Services/WebAppRuntimeCoordinator+RuntimeLauncher+WebAppBrowserWindow+WebAppWindowController*、Features/Dashboard+Settings+Browser、Sources/NeatWebAppRuntime、Sources/Shared、Tests、docs | 00:49 | 2026-09-21 00:49 | 续跑 2026-09-20 计划；保留工作区原型，已修构建错误，全量测试绿并覆盖安装验证中 |
| ChatGPT 卡顿根治（隐藏规则炸弹+容器侧 4 项税+宽规则告警） | 待验收 | Sources/NeatWebApp/Features/Browser（Session/WebView/ElementHiding）、Services/WebAppWindowController+FramePlacement+AutoCollapse、Tests/NeatWebAppRuntimeTests、用户偏好数据 | 2026-09-22 | 2026-09-22 | 代码已合入工作区、编译绿、运行时测试全绿；9 条 ChatGPT 隐藏规则已删（有备份）。覆盖安装+真机验收待用户网页应用空闲时做，做完删本条 |
| 迁移开源到 GitHub NeatMacApps/NeatWebApp | 进行中 | LICENSE、scripts/publish-release.sh+publish-local.env、README双语、docs/images、Sources/NeatWebApp/App/Info.plist、docs/design/release-and-auto-update.md、appcast.xml、分支与远端 | 2026-09-22 | 2026-09-22 | 用户指示直接搬、无过渡版；NeatPaste 同款链路，做完删本条 |
| Floating Dock drag handle | 进行中 | SideDock view/layout, shared interaction standard, Dock docs, release | 12:52 | 2026-10-11 12:52 | Grip build/test/analyze passed; cold install next. This task owns fresh 0.3.23/3041 publication from corrected Dock + short browser labels; old 0.3.22 runner stopped. Do not launch a parallel release. |
