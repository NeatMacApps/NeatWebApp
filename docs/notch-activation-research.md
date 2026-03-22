# Notch Activation Research

## Current Conclusion

macOS 已经提供了足够的公开 API 来判断带刘海屏幕的顶部结构，不需要私有 API。

## Public API Signals

- `NSScreen.safeAreaInsets`
  - 表示屏幕四边被遮挡的距离
- `NSScreen.auxiliaryTopLeftArea`
  - 位于顶部、在 safe area 之外、但仍然可见的左侧区域
- `NSScreen.auxiliaryTopRightArea`
  - 位于顶部、在 safe area 之外、但仍然可见的右侧区域

结合这三个值，可以推断出 notch 所在的中间矩形区域：

1. 取屏幕顶条 `screen.frame.maxY - safeAreaInsets.top ... screen.frame.maxY`
2. notch 左边界 = `auxiliaryTopLeftArea.maxX`
3. notch 右边界 = `auxiliaryTopRightArea.minX`
4. notch rect = 两者之间的 gap

## Mouse Monitoring Strategy

仅用 local monitor 不够，因为鼠标在别的 app 上活动时不会回调到当前应用。

所以当前脚手架使用两条管线：

- `NSEvent.addGlobalMonitorForEvents`
  - 监听别的 app 上的鼠标移动
- `NSEvent.addLocalMonitorForEvents`
  - 监听本 app 内部的鼠标移动

这两个 monitor 组合起来，能覆盖 overlay 打开前后两种状态。

## Known Gaps

- 当前版本使用 panel frame 命中来延长 launcher 显示，不是最终形态。
- 如果后续要做更细腻的“移入 notch 后再向下展开”的动画，建议补上 tracking area 和显式状态机。
- 如果要支持没有刘海的显示器，需要增加 fallback trigger 策略。
