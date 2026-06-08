# NeatWebApp

NeatWebApp is an experimental macOS web app shell built with SwiftUI and WebKit. It combines a notch-triggered launcher, content-first browser windows, and a lightweight runtime model where each web app is hosted by its own helper process.

The project currently targets Apple Silicon and Intel Macs running macOS 15 or later, and is developed with Xcode 16.2+ and Swift 6.

## Highlights

- Notch-triggered launcher built with SwiftUI and AppKit window coordination
- Content-first `WKWebView` windows with per-site zoom, persistence, and favicon caching
- Runtime isolation: each web app window is hosted by `NeatWebAppRuntime` instead of the main app process
- Floating icon collapse / restore workflow handled by the runtime helper
- Custom web app catalog with add, delete, URL editing, and drag-to-reorder management in the dashboard
- Public-API notch detection based on `NSScreen.safeAreaInsets` and auxiliary top areas

## Status

NeatWebApp is a real working prototype, not a polished end-user product yet.

What is already in place:

- Launcher reveal and retention behavior for notched displays
- Dashboard for managing custom web apps, including configured URLs, and inspecting notch geometry
- Runtime registry refresh and takeover of outdated helper builds
- Persistent site data through `WKWebsiteDataStore.default()`
- Unit tests for notch geometry, runtime registry persistence, favicon storage, browser chrome theme, and floating icon snap behavior

What is still intentionally evolving:

- No stable import/export format for user-defined app catalogs yet
- The dashboard still doubles as a control surface and diagnostics view
- Multi-display and non-notched fallback behavior need more productization

## Requirements

- macOS 15.0+
- Xcode 16.2+
- Swift 6
- [XcodeGen 2.44+](https://github.com/yonaskolb/XcodeGen)

## Getting Started

Generate the Xcode project:

```bash
xcodegen generate
```

Build:

```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build
```

Run tests:

```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

Install the freshly built app into `/Applications` and launch it:

```bash
pkill -x "NeatWebApp" || true
rm -rf "/Applications/NeatWebApp.app"
ditto "build/DerivedData/Build/Products/Debug/NeatWebApp.app" "/Applications/NeatWebApp.app"
for attempt in 1 2 3; do
    if open "/Applications/NeatWebApp.app"; then
        break
    fi
    if [ "$attempt" -eq 3 ]; then
        echo "Failed to launch NeatWebApp after 3 attempts" >&2
        exit 1
    fi
    sleep 1
done
```

## Repository Layout

```text
.
├── project.yml
├── README.md
├── CONTRIBUTING.md
├── docs/
│   ├── architecture.md
│   ├── notch-activation-research.md
│   └── webapp-runtime-isolation-refactor.md
├── Sources/
│   ├── NeatWebApp/          # Host app: dashboard, launcher, app catalog, runtime orchestration
│   ├── NeatWebAppRuntime/   # Helper app: browser window runtime and floating icon lifecycle
│   └── Shared/              # Shared runtime models, IPC, persistence, and placement helpers
└── Tests/
    ├── NeatWebAppTests/
    └── NeatWebAppRuntimeTests/
```

## Architecture At A Glance

- `NeatWebApp` is the host process. It owns the dashboard, menu bar controls, launcher UI, custom app catalog, favicon cache, and runtime coordination.
- `NeatWebAppRuntime` is a helper app embedded into the host. Each launched web app gets its own runtime process with its own browser window lifecycle.
- `Sources/Shared` contains runtime bootstrap models, event bus definitions, support-directory helpers, and placement utilities shared by both targets.

More detail lives in [docs/architecture.md](docs/architecture.md). Historical context for the runtime split is documented in [docs/webapp-runtime-isolation-refactor.md](docs/webapp-runtime-isolation-refactor.md).

## Contributing

Development setup, validation workflow, and contribution expectations are documented in [CONTRIBUTING.md](CONTRIBUTING.md).
