# Shell/Core Contract

This document freezes the contract between the shared application core and native shells.

## Design rule

The shared core owns product logic and semantic state transitions. Native shells own platform APIs, permissions, input capture, audio capture, paste simulation, and UI.

## Shared core responsibilities

- semantic trigger interpretation
- dictation state transitions
- style/category resolution
- transcript cleanup and conservative formatting
- capability resolution
- provider/language/model policy
- diagnostics state reduction

The shared core must not depend on:

- physical key identities such as `Fn`, `Globe`, or platform key codes
- Accessibility or UI Automation APIs
- platform permission APIs
- native windowing or paste APIs

## Native shell responsibilities

Each shell owns:

- trigger capture and fallback binding registration
- microphone and Accessibility/UI Automation permissions
- audio capture
- focused app/window/field capture
- app/window activation
- paste simulation
- overlay and settings UI
- runtime process startup and staging

## Semantic trigger contract

The core consumes semantic trigger events only.

### Trigger types

- `TriggerMode`
  - `hold`
  - `toggle`
  - `doubleTapLock`
- `TriggerID`
  - `dictation`
- `InputEvent`
  - `triggerDown(triggerID, timestamp)`
  - `triggerUp(triggerID, timestamp)`
  - `triggerToggle(triggerID, timestamp)`

### Core output actions

- `none`
- `startRecording`
- `stopRecording`
- `cancelRecording`

### UI summary payload

Shell-facing trigger diagnostics should include:

- requested binding label
- effective binding label
- backend label
- fallback reason
- availability/error state
- active trigger mode

## Context snapshot contract

The shell captures a normalized focused-context snapshot at record start. That snapshot is used for both:

- style/category decision input
- insertion target restore/validation

The normalized snapshot should include:

- app name
- bundle identifier
- process identifier
- focused window title
- focused element role
- focused element subrole
- focused element title
- focused element placeholder
- focused element description
- editable-text flag
- secure-text flag
- optional short value snippet for non-secure editable fields only

## Insertion diagnostics contract

The shell owns paste simulation, but it should expose a stable diagnostic payload for the rest of the product.

### Required fields

- requested insertion mode
- target app
- target window title
- target field role/title/placeholder
- final outcome:
  - `pasted`
  - `copiedOnly`
  - `failed`
- fallback reason when clipboard copy was used:
  - app restore failed
  - field not editable
  - field no longer matched
  - accessibility unavailable

## Settings contract

The shared settings schema stores one semantic trigger configuration and per-OS bindings.

### Dictation trigger

- `dictationTrigger.mode`
- `dictationTrigger.bindings.macos`
- `dictationTrigger.bindings.windows`
- `dictationTrigger.bindings.linux`

### Provider language settings

Language preference is provider-specific.

- Apple Speech language selection
- Whisper language selection
- Parakeet language selection

Shell defaults may differ by platform, but the schema remains shared.

## macOS reference shell

The current reference shell is:

- SwiftUI/AppKit shell
- Accessibility-based context capture
- `Fn / Globe` preferred trigger with shell-only fallback binding support
- Whisper provider prewarm

Future shells should implement the same semantic contract rather than copying macOS platform behavior directly.
