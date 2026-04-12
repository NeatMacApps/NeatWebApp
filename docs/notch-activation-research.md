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

## Pointer Monitoring

A local event monitor alone is not sufficient because the pointer may move while another app is active. The current implementation combines:

- `NSEvent.addGlobalMonitorForEvents`
- `NSEvent.addLocalMonitorForEvents`

This lets the launcher react both before and after the overlay becomes visible.

## Known Tradeoffs

- Launcher retention still uses panel-frame hit testing instead of a dedicated tracking-area state machine.
- A non-notched fallback reveal mode has not been productized yet.
- Any future animation that depends on directional pointer intent will likely need a richer explicit state machine.
