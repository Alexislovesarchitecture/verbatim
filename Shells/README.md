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

- `scripts/build_host_shell.ps1`, `scripts/run_host_app.ps1`, and `scripts/install_host_app.ps1` on Windows
- `scripts/build_host_shell.sh`, `scripts/run_host_app.sh`, and `scripts/install_host_app.sh` on macOS and Linux

The macOS shell provides shell-local app scripts under `macOS/scripts/`.
