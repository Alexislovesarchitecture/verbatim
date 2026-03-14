# Verbatim

Native macOS dictation app that keeps the existing Verbatim identity and visual language while replacing the old mixed backend surface with a local-only transcription stack.

## What’s In This Rewrite

- Native SwiftUI/AppKit app shell with the existing Verbatim branding and glass styling
- Floating overlay bubble for `idle`, `recording`, `processing`, `success`, and `error`
- Menu bar status item for start/stop, open app, provider summary, and quit
- Global tap-to-toggle hotkey via Carbon event hot keys
- Local providers:
  - Apple Speech via `SpeechAnalyzer`, `SpeechTranscriber`, and `AssetInventory`
  - Whisper via bundled `whisper-server`
  - Parakeet via bundled sherpa websocket runtime
- Local history and custom dictionary stored in the existing Verbatim SQLite database location
- Local model management for Whisper and Parakeet under Application Support
- Clipboard fallback when Accessibility is missing

## Source Layout

- Native shared source tree: [`Verbatim/`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim)
- Architecture note: [`docs/architecture.md`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/docs/architecture.md)
- App entry: [`Verbatim/App/VerbatimNativeApp.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/App/VerbatimNativeApp.swift)
- App state/orchestration: [`Verbatim/App/AppModel.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/App/AppModel.swift)
- Provider/runtime services: [`Verbatim/Services/TranscriptionServices.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Services/TranscriptionServices.swift)
- Permissions, hotkeys, overlay, paste, status item: [`Verbatim/Services/PlatformServices.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Services/PlatformServices.swift)
- Persistence and manifest loading: [`Verbatim/Services/StorageServices.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Services/StorageServices.swift)
- Main UI: [`Verbatim/Views/AppRootView.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Verbatim/Views/AppRootView.swift)
- Tests: [`NativeTests/VerbatimNativeTests.swift`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/NativeTests/VerbatimNativeTests.swift)
- Archived legacy app source: [`Legacy/VerbatimSwiftMVP/`](/Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/Legacy/VerbatimSwiftMVP)

## Storage

- App support root: `~/Library/Application Support/Verbatim`
- History database: `~/Library/Application Support/Verbatim/transcript_history.sqlite`
- Whisper models: `~/Library/Application Support/Verbatim/Models/Whisper`
- Parakeet models: `~/Library/Application Support/Verbatim/Models/Parakeet`
- Runtime binaries copied on first launch: `~/Library/Application Support/Verbatim/Runtime`

On first launch, Verbatim migrates existing local data from `~/Library/Application Support/VerbatimSwiftMVP` if the new `Verbatim` root does not exist yet. It also imports still-live legacy defaults from the `VerbatimSwiftMVP.*` namespace into the current `Verbatim` settings blob.

The app also attempts a one-way import of existing Electron-era model downloads from:

- `~/.cache/openwhispr/whisper-models`
- `~/.cache/openwhispr/parakeet-models`

## Build

SwiftPM compile/test:

```bash
cd /Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim
swift build
swift test
```

Xcode target build:

```bash
cd /Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim
xcodebuild -project verbatim.xcodeproj -target 'Verbatim' -configuration Debug build
```

Open in Xcode:

```bash
open /Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim/verbatim.xcodeproj
```

## Notes

- The Xcode target is configured for arm64 because the bundled local runtime binaries in this repo are arm64-only.
- A pre-sign build phase strips extended attributes from the built app bundle so local codesigning succeeds.
- The app target disables the macOS app sandbox because local subprocess runtimes, Accessibility paste automation, and model file management need direct local access.
- Apple Speech requires an explicit language. Whisper and Parakeet support `auto` when the selected provider/model can handle it.
- The app icon catalog currently contains an extra master image file that Xcode warns about during asset compilation, but it does not block builds.
