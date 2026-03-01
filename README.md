# Verbatim

Local-first, SwiftData-backed dictation app shell for macOS inspired by Flow-style dictation workflows.

## Scope

- No sync and no team-sharing in this build.
- Shared dictionary/snippet tabs are present as UI stubs.
- Data is persisted in SwiftData and local keychain.

## How to run

### Build with the package (recommended)

```bash
cd /Users/alexislovesarchitecture/Desktop/CodexWorkspace/verbatim
swift build
swift run Verbatim
```

If you prefer Xcode:

1. Open/create a macOS app target and add `Sources/Verbatim` as the source root.
2. Ensure macOS deployment target is at least `14`.
3. Set package/module name `Verbatim`.
4. Build and run.

## Permissions

You must grant the following macOS permissions for full behavior:

- **Microphone**: required for recording dictation audio.
- **Accessibility**: required for editable-target insertion mode.

If accessibility is denied, app falls back to clipboard capture when fallback mode is enabled.

## Project structure

- `Sources/Verbatim` is the active app target.
- `Sources/Verbatim/App` app entry and shell state.
- `Sources/Verbatim/Models` domain enums and SwiftData models.
- `Sources/Verbatim/Services` capture pipeline, persistence, hotkey, transcription, insertion, overlay.
- `Sources/Verbatim/ViewModels` and `Views` for page-based UI.
- `Tests/VerbatimAppTests` contains formatting/repository/flow unit tests.

## Local data location

SwiftData stores are under:

`~/Library/Application Support/Verbatim/`

## Manual test checklist

1. **App boot + shell**
   - Launch app and confirm left rail tabs appear: Home, Dictionary, Snippets, Style, Notes, Settings.
   - Open each page and verify page header + card styling.

2. **Dictionary CRUD**
   - Add a new dictionary term/replacement/expansion.
   - Edit and delete an item.
   - Confirm values survive app restart.

3. **Snippet CRUD**
   - Add a snippet with enabled + exact-match toggles.
   - Edit and delete.
   - Confirm restart persistence.

4. **Style + preview**
   - Open each category tab (Personal/Work/Email/Other).
   - Change tone for a category and verify `previewText` updates.
   - Toggle filler/voice command options and confirm formatting changes in preview.

5. **Home history**
   - Capture any transcript (if available), confirm it appears in Home.
   - Switch history filters (All/Inserted/Clipboard/Failed).
   - Expand a history row to see raw/formatted and copy actions.
   - Verify `Copy last capture` uses formatted text when present.

6. **Clipboard fallback behavior**
   - In an app with no editable target, capture text and confirm:
     - if fallback enabled: status becomes `Clipboard` and clipboard has content.
     - if fallback disabled: status becomes `Failed`.
   - `Show captured toast` setting shows toast after clipboard capture.

7. **Settings + retention**
   - Toggle Capture/Insertion/Data settings and ensure they persist.
   - Set short retention window and verify old captures are purged on new capture.
   - Use “Clear History” with confirmation.

8. **Notes**
   - Save to notes from a Home history row.
   - Edit and delete notes.
   - Confirm note list updates with title + timestamp.

9. **No-sync check**
   - Confirm no network sync actions are attempted and history stays local to machine.
