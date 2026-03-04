# Verbatim (Swift)

macOS-native SwiftUI app for recording microphone audio and sending it to the OpenAI Transcriptions API.

## Build and run (from this folder)

```bash
cd /Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim
swift build
swift run
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

- Targets macOS 26+ (`.macOS(.v26)`).
- No local speech model is used in this minimal version.
- App source of truth is under `Sources/VerbatimSwiftMVP/` (views, view model, services, app entry).
