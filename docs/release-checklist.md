# Verbatim macOS Release Checklist

This project is currently optimized for direct downloadable distribution, not Mac App Store distribution.

## Build and runtime

- Run `swift test`
- Run `./scripts/build_rust_core.sh`
- Run `swift build --product Verbatim`
- Confirm the app bundle contains:
  - `Contents/MacOS/Verbatim`
  - `Contents/Resources/Verbatim_Verbatim.bundle`
  - `Contents/Resources/RustRuntime/libverbatim_core.dylib`
- Confirm the app launches with the bundled Rust runtime present

## Signing and notarization

- Sign with a Developer ID Application certificate
- Enable hardened runtime
- Verify the app bundle signature with `codesign --verify --deep --strict`
- Submit the app for notarization with `notarytool`
- Staple the notarization ticket to the distributed app
- Re-verify the stapled app before shipping

## First-launch and setup

- Fresh-install launch succeeds
- Accessibility onboarding is contextual and non-redundant
- Microphone permission flow is contextual and non-redundant
- Model/runtime readiness messaging is inline and actionable
- Unsupported providers/features remain visible with disabled reasons

## Dictation workflow

- Manual dictation button works end to end
- `Fn / Globe` trigger works end to end
- Recording overlay shows recording/processing/error states correctly
- Style/context capture is visible in the Style tab
- True auto-paste shows success UI
- Clipboard fallback is silent
- Focused-field restore avoids blind paste into the wrong field

## Provider and model readiness

- Apple Speech readiness reflects current system capability
- Whisper runtime prewarm reflects actual runtime state
- Missing model/runtime states are visible in diagnostics
- Runtime restart path updates readiness state correctly
- Per-provider language settings persist correctly across relaunch

## Persistence

- Settings persist across relaunch
- History persists across relaunch
- Dictionary persists across relaunch
- Current provider selection and provider-specific language selection persist across relaunch

## Distribution follow-up

- Choose an update strategy:
  - Sparkle
  - explicit manual-update flow
- Create a release checklist for:
  - version bump
  - changelog
  - signing
  - notarization
  - smoke test
  - upload/distribution
