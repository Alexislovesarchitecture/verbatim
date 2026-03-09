# OpenWhispr Gap Map
Date: 2026-03-09

Current source of truth for comparison:
- Current official OpenWhispr repo/site only
- Older OpenWispr/OpenWhispr docs treated as historical leftovers

## Recorder And Capture
- `verbatim` already uses a clean push-to-talk recorder and hands off a file artifact plus live PCM frames to the coordinator.
- OpenWhispr’s stronger lesson is not a different recorder, but tighter separation between capture and downstream inference.
- Change applied here: keep the current recorder flow, but force the managed local Whisper lane to receive a canonical 16 kHz mono WAV before inference.

## Local STT Runtime Boundary
- Previous `verbatim` state: WhisperKit ran directly in-process per utterance, while the managed-helper path behaved like a one-shot subprocess.
- OpenWhispr reference pattern: long-lived localhost inference boundary with explicit launch, health, prewarm, and failure isolation.
- Change applied here: WhisperKit now defaults to an app-managed localhost helper runtime with `ensureRunning`, `health`, `prewarm`, `transcribe`, and `shutdown`.

## Model Install And Storage
- `verbatim` already stored local artifacts under `~/Library/Application Support/VerbatimSwiftMVP`.
- OpenWhispr’s useful pattern is explicit install/cache/runtime directories instead of implicit helper state.
- Change applied here: shared local-runtime paths now define stable roots for WhisperKit models, legacy Whisper models, helper logs, helper state, and helper audio staging.

## Diagnostics And Shell Behavior
- Previous `verbatim` diagnostics tracked engine, backend, lifecycle state, latency, insertion outcome, and silence skips.
- OpenWhispr’s stronger lesson is stage-aware runtime diagnostics around helper launch, health, model availability, and inference boundaries.
- Change applied here: diagnostic route data now tracks `transport`, `helperState`, `prewarmState`, and `failureStage`, and the managed helper writes state/log artifacts for runtime inspection.

## Deliberate Non-Goals In This Pass
- No meeting transcription lane
- No Realtime API lane
- No Parakeet lane
- No agent mode
- No Python or FFmpeg dependency
