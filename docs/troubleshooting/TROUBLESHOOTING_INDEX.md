# 故障排查索引

何时跳过：已知是功能设计取舍（不是异常）时，先读对应 `docs/design/`，不要从本索引找「修法」。

本索引是排查类文档的权威入口；根 `AGENTS.md` 只留本条强路由。

| 文档 | 何时读 |
|---|---|
| [2026-07-26 Spotlight 重复 App 与图标缓存](2026-07-26-spotlight-duplicate-app-and-icon-cache.md) | 安装、构建、改 App 图标，或排查 Spotlight 多个 NeatWebApp、图标不刷新、旧副本残留。 |
| [2026-08-01 侧边 Dock 跨显示器跳动](2026-08-01-side-dock-jumps-between-displays.md) | 改、评审或排查侧边 Dock 选屏与定位（多屏乱跳、拔插后跑偏）。 |
| [2026-08-04 网页通行密钥不可用](2026-08-04-webview-passkey-unavailable.md) | 排查内嵌网页用不了通行密钥 / 密码自动填充；评估或动手向苹果申请浏览器 Passkey 权限前必读（含门槛、难度与 Thunderbird 拒批证据）。 |
| [2026-09-05 宿主内存压力回调闪退](2026-09-05-host-memory-pressure-mainactor-crash.md) | 排查「菜单栏宿主突然没了 / 进程消失 / EXC_BREAKPOINT + `_dispatch_assert_queue_fail`」、或改内存压力订阅。不读会把主线程隔离闭包挂到后台压力回调上，系统一报压力就闪退。 |
| [2026-09-18 长页面把窗口卡死](2026-09-18-long-page-webview-jank.md) | 排查「网页应用内容一多就打字卡、滚动卡、窗口不可用」（对话、信息流都算），或准备给容器加显示/GPU/卸页优化之前。不读会做成某个网站的定点补丁，或用卸页破坏秒开。 |

<!-- 该文档整理/压缩于 2026-09-05 -->
