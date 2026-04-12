# Contributing

Thanks for taking a look at NeatWebApp.

## Toolchain

- macOS 15.0+
- Xcode 16.2+
- Swift 6
- XcodeGen 2.44+

## Development Workflow

Generate the project whenever `project.yml` changes or files are added or removed:

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

Install the current debug build into `/Applications` and launch it:

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

## Project Conventions

- Keep changes scoped to the task at hand; avoid unrelated formatting churn.
- Prefer small, reviewable changes over broad refactors.
- Use Swift 6 concurrency and Observation patterns for new code.
- Keep AppKit usage narrow and focused on windowing, screen geometry, and event monitoring.
- Avoid introducing force unwraps, `try!`, or forced casts.
- If you touch browser runtime behavior, verify both the build and a real app launch from `/Applications/NeatWebApp.app`.

## Repository Guide

- `Sources/NeatWebApp`: host app, launcher, dashboard, runtime orchestration
- `Sources/NeatWebAppRuntime`: helper runtime app
- `Sources/Shared`: shared runtime models and helpers
- `Tests/NeatWebAppTests`: host-side tests
- `Tests/NeatWebAppRuntimeTests`: runtime-side tests

## Pull Requests

Please include:

- what changed
- why it changed
- how you validated it

If a change affects launcher behavior, browser window behavior, persistence, or runtime coordination, mention that explicitly in the PR description so reviewers know where to focus.
