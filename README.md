# Verbatim (Swift)

macOS Tahoe-and-up SwiftUI dictation app with record-then-transcribe, incremental OpenAI SSE updates after recording stops, Apple Speech local transcription, and a refactored transcription session pipeline.

## Build and run (from this folder)

```bash
cd /Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim
swift build
swift run
swift test
```

You can also launch from Xcode by opening:
- `/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim`

## Configure API key

Enter your OpenAI API key in the app UI (`OpenAI API key` field), then click **Save key**.

You can still run with env var:

```bash
OPENAI_API_KEY=sk-... swift run
```

## Notes

- Core app/services target macOS Tahoe and up (`.macOS("26.0")` / `MACOSX_DEPLOYMENT_TARGET = 26.0`), and Tahoe presentation styles are centralized in `PlatformAppearance.swift` with no pre-Tahoe fallback branches.
- App source of truth is under `Sources/VerbatimSwiftMVP/` (views, view model, services, app entry).
- Transcription flow now runs through a `TranscriptionCoordinator` plus `PostTranscriptionPipeline` (`record -> stream transcript events -> deterministic cleanup -> optional profile-driven LLM refine`).
- Prompt profiles are bundled at `Sources/VerbatimSwiftMVP/Resources/PromptProfiles.json` and can be overridden in `~/Library/Application Support/VerbatimSwiftMVP/PromptProfiles.json`.
- Transcript history + LLM cache are stored in `~/Library/Application Support/VerbatimSwiftMVP/transcript_history.sqlite`.
- General Settings include customizable global hotkeys (default `Fn/World`; `hold to talk`, `tap to toggle`, `double tap to lock`) and listening feedback controls.
- Optional auto-paste insertion uses macOS Accessibility permissions.
