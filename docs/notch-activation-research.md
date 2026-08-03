# Notch Activation Notes

NeatWebApp intentionally relies only on public macOS APIs to understand notched displays.

## Geometry Signals

The launcher uses three values from `NSScreen`:

- `safeAreaInsets`
- `auxiliaryTopLeftArea`
- `auxiliaryTopRightArea`

Together they provide enough information to infer the occupied top-center notch region:

1. Take the top strip defined by `safeAreaInsets.top`.
2. Use `auxiliaryTopLeftArea.maxX` as the inferred left edge.
3. Use `auxiliaryTopRightArea.minX` as the inferred right edge.
4. Treat the gap between those edges as the notch rectangle.

That derived geometry is then expanded into an activation region and a launcher-retention region.

## 无刘海屏幕的虚拟刘海（2026-08-01 落地）

外接显示器、Mac mini / Studio、旧款 MacBook 都没有硬件刘海，此前整条唤出链路对这些屏幕直接失效。现在由 `ScreenNotchGeometry.virtual(...)` 在这类屏幕顶部中央合成一块虚拟刘海。

设计要点：

- **复用同一组字段描述虚拟区域**（`safeAreaInsets.top` + 两侧 auxiliary 区域），而不是给下游加分支。热区判定、launcher 布局、调试叠层因此完全不用区分来源，只有需要区分表现时才看 `kind` / `isVirtual`。
- **高度对齐菜单栏**：取 `screenFrame.maxY - visibleFrame.maxY`，上限 38pt。展开时黑条正好盖住菜单栏中段，不会额外压到窗口内容。菜单栏自动隐藏、或该屏幕根本没有菜单栏时这个差值为 0，退回 26pt 兜底高度。
- **宽度按屏宽 18% 取值**，夹在 180–320pt，且不超过屏宽的 60%（超宽屏不会拉出一条夸张的黑带，小屏也不会两侧 auxiliary 区域为空导致几何判定失败）。
- **硬件刘海优先**：某块屏幕已识别出硬件刘海时不再合成虚拟刘海，避免同屏出现两个热区。
- **开关**：设置里的「虚拟刘海」可关（默认开），偏好键 `launcher.virtualNotchEnabled`。关闭时立刻撤掉挂在虚拟热区上的启动器，硬件刘海不受影响。
- **窗口落位不受影响**：虚拟几何只以 `displayID` 的形式传给运行时进程，运行时那边仍然只从真实 `NSScreen` 推导硬件刘海，因此无刘海屏幕上的窗口摆放规则没有变化。

### 虚拟热区必须要求悬停停留

硬件刘海背后没有任何系统控件，指针一进入就可以展开。虚拟热区压在菜单栏上，**必须先要求指针在热区内停留约 260ms 才展开**，否则用户只是路过去点菜单栏，也会被启动器抢走。同理，落在虚拟热区里的点击一律让给菜单栏，不在那里抢焦点。

### 坑：屏幕刷新不能无差别取消待定的悬停等待

`refreshScreenState()` 一开始会无条件取消待定的悬停等待，结果是：应用启动瞬间 `didChangeScreenParametersNotification` 会再触发一次刷新，把刚排上的等待任务取消掉；此时指针若停在热区不动就再也不会有新事件，启动器永远等不到展开（表面现象是「虚拟热区完全没反应」）。正确做法是只清理**已经消失的**热区对应的等待，顺带在热区消失时收掉挂在上面的启动器。

## Pointer Monitoring

A local event monitor alone is not sufficient because the pointer may move while another app is active. The current implementation combines:

- `NSEvent.addGlobalMonitorForEvents`
- `NSEvent.addLocalMonitorForEvents`

This lets the launcher react both before and after the overlay becomes visible.

## Known Tradeoffs

- Launcher retention still uses panel-frame hit testing instead of a dedicated tracking-area state machine.
- 虚拟刘海在空闲时完全不可见，只有悬停才出现；发现成本靠首页诊断文案与设置说明兜底，暂时没做常驻提示。
- Any future animation that depends on directional pointer intent will likely need a richer explicit state machine.

## 验证手法（无人值守时怎么测唤出）

launcher / 侧边 Dock 都是 `NSPanel` 覆盖层，验证时有两个反直觉的点：

- `winshot.py`（截图 skill）只列窗口层级为 0 的普通窗口，**截不到这类覆盖层**；要确认它是否真的出现，用 `CGWindowListCopyWindowInfo` 直接看进程的窗口列表（launcher 在层级 25，可顺带核对位置与尺寸是否等于预期的刘海几何）。
- `CGWarpMouseCursorPosition` 只挪指针、不产生鼠标事件，所以挪过去不会触发唤出；用 `CGEvent.post` 合成移动事件又受辅助功能授权限制。可行做法是：**先把指针停到目标热区，再重启应用**——事件监视器启动时会主动评估一次当前指针位置，从而走完整条唤出链路。
