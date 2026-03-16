# Shell/Core Contract

This document defines the stable contract between the Rust engine and each native shell.

Code location:

- `RustCore/crates/verbatim_core_contract/` owns the shared payloads and reducers.
- `RustCore/crates/verbatim_core_ffi/` owns only JSON/C ABI marshaling.

## Design rule

Rust owns portable product logic. Native shells own OS APIs and side effects.

## Engine responsibilities

- semantic trigger handling
- capability reduction
- provider activation fallback
- provider-specific language/model policy
- diagnostics reduction
- style/category resolution
- transcript cleanup and conservative post-processing
- history grouping/filtering

The engine must not depend on:

- platform permission APIs
- physical key identities
- Accessibility/UI automation APIs
- native windowing or paste APIs

## Shell responsibilities

Each shell owns:

- hotkey registration
- microphone and automation permissions
- audio capture
- frontmost app/window/field capture
- paste simulation
- runtime process staging and lifecycle
- native UI

## Stable payloads

Every shell must use the same contract shapes for:

- trigger events and semantic actions
- focused-context snapshot
- insertion diagnostics
- provider capability/readiness state
- provider model/language selection state
- processed transcript payload
- history grouping requests and responses

## Settings contract

The shared settings schema stores:

- selected provider
- per-provider language preferences
- per-provider model selection
- per-OS hotkey bindings
- paste mode
- diagnostics preferences
- style settings

Shell defaults may differ, but the schema and normalization rules remain shared.

## Product rule

Transcription remains transcription-first:

- providers generate transcript text
- the engine applies conservative formatting only
- translation does not happen unless a provider is explicitly asked to translate
