# Repository Guidelines

## Project Structure & Module Organization
- Primary app target: `Sources/Verbatim`.
- App shell and composition: `Sources/Verbatim/App`.
- Core domain and persistence models: `Sources/Verbatim/Models`.
- Runtime services (capture, transcription, insertion, formatting, persistence): `Sources/Verbatim/Services`.
- UI state and pages: `Sources/Verbatim/ViewModels` and `Sources/Verbatim/Views/Pages`.
- Tests: `Tests/VerbatimAppTests`.
- Legacy compatibility shims exist in top-level `Services/*` and `Views/*` placeholder files; active implementations are in nested feature folders (for example `Services/Capture/*`, `Views/Pages/*`).

## Build, Test, and Development Commands
- `swift build` (run from repository root): builds the Swift package.
- `swift run Verbatim`: runs the macOS app target from package context.
- `swift test`: runs package tests in `Tests/VerbatimAppTests`.
- `./scripts/build-verbatim.sh`: generates `Verbatim.xcodeproj` via XcodeGen and opens it.
- In Xcode, use the `Verbatim` scheme for app builds and test execution.

## Coding Style & Naming Conventions
- Language: Swift 5.10+, SwiftUI-first architecture.
- Indentation: 4 spaces; keep methods focused and small.
- Naming: `PascalCase` for types, `camelCase` for properties/functions.
- File naming: match primary type (`CaptureCoordinator.swift`, `SettingsViewModel.swift`).
- Prefer protocol-driven services (`*Protocol`, repository protocols) and dependency injection via initializers.

## Testing Guidelines
- Framework: XCTest.
- Test files end with `Tests.swift` (for example `FormattingPipelineTests.swift`).
- Test names should be descriptive: `testX_whenY_thenZ` style is preferred.
- Cover formatting behavior, persistence flows, and coordinator insertion/clipboard branches.
- Run `swift test` before opening a PR.

## Commit & Pull Request Guidelines
- Recent history shows concise, imperative subjects (for example `Implement Verbatim macOS flows`) and occasional conventional prefixes (`chore:`).
- Recommended commit format: `<type(optional)>: <imperative summary>` or short imperative summary.
- PRs should include:
  - Clear scope and rationale
  - Test evidence (`swift test` / Xcode test results)
  - Screenshots or short clips for UI changes
  - Notes on migration/config updates (for example model or settings schema changes)

## Security & Configuration Tips
- Never commit API keys. Use keychain-backed storage (`OpenAIKeyStore`) and local environment configuration.
- Respect audio upload limits and provider capabilities when updating transcription logic.
- Keep Accessibility and microphone permission prompts functional for insertion/capture flows.
