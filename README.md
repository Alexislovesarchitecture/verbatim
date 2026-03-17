# Verbatim

Verbatim is one desktop product with a shared Rust engine and native shells per operating system.

## Repository layout

- `RustCore/`
  - shared Rust engine
  - portable reducers, formatting logic, and shell contract boundary
- `Shells/macOS/`
  - active SwiftUI/AppKit reference shell
- `Shells/windows/`
  - WinUI 3 native shell scaffold
- `Shells/linux/`
  - GTK4/libadwaita native shell scaffold
- `scripts/`
  - host-aware build, run, and install entrypoints
- `docs/`
  - architecture, shell/core contract, parity notes, and release guidance

## Host workflow

Build the current host app bundle:

```bash
./scripts/build_host_shell.sh
```

Run the current host app:

```bash
./scripts/run_host_app.sh
```

Install the current host app:

```bash
./scripts/install_host_app.sh
```

On macOS, the packaged app bundle is staged at `dist/Verbatim.app`.

## Reference shell

The fully working shell in this repo today is the macOS shell at `Shells/macOS/`.

It includes:

- provider selection with capability-gated activation
- provider-specific language persistence
- local model management with progress, ready/error states, and inline diagnostics
- floating overlay and menu bar integration
- hotkey capture and Accessibility-based auto-paste
- local history, dictionary, and style settings
- Apple Speech, Whisper, and Parakeet provider handling with explicit platform gating

## Product rules

- Rust owns portable product logic and semantic state transitions.
- Native shells own permissions, input capture, audio capture, focus/window capture, paste automation, runtime management, and UI.
- Auto-detect means transcription without silent translation.
- Unsupported providers and features stay visible with explicit reasons instead of disappearing.

## Documentation

- `docs/architecture.md`
- `docs/shell-core-contract.md`
- `docs/feature-parity-matrix.md`
- `docs/retired-legacy-features.md`
- `docs/release-checklist.md`
