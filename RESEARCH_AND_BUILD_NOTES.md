# Verbum research and build notes

This folder is the practical output of comparing four reference points:

- Wispr Flow: product benchmark for smart formatting, dictionary, snippets, per-app style, and cross-app insertion.
- FreeFlow: reference for a simple Swift macOS app that holds `Fn`, records, and pastes into the active text field using a cloud transcription plus post-processing pipeline.
- open-wispr: reference for a lightweight local-first architecture using whisper.cpp, Metal, Globe hold-to-talk, a menu bar waveform, and a service-like background model.
- OpenSuperWhisper: reference for multiple engines, hold-to-record, global shortcuts, and file transcription in a GUI app.

## What Verbum copies on purpose

- Fn or Globe as the primary trigger
- press-to-talk, release-to-stop
- double-tap lock mode
- visual listening state in a small floating overlay
- start cue sound
- direct insert into the focused field when possible
- clipboard fallback when direct insert fails
- a Home timeline so captures are recoverable
- Dictionary, Snippets, Style, and Notes as first-class screens

## What Verbum does differently

- It keeps the transcription layer swappable.
- It treats clipboard fallback as a core path, not an error case.
- It starts with deterministic formatting rules before adding any AI rewrite step.
- It lets you use OpenAI for fast setup or whisper.cpp for local privacy.

## Recommended next engineering steps

1. Validate Fn and Globe behavior on your exact keyboard and macOS version.
2. Test Accessibility insertion in Notes, Mail, Chrome, Slack, Terminal, and a browser text area.
3. Decide whether you want OpenAI as default or whisper.cpp as default.
4. Add a better start sound asset.
5. Add a tiny onboarding flow for permissions and the Globe key conflict.
6. Add undo-last-insert and re-copy-last-capture commands.
7. Add a small prompt editor for OpenAI formatting if you want stronger cleanup.

## Why the clipboard fallback matters

Your must-have is correct: if you start talking before the target field is ready, the app should still keep the capture. That means recording must be independent from insertion. Verbum follows that separation.
