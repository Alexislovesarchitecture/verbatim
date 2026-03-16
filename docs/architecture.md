# Verbatim Architecture

## Overview

Verbatim is structured as one shared Rust engine with native shells per operating system.

- `RustCore/`
  - `crates/verbatim_core_contract`: stable shared models and reducers
  - `crates/verbatim_core_ffi`: thin C ABI wrapper over the contract crate
  - provider/language/model policy
  - capability and diagnostics reduction
  - history grouping/filtering
  - style resolution and conservative transcript post-processing
- `Shells/macOS/`
  - SwiftUI/AppKit reference shell
  - current working implementation
- `Shells/windows/`
  - WinUI 3 shell scaffold
- `Shells/linux/`
  - GTK4/libadwaita shell scaffold

## Shell/core split

The engine owns:

- semantic trigger interpretation
- provider and language policy
- capability reduction
- diagnostics reduction
- style/category resolution
- transcript cleanup and conservative formatting
- history grouping/filtering

Native shells own:

- hotkey registration
- permissions
- microphone capture
- focus/window capture
- paste automation
- runtime process launch/staging
- UI

## Current reference implementation

The macOS shell in `Shells/macOS/` is the behavioral reference for the other shells.

The main runtime path is:

1. native shell captures trigger input and focused context
2. shell translates native state into shared contract payloads
3. `SharedCoreBridge` or the native host bridge calls into `verbatim_core_ffi`, which delegates to `verbatim_core_contract`
4. Rust returns semantic decisions
5. shell performs platform side effects and renders diagnostics

## Cross-platform intent

Windows and Linux shells are expected to match the same product surfaces and workflows as the macOS shell, while allowing platform-specific implementation details and explicit capability gating where platform APIs differ.
