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

### 悬停停留：硬件 100ms、虚拟约 260ms

指针移入热区后**不能立刻展开**，必须先开一个时间窗口，到点时再看指针是否还在区内：还在才弹出启动器，已经离开就当路过、不展开。这是为了挡住「从刘海上划过去 / 划到上方外接屏」这类误开。

- **硬件刘海：100ms。** 背后没有系统控件，窗口要短，否则会觉得钝；但不能是 0——路过也会误开。100ms 到期时用当时指针位置再判一次，不要求这 100ms 内完全静止。已经展开时不再等；点进硬件刘海视为明确意图，立即展开。
- **虚拟热区：约 260ms。** 热区压在菜单栏上，必须更久，否则路过要点菜单也会被启动器抢走。落在虚拟热区里的点击一律让给菜单栏，不在那里抢焦点。

不要把两套停留时间并成同一个数：100ms 挡不住菜单栏误触，260ms 会让真刘海发钝。

### 坑：屏幕刷新不能无差别取消待定的悬停等待

`refreshScreenState()` 一开始会无条件取消待定的悬停等待，结果是：应用启动瞬间 `didChangeScreenParametersNotification` 会再触发一次刷新，把刚排上的等待任务取消掉；此时指针若停在热区不动就再也不会有新事件，启动器永远等不到展开（表面现象是「热区完全没反应」）。硬件刘海改为带停留窗口之后也走同一条等待任务，这个坑不再只打虚拟热区。正确做法是只清理**已经消失的**热区对应的等待，顺带在热区消失时收掉挂在上面的启动器。

## 展开后的点击收起与图标换位（2026-10-07 裁定）

- **点抽屉里的黑色部分就收起，按像素算**：图标以外的黑底（含图标间隙、图标圆形外的四角、顶部刘海那一截）单击即收起，走「主动收起」路径——指针离开刘海热区前不会被悬停重新弹出。图标自己的点开/拖动优先，不会被这层收起手势抢走。
- **黑底收起在宿主的鼠标监听里判定，不靠界面点击手势**：浮层没拿到焦点时，图标行的滚动区会把第一次点击吞掉用来取焦点，界面手势收不到，表现为「有的黑色要点两次才收」。宿主监听每次按下都收得到，按下点不在任何图标可见圆形里就收起；图标圆形的位置由界面实时上报（含滚动与拖动偏移）。
- **看得见的就是能点的**：每个图标的可点范围等于它可见的圆形，不能用比图标大的方块。「打开主窗口」的加号同样画成与网页应用图标同尺寸的浅色圆底，可点范围就是这个圆；不允许出现「看着是黑底、点了却打开东西」的区域。
- **拖到边缘自动横向滚动**：图标多到需要横向滚动时，拖动中指针进入图标行左右边缘区（约一个图标宽）就朝该方向连续滚动，越靠外越快，拖出图标行时最快；离开边缘区立即停止。滚动期间被拖图标仍贴住指针，目标位置按「指针位移 + 已滚动距离」计算。
- **拖动换位必须跟手、不抽动**：
  - 拖动位移必须在全局坐标里量。手势挂在带偏移的图标上，用本地坐标量时，图标一挪，量出的位移就跟着变，目标位置来回跳，表现为抽动。
  - 拖动过程中不改应用顺序，只移动显示位置：被拖的图标直接等于指针位移、不加动画；被让开的图标用短弹簧动画滑一格；松手时一次性写回顺序，被拖图标从指针处滑回槽位。拖动中途就改顺序会让整行重新排版，被拖图标跟着跳。
  - 宿主的鼠标监视在每个移动/拖动事件都会进主线程，里面禁止做文件读写等同步耗时操作；曾经残留的逐事件写日志会让拖动掉帧。
- **验证状态（2026-10-07）**：拖动跟手、让位动画、松手落位已在真机截图确认；点图标空隙与顶部刘海段一次收起已由真人点击确认（界面手势版）。改为宿主监听判定后的「圆外黑角一次收起」、加号圆底、贴边自动滚动尚待用户手测，未发版。
- **自动滚动的坐标（未实测确认）**：图标行用了左右内容边距，实测滚动几何的起点偏移是 -8（等于边距），可滚范围约 -8…83；实现按「读到的偏移与程序滚动目标同一坐标」处理。若手测发现拖动开始瞬间整行跳几点，先查这里。

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
- 用 `cliclick` 一类工具合成移动、拖动、点击可以走通真实路径，但会接管用户正在用的指针；用户在用这台电脑时不要跑，交给用户手测并说明要测哪几处。用户同时动鼠标还会产生干扰事件（指针离开抽屉触发正常收起），看日志时要区分。
- 覆盖层的视觉可用 `screencapture -x -R x,y,w,h` 按屏幕区域截（区域截图会带上浮层，与只列普通窗口的截图 skill 不同），连续截几帧再拼起来看拖动过程。
- 行为细节靠临时加系统日志再用 `/usr/bin/log stream --predicate 'subsystem == "…"'` 看；zsh 里裸写 `log` 是内建命令，会报参数过多。临时日志提交前必须删掉。
- `CGWarpMouseCursorPosition` 只挪指针、不产生鼠标事件，所以挪过去不会触发唤出；用 `CGEvent.post` 合成移动事件又受辅助功能授权限制。可行做法是：**先把指针停到目标热区，再重启应用**——事件监视器启动时会主动评估一次当前指针位置，从而走完整条唤出链路。

<!-- 该文档整理/压缩于 2026-09-05 -->
