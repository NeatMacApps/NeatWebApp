# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Recoverable website icon loading | 验证中 | AppModel favicon integration, WebAppFaviconLoader/ImagePreparing, new loading coordinator/tests, architecture/memory docs; Xcode 27.2 + existing MacKit/Sparkle | 22:32 | 2026-10-26 22:43 | 219 full tests passed; invalid-image fixture exposed index-zero decode precondition, now guarded with regression; repeat tests, universal Debug/Release analyze and signed local acceptance next |
| Compact downloads continued acceptance | 验证中 | BrowserDownloadPanel/Session/Manager, runtime acceptance fixtures, browser chrome docs; conditional UI fixes and release | 2026-10-21 | 2026-10-21 | 7 download-status tests green; Clear clears records only (files intact in ~/Downloads, cleared screenshot shows capsule gone); Close only dismisses popover; expanded/progress/complete/failed shots captured; Finder click, Esc/outside, dark-page contrast still need interactive desktop |
| Fix browser window pointer offset during cross-display dragging | 验证中 | WebAppBrowserWindow, window placement regression tests/docs, version/release | 2026-10-20 | 2026-10-20 | 187 tests + build/analyze passed; Xcode 27.2; installed mixed-display drag acceptance next |
| Generic page scroll oscillation investigation and fix | In progress | Browser scripts/session/layout, runtime regression tests, long-page troubleshooting, release | 2026-10-17 | 2026-10-17 | Current owner request; inspect installed behavior, no site-specific compatibility logic |
| 继续执行 App 优化计划（退出联动/下载收藏/窗口越界/管理窗重画/长页性能） | 进行中 | Sources/NeatWebApp/App、Services/WebAppRuntimeCoordinator+RuntimeLauncher+WebAppBrowserWindow+WebAppWindowController*、Features/Dashboard+Settings+Browser、Sources/NeatWebAppRuntime、Sources/Shared、Tests、docs | 00:49 | 2026-09-21 00:49 | 续跑 2026-09-20 计划；保留工作区原型，已修构建错误，全量测试绿并覆盖安装验证中 |
| ChatGPT 卡顿根治（隐藏规则炸弹+容器侧 4 项税+宽规则告警） | 待验收 | Sources/NeatWebApp/Features/Browser（Session/WebView/ElementHiding）、Services/WebAppWindowController+FramePlacement+AutoCollapse、Tests/NeatWebAppRuntimeTests、用户偏好数据 | 2026-09-22 | 2026-09-22 | 代码已合入工作区、编译绿、运行时测试全绿；9 条 ChatGPT 隐藏规则已删（有备份）。覆盖安装+真机验收待用户网页应用空闲时做，做完删本条 |
| 迁移开源到 GitHub NeatMacApps/NeatWebApp | 进行中 | LICENSE、scripts/publish-release.sh+publish-local.env、README双语、docs/images、Sources/NeatWebApp/App/Info.plist、docs/design/release-and-auto-update.md、appcast.xml、分支与远端 | 2026-09-22 | 2026-09-22 | 用户指示直接搬、无过渡版；NeatPaste 同款链路，做完删本条 |
