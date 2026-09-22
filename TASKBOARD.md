# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| 继续执行 App 优化计划（退出联动/下载收藏/窗口越界/管理窗重画/长页性能） | 进行中 | Sources/NeatWebApp/App、Services/WebAppRuntimeCoordinator+RuntimeLauncher+WebAppBrowserWindow+WebAppWindowController*、Features/Dashboard+Settings+Browser、Sources/NeatWebAppRuntime、Sources/Shared、Tests、docs | 00:49 | 2026-09-21 00:49 | 续跑 2026-09-20 计划；保留工作区原型，已修构建错误，全量测试绿并覆盖安装验证中 |
| ChatGPT 卡顿根治（隐藏规则炸弹+容器侧 4 项税+宽规则告警） | 待验收 | Sources/NeatWebApp/Features/Browser（Session/WebView/ElementHiding）、Services/WebAppWindowController+FramePlacement+AutoCollapse、Tests/NeatWebAppRuntimeTests、用户偏好数据 | 2026-09-22 | 2026-09-22 | 代码已合入工作区、编译绿、运行时测试全绿；9 条 ChatGPT 隐藏规则已删（有备份）。覆盖安装+真机验收待用户网页应用空闲时做，做完删本条 |
| 发版 v0.3.18（优化计划合入后发布） | 进行中 | project.yml、scripts/release-notes、git tag/Release、公开更新仓 | 2026-09-22 | 2026-09-22 | 用户要求快发；版本号已升 0.3.18/3036，待构建验证后跑 publish-release.sh，做完删本条 |
