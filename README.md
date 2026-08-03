# NeatWebApp

NeatWebApp is an experimental macOS web app shell built with SwiftUI and WebKit. It combines a notch-triggered launcher, content-first browser windows, and a lightweight runtime model where each web app is hosted by its own helper process.

The project currently targets Apple Silicon and Intel Macs running macOS 15 or later, and is developed with Xcode 16.2+ and Swift 6.

## Highlights

- Notch-triggered launcher built with SwiftUI and AppKit window coordination
- Content-first `WKWebView` windows with per-site zoom, persistence, and favicon caching
- Daily browser capabilities in the runtime: camera/microphone prompts, file upload, automatic Downloads-folder saving, external app links, and native JavaScript dialogs
- Runtime isolation: each web app window is hosted by `NeatWebAppRuntime` instead of the main app process
- Shared side notch for collapsed WebApps, draggable from anywhere, with no hover drawer and left/right placement
- Custom web app catalog with add, delete, URL editing, and drag-to-reorder management in the dashboard
- Public-API notch detection based on `NSScreen.safeAreaInsets` and auxiliary top areas

## Status

NeatWebApp is a real working prototype, not a polished end-user product yet.

What is already in place:

- Launcher reveal and retention behavior for notched displays
- Dashboard for managing custom web apps, including configured URLs, and inspecting notch geometry
- Runtime registry refresh and takeover of outdated helper builds
- Persistent site data through `WKWebsiteDataStore.default()`
- Download status in the browser top bar, with completed downloads revealable in Finder
- Unit tests for notch and side-Dock geometry, runtime registry persistence, favicon storage, browser chrome theme, and window auto-collapse behavior

What is still intentionally evolving:

- No stable import/export format for user-defined app catalogs yet
- The dashboard still doubles as a control surface and diagnostics view
- Multi-display and non-notched fallback behavior need more productization

## Install

NeatWebApp ships as a signed and notarized drag-to-install disk image. No login and no Gatekeeper workaround is required.

1. Download the latest `NeatWebApp-<version>.dmg` from the [releases page](https://forgejo.caozc.top/Max/NeatWebApp-updates/releases/latest).
2. Open the disk image and drag **NeatWebApp** into **Applications**.
3. Launch it from Applications. NeatWebApp lives in the menu bar — it has no Dock icon.

Updates are handled in-app: NeatWebApp checks daily, then downloads and installs new versions automatically. You can also trigger a check at any time from the menu bar item (**检查更新…**).

Requires macOS 15.0 or later on Apple Silicon or Intel.

## Requirements (development)

- macOS 15.0+
- Xcode 16.2+
- Swift 6
- [XcodeGen 2.44+](https://github.com/yonaskolb/XcodeGen)

Dependencies are resolved through Swift Package Manager; [Sparkle](https://sparkle-project.org/) provides the in-app updater.

## Getting Started

Generate the Xcode project:

```bash
xcodegen generate
```

Build:

```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData.noindex build
```

Run tests:

```bash
xcodebuild -project "NeatWebApp.xcodeproj" -scheme "NeatWebApp" -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData.noindex test
```

Install the freshly built app into `/Applications` and launch it:

```bash
pkill -x "NeatWebApp" || true
rm -rf "/Applications/NeatWebApp.app"
ditto "build/DerivedData.noindex/Build/Products/Debug/NeatWebApp.app" "/Applications/NeatWebApp.app"
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
├── scripts/
│   └── publish-release.sh   # One-command release: build, sign, notarize, package, publish
├── Sources/
│   ├── NeatWebApp/          # Host app: dashboard, launcher, app catalog, runtime orchestration
│   ├── NeatWebAppRuntime/   # Helper app: isolated browser window runtime
│   └── Shared/              # Shared runtime models, IPC, persistence, and placement helpers
└── Tests/
    ├── NeatWebAppTests/
    └── NeatWebAppRuntimeTests/
```

## Architecture At A Glance

- `NeatWebApp` is the host process. It owns the dashboard, menu bar controls, launcher UI, side-notch Dock, custom app catalog, favicon cache, and runtime coordination.
- `NeatWebAppRuntime` is a helper app embedded into the host. Each launched web app gets its own runtime process with its own browser window lifecycle.
- `Sources/Shared` contains runtime bootstrap models, event bus definitions, support-directory helpers, and placement utilities shared by both targets.

More detail lives in [docs/architecture.md](docs/architecture.md). Historical context for the runtime split is documented in [docs/webapp-runtime-isolation-refactor.md](docs/webapp-runtime-isolation-refactor.md).

## Releasing

Releases are cut from a maintainer's Mac with a single command. It builds, signs both the host app and the embedded runtime with a Developer ID identity, notarizes and staples them, produces the disk image and the update archive, and publishes both along with the signed update feed:

```bash
scripts/publish-release.sh              # full release
scripts/publish-release.sh --local-only # produce a notarized dmg only, no publishing
```

Signing, notarization and stapling all require macOS tooling and a local keychain, so this cannot run on a Linux machine.

## Contributing

Development setup, validation workflow, and contribution expectations are documented in [CONTRIBUTING.md](CONTRIBUTING.md).
