# Create Verbum in Xcode

If you do not want to use XcodeGen, do this:

1. Open Xcode.
2. Create a new project.
3. Choose `App` under macOS.
4. Name it `Verbum`.
5. Interface: SwiftUI.
6. Language: Swift.
7. Close the generated file tabs.
8. Delete the default `ContentView.swift` and generated `App` file.
9. Drag the `Sources/Verbum` folder into your project navigator.
10. Make sure `Copy items if needed` is checked.
11. In target settings:
   - Signing & Capabilities: remove App Sandbox for local testing.
   - Info: add `Privacy - Microphone Usage Description`.
12. Build and run.
13. Grant microphone permission.
14. When prompted, grant Accessibility permission so Verbum can insert text into other apps.

For the first test, keep `Auto insert` turned on and `Auto paste fallback` turned on.
