# Verbatim Windows Shell

Native Windows shell for Verbatim.

## Intent

- WinUI 3 desktop shell
- Rust engine loaded through a thin native bridge
- same product surfaces as the macOS shell:
  - onboarding
  - provider selection
  - language/model state
  - permissions and diagnostics
  - history
  - dictionary
  - style settings

## Current state

This scaffold establishes the native project, shell contracts, and host scripts.
Platform adapters still need implementation for:

- global hotkeys
- microphone capture
- focus/window capture
- clipboard and paste automation
- local runtime management
- diagnostics polling
