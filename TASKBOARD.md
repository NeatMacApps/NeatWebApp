# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| 拆 AppModel.swift 巨石为 core+extension | 受阻 | Sources/NeatWebApp/Services/AppModel*.swift、project.yml/xcodegen/pbxproj | 09:54 | 2026-09-06 09:57 | 源码已拆完；等对方「拆 WebAppWindowController…」删条后再 xcodegen/commit。09:57 对方验证中含 pbxproj |
| 拆 WebAppWindowController + 菜单去 Notch Debug | 验证中 | Services/WebAppWindowController*.swift、WebAppBrowserWindow.swift、RuntimeWindowEventSink.swift、App/AppCommands.swift、project.yml、pbxproj；不碰 AppModel/BrowserWebView | 09:53 | 2026-09-06 09:56 | 路径二；已 xcodegen；Debug 构建中 |
