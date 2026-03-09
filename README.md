# Verbatim (Swift)

macOS Tahoe-and-up SwiftUI dictation app with a local-only record-then-transcribe flow, Apple Dictation via the modern Speech framework, and a refactored transcription session pipeline.

## Build and run (from this folder)

```bash
cd /Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim
swift build
swift test
```

For microphone and Apple Speech testing, launch the app bundle from Xcode:
- `/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/verbatim.xcodeproj`

`swift run VerbatimSwiftMVP` is fine for compile checks, but macOS privacy prompts for microphone and speech recognition require the Xcode app target bundle metadata.

## Notes

- Core app/services target macOS Tahoe and up (`.macOS("26.0")` / `MACOSX_DEPLOYMENT_TARGET = 26.0`), and Tahoe presentation styles are centralized in `PlatformAppearance.swift` with no pre-Tahoe fallback branches.
- App source of truth is under `Sources/VerbatimSwiftMVP/` (views, view model, services, app entry).
- Transcription flow now runs through a `TranscriptionCoordinator` plus `PostTranscriptionPipeline` (`record -> local transcription -> deterministic cleanup -> optional local Ollama refine`).
- Apple Dictation now uses `SpeechAnalyzer + DictationTranscriber`, with locale resolution and explicit asset installation through macOS-managed speech assets.
- The current product surface is local-only. Remote OpenAI transcription and Whisper runtime choices remain in the codebase for future work, but are not exposed in the app UI.
- Prompt profiles are bundled at `Sources/VerbatimSwiftMVP/Resources/PromptProfiles.json` and can be overridden in `~/Library/Application Support/VerbatimSwiftMVP/PromptProfiles.json`.
- Transcript history + LLM cache are stored in `~/Library/Application Support/VerbatimSwiftMVP/transcript_history.sqlite`.
- The OpenWhispr comparison artifact for this hardening pass lives at `docs/2026-03-09_openwhispr_gap_map.md`.
- General Settings include customizable global hotkeys (default `Fn/World`; `hold to talk`, `tap to toggle`, `double tap to lock`) and listening feedback controls.
- Optional auto-paste insertion uses macOS Accessibility permissions.
