# Architecture

This document describes the current structure of NeatWebApp after the host/runtime split landed.

## Goals

- Keep browser content front and center instead of wrapping it in a heavyweight shell
- Use SwiftUI for application UI and AppKit only for macOS-specific window and screen behavior
- Isolate each web app window in its own helper process so one runtime does not disturb another
- Preserve persistent browsing state through the system WebKit data store

## Process Model

### `NeatWebApp`

The host app owns:

- the dashboard window
- the menu bar entry and commands
- launcher presentation and notch activation monitoring
- the custom web app catalog
- favicon caching
- runtime discovery, launch, takeover, and command dispatch

### `NeatWebAppRuntime`

The helper app owns:

- a single web app runtime identified by `WebAppDefinition.id`
- `WKWebView` and browser session state
- the browser window and floating icon lifecycle
- runtime event publication back to the host

### `Sources/Shared`

Shared code contains:

- runtime bootstrap and state models
- distributed notification names and payload helpers
- runtime support-directory helpers and lock management
- window placement utilities used by both targets

## Launch Flow

1. `AppModel` starts, loads the app catalog, restores cached favicons, refreshes screen state, and refreshes the runtime registry.
2. When the user opens a web app, `WebAppRuntimeCoordinator` checks whether a runtime for that `appID` is already available.
3. If needed, `RuntimeLauncher` writes a bootstrap payload and launches `NeatWebAppRuntime`.
4. The runtime reads its bootstrap, creates `BrowserSession`, builds its window controller, and publishes runtime state.
5. The host observes runtime changes to update launcher state, diagnostics, and helper takeover behavior.

## Main Components

### App

- `Sources/NeatWebApp/App/NeatWebAppApp.swift`
- `Sources/NeatWebApp/App/AppCommands.swift`
- `Sources/NeatWebAppRuntime/App/NeatWebAppRuntimeApp.swift`

### Models

- `Sources/NeatWebApp/Models/WebAppDefinition.swift`
- `Sources/NeatWebApp/Models/ScreenNotchGeometry.swift`
- `Sources/NeatWebApp/Models/LauncherPresentationContext.swift`

### Host Services

- `Sources/NeatWebApp/Services/AppModel.swift`
- `Sources/NeatWebApp/Services/NotchActivationMonitor.swift`
- `Sources/NeatWebApp/Services/LauncherOverlayController.swift`
- `Sources/NeatWebApp/Services/WebAppRuntimeCoordinator.swift`
- `Sources/NeatWebApp/Services/RuntimeLauncher.swift`
- `Sources/NeatWebApp/Services/WebAppPreferencesStore.swift`
- `Sources/NeatWebApp/Services/WebAppFaviconStore.swift`

### Runtime Services

- `Sources/NeatWebAppRuntime/Services/RuntimeAppModel.swift`
- `Sources/NeatWebAppRuntime/Services/RuntimeWindowCoordinator.swift`
- `Sources/NeatWebAppRuntime/Services/RuntimeCommandListener.swift`
- `Sources/NeatWebAppRuntime/Services/RuntimeEventPublisher.swift`

### Browser Runtime

- `Sources/NeatWebApp/Features/Browser/BrowserSession.swift`
- `Sources/NeatWebApp/Features/Browser/AppKitBridge/BrowserWebView.swift`
- `Sources/NeatWebApp/Features/Browser/BrowserContainerView.swift`
- `Sources/NeatWebApp/Services/WebAppWindowController.swift`
- `Sources/NeatWebApp/Services/WebAppFloatingIconSupport.swift`

## Notch And Launcher Behavior

- `ScreenNotchGeometry` derives notch, activation, and retention rectangles from public `NSScreen` geometry APIs.
- `NotchActivationMonitor` combines local and global mouse monitors so reveal behavior still works when the pointer moves over other apps.
- `LauncherOverlayController` presents a non-activating panel for the launcher UI.
- Launcher edge fades are driven by actual scroll headroom so the visual affordance always matches the remaining hidden content.

## Persistence

- `CustomWebAppStore` persists the user-managed app catalog.
- `WebAppPreferencesStore` persists zoom, pinned state, and saved window placement.
- `WebAppFaviconStore` persists site icons and is shared by the host and runtime targets.
- `RuntimeRegistryStore` tracks active runtime bootstrap/state files and cleans stale entries.

## Testing

Tests are split by ownership:

- `Tests/NeatWebAppTests` covers host-side geometry, persistence, and catalog-related behavior.
- `Tests/NeatWebAppRuntimeTests` covers runtime-side browser chrome and floating icon placement behavior.

## Design Constraints

- The project targets macOS 15, so it stays with `WKWebView` instead of newer WebKit APIs that require newer OS versions.
- AppKit bridges are intentionally narrow and only used where SwiftUI cannot fully express the required behavior.
- The host process should never directly own browser windows or floating icons again; that isolation is a core architectural boundary.
