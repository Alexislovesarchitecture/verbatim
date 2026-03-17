# Verbatim Release Checklist

## Core

- `cargo test --manifest-path RustCore/Cargo.toml`
- Rust contract and FFI payloads serialize cleanly
- staged engine artifacts exist in `RustCore/dist/`

## macOS shell

- `./scripts/build_host_shell.sh`
- `dist/Verbatim.app` launches and finds bundled Rust runtime
- Accessibility and microphone flows remain contextual
- provider/model readiness is inline and actionable

## Windows shell

- `pwsh -File Shells/windows/scripts/build.ps1`
- shell launches and loads the Rust bridge
- unsupported providers/features remain visible with reasons

## Linux shell

- `cargo build --manifest-path Shells/linux/Cargo.toml`
- shell launches and renders the main product surfaces
- unsupported providers/features remain visible with reasons

## Product behavior

- provider-specific language settings persist
- model downloads show progress, ready state, and failure state
- auto-detect does not silently translate
- history and dictionary persist correctly
- diagnostics match actual runtime state
