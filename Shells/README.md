# Verbatim Shells

Verbatim ships as one product with a shared Rust engine and native shells per operating system.

## Layout

- `macOS/`
  - SwiftUI/AppKit reference shell
  - local overlay, menu bar, Accessibility automation, Apple Speech integration
- `windows/`
  - WinUI 3 shell scaffold
  - Rust core hosted through a native DLL bridge
- `linux/`
  - GTK4/libadwaita shell scaffold
  - Rust core linked directly from the Linux shell workspace

## Build entrypoints

Use the root host-aware scripts:

- `scripts/build_host_shell.sh`
- `scripts/test_host_shell.sh`
- `scripts/run_host_app.sh`
- `scripts/install_host_app.sh`

The macOS shell still provides shell-local developer scripts under `macOS/scripts/`.
