# Verbatim Windows Shell

Native Windows shell for Verbatim.

## Intent

- WinUI 3 desktop shell
- Rust engine loaded through a thin native bridge
- packaged/MSIX-first Windows workflow
- same product surfaces as the macOS shell:
  - onboarding
  - provider selection
  - language/model state
  - permissions and diagnostics
  - history
  - dictionary
  - style settings

## Current state

This scaffold establishes the packaged WinUI project, shared-manifest loading, Rust bridge wiring, and host scripts.
Use the repo-level PowerShell wrappers on Windows:

```powershell
.\scripts\build_host_shell.ps1
.\scripts\run_host_app.ps1
.\scripts\install_host_app.ps1
```

Packaged artifacts are staged under `Shells/windows/Verbatim.Windows.Package/AppPackages/`.
The WinUI app remains the single package authority, and that companion folder holds the generated Windows package layout.

Platform adapters still need implementation for:

- global hotkeys
- microphone capture
- focus/window capture
- clipboard and paste automation
- local runtime management
- diagnostics polling
