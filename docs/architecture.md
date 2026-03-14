# Verbatim Architecture

## Overview

Verbatim is structured as one native app shell plus a shared application core:

- `Verbatim/`
  - SwiftUI/AppKit shell
  - owns UI, menu/status item, overlay, permissions, native input capture, Accessibility, paste simulation, and runtime lifecycle
- `RustCore/`
  - shared semantic core exposed over a small C ABI
  - owns semantic trigger handling, style/category resolution, and conservative transcript post-processing

The key split is:

- shell owns physical events and OS side effects
- core owns semantic actions and portable decision logic

## Main runtime path

### 1. Trigger input

macOS input starts in the shell:

- `HotkeyManager` in [`/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Services/PlatformServices.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Services/PlatformServices.swift)
- `FunctionKeyHotkeyBackend` for `Fn / Globe`
- event-monitor fallback for non-`Fn` bindings

The shell converts native input into semantic events:

- `InputEvent.triggerDown`
- `InputEvent.triggerUp`
- `InputEvent.triggerToggle`

Those are passed into:

- `AppModel` in [`/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/App/AppModel.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/App/AppModel.swift)
- `SharedCoreBridge` in [`/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/SharedSwiftBridge/SharedCoreBridge.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/SharedSwiftBridge/SharedCoreBridge.swift)
- Rust core in [`/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/RustCore/crates/verbatim_core_ffi/src/lib.rs`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/RustCore/crates/verbatim_core_ffi/src/lib.rs)

The core returns semantic actions:

- `startRecording`
- `stopRecording`
- `cancelRecording`

The shell then performs the actual side effects.

### 2. Record start

When recording starts, the shell freezes three things:

- current app/context snapshot
- current paste target
- current style decision

Context capture comes from:

- `ActiveAppContextService` in [`/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Services/ContextServices.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Services/ContextServices.swift)

This captures:

- frontmost app identity
- focused window title
- focused field role/subrole/title/placeholder/description
- non-secure value snippet when available

Paste-target capture reuses that same focused-field snapshot so insertion and style decisions are based on the same shell-side truth.

### 3. Record stop and transcription

When recording stops:

1. `RecordingManager` stops audio capture
2. audio is normalized
3. selected provider transcribes
4. `SharedCoreBridge.processTranscript(...)` runs cleanup and conservative formatting
5. `PasteService` attempts insertion

Provider/runtime orchestration lives in:

- [`/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Services/TranscriptionServices.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Services/TranscriptionServices.swift)

## Paste and insertion model

Insertion is shell-owned.

The paste path in `PasteService`:

1. copy final text to clipboard
2. if auto-paste is disabled, stop there
3. if Accessibility is unavailable, stop there
4. restore the target app
5. re-read the focused field
6. verify the current field still matches the captured target
7. only then send `Cmd+V`

Matching uses:

- same process ID
- same editable role class
- matching or near-matching window/field metadata
- optional value-snippet similarity

If confidence is weak, Verbatim does not paste blindly. It falls back to clipboard copy.

Current UX rule:

- true auto-paste success may show success state
- clipboard fallback is silent
- errors still surface

## Scaffolding and module responsibilities

### Swift shell

- `Verbatim/App/`
  - app entry and high-level orchestration
- `Verbatim/Views/`
  - native SwiftUI UI
- `Verbatim/Services/PlatformServices.swift`
  - hotkeys, overlay, paste, status item, permissions-adjacent shell behavior
- `Verbatim/Services/ContextServices.swift`
  - Accessibility-based app and field capture
- `Verbatim/Services/TranscriptionServices.swift`
  - recording, provider calls, normalization, coordinator flow
- `Verbatim/Services/StorageServices.swift`
  - settings/history/log/database persistence

### Shared contracts

- `Verbatim/Core/VerbatimTypes.swift`
  - app settings
  - semantic trigger types
  - style/config models
  - paste target and diagnostics types
  - cross-layer protocols

### Rust shared core

- `RustCore/crates/verbatim_core_ffi/src/lib.rs`
  - semantic trigger reducer
  - style decision logic
  - conservative cleanup/formatting
- `RustCore/include/verbatim_core.h`
  - exported C ABI
- `scripts/build_rust_core.sh`
  - Rust dylib build/staging helper

## Tool-call path inside the app

The internal call path is:

1. native shell captures input/context
2. Swift shell translates that into shared models
3. `SharedCoreBridge` calls the Rust core through C ABI + JSON payloads
4. Rust core returns semantic decisions
5. Swift shell performs native actions
6. diagnostics and latest event/context are surfaced back into the UI

This is what makes the current macOS shell portable enough to support future Windows/Linux shells without teaching the core about physical keys, AppKit, or Accessibility APIs.
