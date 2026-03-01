# Verbatim

Verbatim is a macOS dictation app scaffold inspired by Wispr Flow, FreeFlow, open-wispr, and OpenSuperWhisper.

This package includes:
- a native SwiftUI sidebar app shell
- a menu bar extra
- Fn / Globe hold-to-talk monitoring scaffold
- double-tap lock listening scaffold
- listening overlay with stop button
- audio recording with input level metering
- pluggable transcription engines
  - OpenAI Audio API
  - local whisper.cpp CLI shell-out
- rule-based formatting pipeline
- insertion with Accessibility first, clipboard fallback second
- Home, Dictionary, Snippets, Style, Notes, and Settings screens
- JSON persistence for local data

## What is real vs scaffold

Implemented in source:
- app shell and data model
- history, dictionary, snippets, style, settings UI
- audio recording pipeline
- OpenAI transcription request code
- whisper.cpp CLI integration scaffold
- Accessibility insertion attempt
- clipboard fallback path
- menu bar extra and listening overlay

Needs live testing on a real Mac:
- global Fn / Globe behavior on your keyboard layout
- Accessibility insertion edge cases across apps
- microphone and Accessibility permission flow
- whisper.cpp binary path and local model path
- code signing and app packaging

## Recommended build path

### Verbatim build path (implemented)

This repo is built from `Sources/Verbatim` only.  
`Sources/VerbatimApp` is retained as a historical duplicate and is not part of the package target.

#### 1) Fastest macOS run

From project root:

```bash
cd /Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim
./scripts/build-verbatim.sh
```

Then in Xcode:

1. Verify target bundle settings:
   - deployment target: `13.0`
   - sandbox: disabled for local testing
2. Confirm Info.plist keys include microphone + accessibility prompts.
3. Build and run.
4. Grant microphone + accessibility permissions when prompted.

#### 2) Manual path (no `xcodegen`)

1. Create a new macOS App in Xcode (SwiftUI).
2. Add only `Sources/Verbatim` to the target.
3. Confirm product/module name is `Verbatim`.
4. Apply the same permissions and run.

### Fastest
1. Install Xcode.
2. Install XcodeGen if you want a ready macOS app project.
3. Run `./scripts/build-verbatim.sh`.
4. Build and run in Xcode.

### Without XcodeGen (legacy)
1. Create a new macOS App in Xcode named `Verbatim`.
2. Drag everything from `Sources/Verbatim` into the project.
3. Disable App Sandbox for local testing.
4. Add microphone and accessibility usage descriptions to the target Info.
5. Build and run.

## Runtime verification checklist (first run)

- Capture start: Fn press starts recording.
- Stop path: releasing Fn stops and sends to transcribe.
- Lock path: double-tap Fn enters locked mode, stop button exits.
- Insert path: direct insert succeeds in a focused field.
- Clipboard fallback: succeeds when insertion target is unavailable.
- History: new entry appears in Home view.
- Overlay: state updates during record/transcribe/insert.

## Suggested first configuration

### OpenAI mode
- provider: OpenAI
- model: `gpt-4o-mini-transcribe`
- add your API key in Settings, or set `OPENAI_API_KEY` in your shell/environment
- for local setup, copy `.env.example` to `.env` and set `OPENAI_API_KEY=...` (never commit `.env`)
- optional formatter prompt bias: your name, company names, client jargon

### Local mode
- install whisper.cpp
- point Verbatim at `whisper-cli`
- point Verbatim at a local ggml model file such as `base.en`

## Why the architecture looks like this

Reference products point to the same pattern:
- FreeFlow uses `Fn` hold-to-record and pastes into the current text field, with a cloud transcription plus post-processing step for context-aware cleanup.
- open-wispr uses Globe hold-to-talk, runs on-device with whisper.cpp and Metal, shows a menu bar waveform, and types at the cursor in any app.
- OpenSuperWhisper supports global shortcuts, hold-to-record, and multiple transcription engines.
- Apple Writing Tools overlap with cleanup and rewrite, but not with push-to-talk anywhere.

That is why Verbatim is split into five swappable modules:
1. Hotkey and capture
2. Transcription
3. Formatting
4. Insertion
5. Local memory and UI

## Current MVP priorities baked into this scaffold

- press Fn to talk, release to stop
- double-tap Fn to lock listening
- visible listening state with a stop button
- audible start cue
- automatic insertion when possible
- clipboard fallback when insertion fails or no text field is focused
- persistent timeline so you never lose a capture

## Files

- `App/VerbatimApp.swift`: app entry point
- `App/VerbatimStore.swift`: main coordinator and state machine
- `Models/Models.swift`: app models and settings
- `Services/HotkeyMonitor.swift`: Fn / Globe monitoring scaffold
- `Services/AudioRecorder.swift`: AVAudioEngine recorder
- `Services/TranscriptionEngines.swift`: OpenAI and whisper.cpp engines
- `Services/FormatterPipeline.swift`: rules for cleanup and styles
- `Services/InsertionService.swift`: Accessibility insertion and clipboard fallback
- `Services/OverlayController.swift`: floating listening HUD
- `Services/DataStore.swift`: JSON persistence
- `Views/*`: app UI

## Practical warnings

- Fn / Globe can conflict with emoji, Dictation, or keyboard shortcuts. open-wispr explicitly tells users to set Globe to `Do Nothing` if the key triggers the emoji picker.
- Accessibility insertion will work in many Cocoa apps, but not all. Keep clipboard fallback as a first-class path.
- Local whisper.cpp is strong for privacy, but OpenAI usually wins on setup speed and accuracy.
