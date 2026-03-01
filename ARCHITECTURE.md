# Verbum architecture

## Product goal

Make dictation feel like a hardware feature:

- Hold to talk
- Release to stop
- Double tap to lock
- Clear listening feedback
- Immediate insertion when possible
- Guaranteed clipboard fallback when not possible

## Core pipeline

### 1. Capture

`FunctionKeyMonitor` emits press and release events.

`AudioCaptureService` starts and stops microphone recording.

### 2. Transcribe

`TranscriptionRouter` chooses one engine:

- `MockTranscriptionService`
- `OpenAITranscriptionService`
- `WhisperCPPTranscriptionService`

### 3. Format

`SmartFormatter` applies:

- dictionary corrections
- snippet expansion
- style cleanup
- filler removal
- lightweight punctuation normalization

### 4. Insert

`TextInsertionService` tries to detect an editable focused field.

- If editable, it pastes into the current app.
- If not editable, it saves the transcript as `lastCapture`, copies to clipboard, and surfaces a fallback state.

## Important state machine rules

`idle -> recording -> transcribing -> inserting -> idle`

Special branches:

- `recording(push)` + second tap inside lock window -> `recording(locked)`
- `recording(locked)` + stop button -> `transcribing`
- insertion target unavailable -> `clipboardReady`

## UI structure

- Home: transcript history and session metrics
- Dictionary: custom terms and replacements
- Snippets: reusable voice shortcuts
- Style: tone and punctuation profiles per app category
- Notes: saved dictations / scratchpad
- Settings: engine, hotkey, sounds, permissions, paste behavior

## Technical notes

### Fn / Globe handling

Start with `NSEvent` global and local `.flagsChanged` monitoring.

If Fn proves inconsistent in real-world use, switch to a lower-level `CGEvent` tap or allow a configurable fallback key.

### Permissions

Verbum should prompt for:

- microphone
- accessibility

If you later add deep keyboard monitoring or richer app-context inspection, expect additional TCC friction.

### Floating overlay

The current starter keeps the overlay in the main app window and menu bar.

For a real Flow-like capsule, add a non-activating `NSPanel` pinned near the top center of the screen.

### Formatter philosophy

Keep the first formatter deterministic.

Do not add a general LLM rewrite step until:

- insertion is reliable
- undo is easy
- the user can inspect raw transcript vs formatted transcript

### Data storage

Everything is stored locally as JSON in Application Support.

That makes export/import easy and keeps sync optional.
