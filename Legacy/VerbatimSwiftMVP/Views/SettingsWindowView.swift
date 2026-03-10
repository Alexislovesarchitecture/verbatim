import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case transcription

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .transcription:
            return "Transcription"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Global hotkeys and permission state."
        case .transcription:
            return "Local engine and Whisper model readiness."
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "keyboard"
        case .transcription:
            return "waveform"
        }
    }

    var accent: AppSectionAccent {
        switch self {
        case .general:
            return .mint
        case .transcription:
            return .cobalt
        }
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject private var viewModel: TranscriptionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        Group {
            if viewModel.shouldShowSetupWizard {
                SetupLockedSettingsView()
            } else {
                ZStack {
                    SettingsWindowBackground()

                    VerbatimGlassGroup(spacing: 18) {
                        NavigationSplitView {
                            sidebar
                        } detail: {
                            detail
                        }
                        .navigationSplitViewStyle(.balanced)
                    }
                }
                .overlay(alignment: .topLeading) {
                    WindowConfigurator(centerOnFirstAppear: true)
                        .frame(width: 0, height: 0)
                }
            }
        }
    }

    private var sidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("Back to App", systemImage: "arrow.left")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .applyGlassButtonStyle()
                .keyboardShortcut(.cancelAction)

                HStack(spacing: 12) {
                    VerbatimBrandMark(size: 28)
                        .applyLiquidCardStyle(cornerRadius: 14, tone: .rail, padding: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Verbatim")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(VerbatimPalette.ink)

                        Text("Settings")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }

                    Spacer()
                }
                .applyLiquidCardStyle(cornerRadius: 24, tone: .rail, padding: 14)

                VStack(spacing: 10) {
                    ForEach(SettingsSection.allCases) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: section.systemImage)
                                    .font(.system(size: 14, weight: .semibold))

                                Text(section.title)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                                Spacer()
                            }
                            .foregroundStyle(
                                selectedSection == section
                                    ? section.accent.tint
                                    : VerbatimPalette.ink.opacity(0.84)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(
                            VerbatimRailButtonStyle(
                                isActive: selectedSection == section,
                                accent: section.accent
                            )
                        )
                        .help(section.subtitle)
                    }
                }
            }
            .padding(14)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
        .background(sidebarBackground)
    }

    private var sidebarBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.10),
                    Color(red: 0.20, green: 0.24, blue: 0.32).opacity(0.28)
                ]
                : [
                    Color.white.opacity(0.34),
                    Color(red: 0.86, green: 0.89, blue: 0.95).opacity(0.22)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(.thinMaterial)
    }

    private var detail: some View {
        ZStack {
            detailBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header

                    switch selectedSection {
                    case .general:
                        generalSettings
                    case .transcription:
                        transcriptionSettings
                    }
                }
                .padding(22)
                .frame(maxWidth: 980, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var detailBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.10),
                    Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.36),
                    Color(red: 0.12, green: 0.15, blue: 0.21).opacity(0.30)
                ]
                : [
                    Color.white.opacity(0.40),
                    Color(red: 0.89, green: 0.92, blue: 0.97).opacity(0.28),
                    Color(red: 0.82, green: 0.86, blue: 0.93).opacity(0.18)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(.regularMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedSection.title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)

            Text(selectedSection.subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalSettings: some View {
        VStack(spacing: 18) {
            hotkeyPanel
            permissionPanel
        }
    }

    private var hotkeyPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeader(
                title: "Global Hotkey",
                subtitle: "Keep the local transcription flow on a single shortcut."
            )

            Toggle("Enable global hotkey", isOn: $viewModel.interactionSettings.hotkeyEnabled)
                .toggleStyle(.switch)

            summaryRow(label: "Current binding", value: viewModel.effectiveHotkeyBindingTitle)

            HStack(spacing: 10) {
                Button(viewModel.isCapturingHotkey ? "Capturing..." : "Set Hotkey") {
                    viewModel.beginHotkeyCapture()
                }
                .applyGlassButtonStyle(prominent: true)
                .disabled(viewModel.isCapturingHotkey)

                Button("Use Fn Default") {
                    viewModel.resetHotkeyToDefault()
                }
                .applyGlassButtonStyle()

                if viewModel.isCapturingHotkey {
                    Button("Cancel") {
                        viewModel.cancelHotkeyCapture()
                    }
                    .applyGlassButtonStyle()
                }
            }

            Picker("Mode", selection: hotkeyModeBinding) {
                ForEach(HotkeyTriggerMode.setupCases) { mode in
                    Text(mode == .tapToToggle ? "Tap" : "Hold").tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.hotkeyStatusMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
        .padding(22)
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 0)
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeader(
                title: "Accessibility",
                subtitle: "Accessibility permission is required for the global hotkey."
            )

            summaryRow(label: "Permission", value: viewModel.hotkeyPermissionGranted ? "Enabled" : "Not enabled")

            Text(viewModel.accessibilityPermissionHelpText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            HStack(spacing: 10) {
                Button(viewModel.hotkeyPermissionGranted ? "Refresh" : "Grant Access") {
                    viewModel.requestSetupPermission(.accessibility)
                }
                .applyGlassButtonStyle(prominent: !viewModel.hotkeyPermissionGranted)

                if !viewModel.hotkeyPermissionGranted {
                    Button("Open System Settings") {
                        viewModel.openSetupSystemSettings(for: .accessibility)
                    }
                    .applyGlassButtonStyle()
                }
            }
        }
        .padding(22)
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 0)
    }

    private var transcriptionSettings: some View {
        VStack(spacing: 18) {
            enginePanel

            if viewModel.selectedLocalEngineMode == .appleSpeech {
                applePanel
            } else {
                whisperPanel
            }
        }
    }

    private var enginePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeader(
                title: "Engine",
                subtitle: "Only Apple Speech and local WhisperKit are exposed."
            )

            Picker("Engine", selection: engineBinding) {
                ForEach(LocalTranscriptionEngineMode.userFacingCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.localTranscriptionRuntimeStatusMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
        .padding(22)
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 0)
    }

    private var applePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeader(
                title: "Apple Speech",
                subtitle: "Apple manages the speech assets for the current macOS locale."
            )

            summaryRow(label: "Status", value: viewModel.localModelBadgeText(.appleOnDevice))

            Text(viewModel.localModelNotes(.appleOnDevice))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            if let actionTitle = viewModel.appleSpeechPrimaryActionTitle {
                Button(actionTitle) {
                    viewModel.installAppleSpeechAssets()
                }
                .applyGlassButtonStyle(prominent: true)
                .disabled(!viewModel.canInstallAppleSpeechAssets)
            }

            if let progress = viewModel.appleSpeechInstallProgressValue {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(22)
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 0)
    }

    private var whisperPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeader(
                title: "Whisper Models",
                subtitle: "Choose one local WhisperKit model and keep it ready."
            )

            VStack(spacing: 10) {
                ForEach(LocalTranscriptionModel.userFacingCases) { model in
                    whisperModelRow(model)
                }
            }
        }
        .padding(22)
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 0)
    }

    private func whisperModelRow(_ model: LocalTranscriptionModel) -> some View {
        let isSelected = viewModel.selectedLocalModel == model
        let actionTitle = viewModel.localModelPrimaryActionTitle(model)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(isSelected ? AppSectionAccent.cobalt.tint : Color.primary.opacity(0.18))
                    .frame(width: 10, height: 10)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.title.replacingOccurrences(of: "Whisper ", with: ""))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text(model.detail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)

                    Text(viewModel.localModelNotes(model))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer()

                Text(viewModel.localModelBadgeText(model))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? AppSectionAccent.cobalt.tint : VerbatimPalette.ink)
                    .applyStatusBadgeEffect()
            }

            HStack(spacing: 10) {
                Button(isSelected ? "Selected" : "Use Model") {
                    viewModel.selectLocalModel(model)
                }
                .applyGlassButtonStyle()
                .disabled(!viewModel.isLocalModelSelectable(model))

                if let actionTitle {
                    Button(actionTitle) {
                        viewModel.performPrimaryLocalModelAction(for: model)
                    }
                    .applyGlassButtonStyle(prominent: true)
                    .disabled(!viewModel.canRunLocalModelPrimaryAction(model))
                }

                if viewModel.canRemoveLocalModel(model) {
                    Button("Remove") {
                        viewModel.removeWhisperModel(model)
                    }
                    .applyGlassButtonStyle()
                }
            }

            switch viewModel.localWhisperInstallStateDescription(model) {
            case .progress(let label):
                VStack(alignment: .leading, spacing: 6) {
                    if let progress = viewModel.localModelProgressValue(model) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                    }

                    Text(label)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
            case .none:
                EmptyView()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? AppSectionAccent.cobalt.glow : Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(isSelected ? AppSectionAccent.cobalt.tint.opacity(0.55) : Color.white.opacity(0.22), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            guard viewModel.isLocalModelSelectable(model) else { return }
            viewModel.selectLocalModel(model)
        }
    }

    private var hotkeyModeBinding: Binding<HotkeyTriggerMode> {
        Binding(
            get: {
                HotkeyTriggerMode.setupCases.contains(viewModel.interactionSettings.hotkeyTriggerMode)
                    ? viewModel.interactionSettings.hotkeyTriggerMode
                    : .holdToTalk
            },
            set: { newValue in
                viewModel.interactionSettings.hotkeyTriggerMode = newValue
            }
        )
    }

    private var engineBinding: Binding<LocalTranscriptionEngineMode> {
        Binding(
            get: {
                LocalTranscriptionEngineMode.userFacingCases.contains(viewModel.selectedLocalEngineMode)
                    ? viewModel.selectedLocalEngineMode
                    : .whisperKit
            },
            set: { newValue in
                viewModel.selectLocalEngineMode(newValue)
            }
        )
    }

    private func settingsSectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Spacer(minLength: 16)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SettingsWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.10, green: 0.12, blue: 0.17),
                    Color(red: 0.14, green: 0.18, blue: 0.26),
                    Color(red: 0.09, green: 0.11, blue: 0.16)
                ]
                : [
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                    Color(red: 0.86, green: 0.89, blue: 0.95),
                    Color(red: 0.95, green: 0.97, blue: 0.99)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#if canImport(AppKit)
private struct WindowConfigurator: NSViewRepresentable {
    let centerOnFirstAppear: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(from: nsView, coordinator: context.coordinator)
        }
    }

    private func configureWindow(from nsView: NSView, coordinator: Coordinator) {
        guard let window = nsView.window else { return }

        if coordinator.window !== window {
            coordinator.window = window

            if centerOnFirstAppear {
                window.center()
            }
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    final class Coordinator {
        weak var window: NSWindow?
    }
}
#else
private struct WindowConfigurator: View {
    let centerOnFirstAppear: Bool

    var body: some View {
        EmptyView()
    }
}
#endif
