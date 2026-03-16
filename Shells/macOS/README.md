# Verbatim macOS Shell

Reference native shell for Verbatim.

## Build

```bash
cd Shells/macOS
swift build --product Verbatim
swift test
```

## Developer app

Run the dev app bundle through the shell-local script:

```bash
./scripts/run_dev_app.sh
```

Or use the repo-level host wrapper:

```bash
../../scripts/run_host_app.sh
```

## Responsibilities

- SwiftUI/AppKit UI
- menu bar and overlay
- Accessibility automation
- microphone capture
- provider runtime lifecycle
- native diagnostics rendering
