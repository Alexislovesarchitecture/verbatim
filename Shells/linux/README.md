# Verbatim Linux Shell

Native Linux shell for Verbatim.

## Intent

- GTK4/libadwaita desktop shell
- direct integration with the shared Rust engine and contract crate
- same product surfaces as the reference macOS shell

## Current state

This shell currently establishes:

- a native GTK4/libadwaita shell that uses the shared Rust contract directly
- the Linux app-data root contract (`$XDG_DATA_HOME/verbatim` or `~/.local/share/verbatim`)
- shared settings persistence in `settings.json`
- shared history and dictionary persistence in `history.sqlite`
- provider selection vs activation resolution using the shared core contract
- provider-specific language and model surfaces aligned with macOS/Windows
- X11 vs Wayland capability messaging for automation-sensitive features

## Platform behavior

- Apple Speech remains visible for parity but unsupported on Linux
- Whisper remains the active cross-platform transcription provider
- Parakeet remains visible but unsupported on Linux
- X11 is the automation-capable session target in this build
- Wayland is explicitly gated for global hotkeys, focus capture, and auto-paste

## Build prerequisites

- `pkg-config`
- GTK4 development packages
- libadwaita development packages
- ALSA development packages (`libasound2-dev` on Ubuntu/Debian)
