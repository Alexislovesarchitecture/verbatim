import SwiftUI

struct InlineStatusBanner: View {
    let status: InlineStatusMessage
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.tone == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(status.tone == .warning ? AppSectionAccent.amber.tint : AppSectionAccent.cobalt.tint)

            Text(status.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(VerbatimPalette.mutedInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .applyLiquidCardStyle(cornerRadius: 20, tone: .frost, padding: 0)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

struct ProviderSelectionButtonsView: View {
    @EnvironmentObject private var model: AppModel

    private let providerOrder: [ProviderID] = [.whisper, .parakeet, .appleSpeech]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(providerOrder) { provider in
                let capability = model.providerCapability(for: provider)

                Button {
                    model.selectProvider(provider)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: providerSystemImage(provider))
                            .font(.system(size: 13, weight: .semibold))
                        Text(provider.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(model.settings.selectedProvider == provider ? AppSectionAccent.cobalt.tint : VerbatimPalette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .opacity(capability.isSupported ? 1 : 0.62)
                    .applySelectionPillStyle(selected: model.settings.selectedProvider == provider, accent: .cobalt, cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .disabled(model.canSelectProvider(provider) == false)
            }
        }
    }

    private func providerSystemImage(_ provider: ProviderID) -> String {
        switch provider {
        case .whisper:
            return "waveform"
        case .parakeet:
            return "antenna.radiowaves.left.and.right"
        case .appleSpeech:
            return "apple.logo"
        }
    }
}

struct HotkeysPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsPanelCard(title: "Global Hotkey") {
            Toggle(isOn: Binding(
                get: { model.settings.hotkeyEnabled },
                set: { model.updateHotkeyEnabled($0) }
            )) {
                Text("Enable global activation")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .toggleStyle(.switch)
            .disabled(model.featureCapability(for: .hotkeyCapture).isSupported == false)

            Picker("Trigger mode", selection: Binding(
                get: { model.settings.hotkeyTriggerMode },
                set: { model.updateHotkeyTriggerMode($0) }
            )) {
                ForEach(HotkeyTriggerMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.settings.hotkeyEnabled == false || model.featureCapability(for: .hotkeyCapture).isSupported == false)

            HStack(spacing: 10) {
                HotkeyRecorderField(shortcut: Binding(
                    get: { model.settings.hotkeyBinding },
                    set: { model.updateHotkeyBinding($0) }
                ))
                .frame(width: 220, height: 36)

                Button(model.isCapturingHotkey ? "Capturing…" : "Capture") {
                    model.beginHotkeyCapture()
                }
                .applyGlassButtonStyle(prominent: true)
                .disabled(model.isCapturingHotkey || model.settings.hotkeyEnabled == false)

                Button("Use Fn / Globe") {
                    model.resetHotkeyBindingToDefault()
                }
                .applyGlassButtonStyle()
                .disabled(model.settings.hotkeyEnabled == false)
            }
            .disabled(model.featureCapability(for: .hotkeyCapture).isSupported == false)

            if model.settings.hotkeyBinding.usesFn {
                Picker("Fn / Globe fallback", selection: Binding(
                    get: { model.settings.functionKeyFallbackMode },
                    set: { model.updateFunctionKeyFallbackMode($0) }
                )) {
                    ForEach(FunctionKeyFallbackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.settings.hotkeyEnabled == false || model.featureCapability(for: .hotkeyCapture).isSupported == false)
            }

            Text("Requested binding: \(model.settings.hotkeyBinding.displayTitle)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Text("Effective binding: \(model.hotkeyEffectiveBindingTitle)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Text("Backend: \(model.hotkeyBackendTitle)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            if let fallbackReason = model.hotkeyFallbackReason, fallbackReason.isEmpty == false {
                Text(fallbackReason)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppSectionAccent.amber.tint)
            }

            Text(model.hotkeyStatusMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            if model.featureCapability(for: .hotkeyCapture).isSupported == false {
                Text(model.featureCapability(for: .hotkeyCapture).detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppSectionAccent.amber.tint)
            }
        }
    }
}

struct SupportOverlayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Support")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Quick help for hotkeys, permissions, and local runtime setup.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer()

                Button {
                    model.closeSupport()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                        .padding(10)
                        .applySelectionPillStyle(selected: false, accent: .violet, cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }

            SupportCardView(
                title: "Hotkey",
                subtitle: "Current global shortcut",
                detail: [
                    "Requested: \(model.settings.hotkeyBinding.displayTitle)",
                    "Effective: \(model.hotkeyEffectiveBindingTitle)",
                    "Backend: \(model.hotkeyBackendTitle)",
                    "Trigger mode: \(model.settings.hotkeyTriggerMode.title)",
                    model.hotkeyFallbackReason,
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            )

            SupportCardView(
                title: "Permissions",
                subtitle: "Microphone is required. Accessibility is optional unless you want auto-paste.",
                detail: "Microphone: \(model.permissionsManager.microphoneAuthorized ? \"Granted\" : \"Missing\")\nAccessibility: \(model.permissionsManager.accessibilityAuthorized ? \"Granted\" : \"Missing\")"
            )

            SupportCardView(
                title: "Storage",
                subtitle: "Local history, dictionary, models, and logs live here.",
                detail: model.paths.rootURL.path
            )

            SupportCardView(
                title: "Local Runtimes",
                subtitle: "Whisper uses whisper-server, Parakeet uses sherpa-onnx, and Apple Speech uses macOS system assets.",
                detail: "Everything continues to work offline after models and Apple language assets are installed.\n\(model.providerPrewarmStatusMessage)"
            )

            SupportCardView(
                title: "Diagnostics",
                subtitle: "Current provider/runtime summary",
                detail: model.supportDiagnosticsSummary.isEmpty ? "Checking local runtime state…" : model.supportDiagnosticsSummary
            )

            HStack(spacing: 10) {
                Button("Re-check") {
                    Task { await model.recheckDiagnostics() }
                }
                .applyGlassButtonStyle(prominent: true)

                Button("Reveal Logs") {
                    model.revealLogs()
                }
                .applyGlassButtonStyle()

                Button("Copy Diagnostics") {
                    model.copyDiagnostics()
                }
                .applyGlassButtonStyle()

                Button("Reveal Application Support") {
                    model.revealAppSupport()
                }
                .applyGlassButtonStyle()

                Button("Microphone Settings") {
                    model.permissionsManager.openMicrophoneSettings()
                }
                .applyGlassButtonStyle()

                Button("Accessibility Settings") {
                    model.permissionsManager.openAccessibilitySettings()
                }
                .applyGlassButtonStyle()
            }

            HStack {
                Spacer()
                Button("Close") {
                    model.closeSupport()
                }
                .applyGlassButtonStyle(prominent: true)
            }
        }
        .padding(24)
        .frame(width: 560)
        .applyLiquidCardStyle(cornerRadius: 30, tone: .shell, padding: 0)
        .shadow(color: Color.black.opacity(0.16), radius: 30, x: 0, y: 18)
    }
}

private struct SupportCardView: View {
    let title: String
    let subtitle: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .applyLiquidCardStyle(cornerRadius: 22, tone: .frost, padding: 16)
    }
}

private struct SettingsPanelCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .applyLiquidCardStyle(cornerRadius: 24, tone: .frost, padding: 16)
    }
}
