# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-03-03 | self | Started repo exploration before establishing persistent napkin file because it did not exist yet | Create `.claude/napkin.md` immediately when missing, then continue technical exploration |
| 2026-03-03 | self | Assumed `gh repo fork --remote --remote-name fork` would add a `fork` git remote in this repo, then push failed because remote was absent | Verify remotes with `git remote -v` immediately after forking and add the intended remote explicitly before pushing |
| 2026-03-03 | self | Tried using `remote.origin.pushurl` to redirect pushes while keeping `origin.url` on upstream; `--force-with-lease origin` compared lease against upstream tracking ref and rejected as stale | For fork workflows that use `--force-with-lease`, set `origin` to the writable fork and keep canonical repo as separate `upstream` remote |
| 2026-03-03 | self | Used main-actor-isolated service initializers as default arguments in a main-actor view model init; Swift treated call-site as nonisolated and failed compile | Keep service types nonisolated unless actor isolation is required, or construct defaults inside initializer body |
| 2026-03-03 | self | Mixed `HierarchicalShapeStyle` (`.secondary`) and `Color` (`.orange`) in one ternary for `.foregroundStyle` | Use explicit `Color.secondary` / `Color.orange` when mixing style branches |
| 2026-03-03 | user | Friendly aliases (Mini/Turbo) were interpreted as desired labels, but user wants official model names only | Display OpenAI models exactly by API-provided model IDs; avoid custom marketing labels |
| 2026-03-03 | self | Parsed `known_speaker_references` using comma splitting, which corrupts data URLs because they contain commas | Parse speaker references line-by-line only; keep comma splitting limited to speaker-name convenience input |
| 2026-03-03 | self | `withCheckedThrowingContinuation` in a complex callback failed type inference after refactor | Use explicit continuation type (`CheckedContinuation<ExpectedType, Error>`) when inference becomes ambiguous |
| 2026-03-03 | self | `@Published` `didSet` for `transcribeUseDiarization` called `applyTranscriptionModelSelectionDefaults()`, which reassigned the same property and caused infinite observer recursion + EXC_BAD_ACCESS on launch | In property observers that trigger normalization, gate recursive calls with `if oldValue != newValue` and make normalization idempotent |
| 2026-03-03 | self | Logic formatting failed with API error `unsupported value 'none'` for `reasoning.effort` | Use only supported effort values (`minimal|low|medium|high`), send reasoning only for GPT-5 models, and add one fallback retry with `minimal` or no reasoning on 400 reasoning validation errors |

## User Preferences
- Keep successful behavior intact and layer visual enhancements instead of feature rewrites.
- Keep OpenAI model names exactly as OpenAI provides them (no custom renaming).
- Expose reasoning effort as an explicit user-facing selector in Logic settings (not just hidden defaults).
- Prefer local model execution without localhost API dependency when possible.

## Patterns That Work
- Inspect SwiftUI file structure first, then make minimal style-only diffs.
- Use a reusable glass card modifier and button style so visual upgrades stay centralized and low-risk.
- For feature knobs like model selection, keep one typed enum shared across picker, persisted settings, and API request serialization.
- For split-view settings UIs, keep selection state persisted in `UserDefaults` so users return to the last section/mode/model.
- For fork-only workflows, remove `upstream` and verify `git remote -v` plus `git branch -r` to ensure no stale upstream references remain.

## Patterns That Don't Work
- Skipping persistent notes setup causes avoidable process drift.

## Domain Notes
- Repository is a SwiftUI app (`Package.swift`, `Sources/`).
- Current task: add Apple-style Liquid Glass visual enhancements while preserving current functionality.
- Model selection now uses `TranscriptionModel` and is persisted in user defaults.
