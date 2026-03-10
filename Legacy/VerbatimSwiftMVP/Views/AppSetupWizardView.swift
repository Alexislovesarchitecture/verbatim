import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct AppSetupWizardView: View {
    @EnvironmentObject private var viewModel: TranscriptionViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            setupBackground

            VerbatimGlassGroup(spacing: 20) {
                Group {
                    if viewModel.setupStep == .welcome {
                        welcomeScreen
                    } else {
                        wizardScreen
                    }
                }
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            }
        }
        .onAppear {
            viewModel.refreshSetupPermissionState()
        }
#if canImport(AppKit)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshSetupPermissionState()
        }
#endif
    }

    private var setupBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.12, green: 0.14, blue: 0.18),
                    Color(red: 0.09, green: 0.11, blue: 0.16),
                    Color.black.opacity(0.92)
                ]
                : [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.89, green: 0.92, blue: 0.97),
                    Color(red: 0.84, green: 0.88, blue: 0.94)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var welcomeScreen: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)

            VStack(spacing: 20) {
                VerbatimBrandMark(size: 96)
                    .padding(22)
                    .applyInsetWellStyle(cornerRadius: 30, padding: 18)

                VStack(spacing: 10) {
                    Text("Welcome to Verbatim")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text("Choose Apple Speech or local Whisper, grant microphone and Accessibility access, and finish your hotkey setup.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 580)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .applyLiquidCardStyle(cornerRadius: 34, tone: .frost, padding: 34)

            Button("Continue") {
                viewModel.continueSetupFlow()
            }
            .applyGlassButtonStyle(prominent: true)
            .tint(AppSectionAccent.cobalt.tint)

            Spacer(minLength: 40)
        }
    }

    private var wizardScreen: some View {
        VStack(spacing: 20) {
            setupProgressHeader

            Group {
                switch viewModel.setupStep {
                case .welcome:
                    EmptyView()
                case .transcription:
                    transcriptionSetupCard
                case .permissions:
                    permissionsCard
                case .activation:
                    activationCard
                }
            }
            .applyLiquidCardStyle(cornerRadius: 34, tone: .frost, padding: 28)

            setupNavigationBar
        }
    }

    private var setupProgressHeader: some View {
        HStack(spacing: 16) {
            ForEach(Array(viewModel.setupProgressSteps.enumerated()), id: \.element.id) { index, step in
                let state = stepperState(for: step)

                HStack(spacing: 10) {
                    Image(systemName: state.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(state.tint)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(state.background)
                        )

                    Text(step.stepLabel)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(state.tint)
                }

                if index < viewModel.setupProgressSteps.count - 1 {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 30, height: 2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .applyLiquidCardStyle(cornerRadius: 24, tone: .rail, padding: 12)
    }

    private var transcriptionSetupCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupHeader(
                title: "Transcription Setup",
                subtitle: "Choose the local engine you want Verbatim to use on this Mac."
            )

            Picker("Engine", selection: setupEngineBinding) {
                ForEach(LocalTranscriptionEngineMode.userFacingCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.selectedLocalEngineMode == .appleSpeech {
                appleSpeechSetupPanel
            } else {
                whisperSetupPanel
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Preferred Language")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                HStack {
                    Label("Auto-detect", systemImage: "globe")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .applyInsetWellStyle(cornerRadius: 20, padding: 0)
            }
        }
    }

    private var appleSpeechSetupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppSectionAccent.mint.tint)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppSectionAccent.mint.glow)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple Speech")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text(viewModel.localTranscriptionRuntimeStatusMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer()

                Text(viewModel.localModelBadgeText(.appleOnDevice))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppSectionAccent.mint.tint)
                    .applyStatusBadgeEffect()
            }

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
        .padding(18)
        .applyInsetWellStyle(cornerRadius: 24, padding: 0)
    }

    private var whisperSetupPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                setupBadge("Local Whisper", accent: .cobalt)
                setupBadge("WhisperKit", accent: .mint)
                setupBadge("Auto-detect language", accent: .amber)
            }

            VStack(spacing: 12) {
                ForEach(LocalTranscriptionModel.userFacingCases) { model in
                    setupModelRow(model)
                }
            }
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupHeader(
                title: "Permissions",
                subtitle: "Verbatim needs microphone and Accessibility access for local transcription and hotkeys."
            )

            VStack(spacing: 14) {
                ForEach(viewModel.setupPermissionRows) { row in
                    setupPermissionRow(row)
                }
            }
        }
    }

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupHeader(
                title: "Activation Setup",
                subtitle: "Configure how you trigger dictation with your global hotkey."
            )

            VStack(alignment: .leading, spacing: 18) {
                Text("Hotkey")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                VStack(spacing: 12) {
                    Text(viewModel.hotkeyBindingTitle)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text(viewModel.isCapturingHotkey ? "Press any key combination now." : "Click below to change the activation hotkey.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .applyInsetWellStyle(cornerRadius: 26, padding: 18)

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
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Mode")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                Picker("Activation Mode", selection: setupHotkeyModeBinding) {
                    ForEach(HotkeyTriggerMode.setupCases) { mode in
                        Text(mode == .tapToToggle ? "Tap" : "Hold").tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(viewModel.setupActivationModeDescription)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Test")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.setupActivationPreviewText)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(viewModel.setupActivationPreviewTextIsPlaceholder ? VerbatimPalette.mutedInk : VerbatimPalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                        .textSelection(.enabled)

                    Text(viewModel.setupActivationTestMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(viewModel.isSetupActivationMonitorActive ? VerbatimPalette.mutedInk : Color.orange)
                }
                .padding(18)
                .applyInsetWellStyle(cornerRadius: 22, padding: 0)
            }
        }
    }

    private var setupNavigationBar: some View {
        HStack {
            Button {
                viewModel.goBackInSetupFlow()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .applyGlassButtonStyle()

            Spacer()

            Button {
                viewModel.continueSetupFlow()
            } label: {
                Label(setupPrimaryActionTitle, systemImage: setupPrimaryActionSymbol)
            }
            .applyGlassButtonStyle(prominent: true)
            .tint(viewModel.setupStep == .activation ? AppSectionAccent.mint.tint : AppSectionAccent.cobalt.tint)
            .disabled(!viewModel.canAdvanceFromCurrentSetupStep)
        }
        .padding(.horizontal, 8)
    }

    private func setupHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)

            Text(subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    private func setupModelRow(_ model: LocalTranscriptionModel) -> some View {
        let isSelected = viewModel.selectedLocalModel == model
        let isAvailable = viewModel.isLocalModelSelectable(model)
        let badge = viewModel.localModelBadgeText(model)
        let actionTitle = viewModel.localModelPrimaryActionTitle(model)
        let progress = viewModel.localModelProgressValue(model)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(isSelected ? AppSectionAccent.cobalt.tint : Color.primary.opacity(0.18))
                    .frame(width: 10, height: 10)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(model.title.replacingOccurrences(of: "Whisper ", with: ""))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(VerbatimPalette.ink)

                        Text(model.detail.replacingOccurrences(of: "·", with: ""))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }

                    Text(viewModel.localModelNotes(model))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle((badge == "Retry" || !isAvailable) ? Color.orange : VerbatimPalette.mutedInk)
                }

                Spacer()

                Text(badge)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? AppSectionAccent.cobalt.tint : VerbatimPalette.ink)
                    .applyStatusBadgeEffect()
            }

            HStack(spacing: 10) {
                Button(isSelected ? "Selected" : "Choose") {
                    viewModel.selectLocalModel(model)
                }
                .applyGlassButtonStyle()
                .disabled(!isAvailable)

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
                    if let progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                    }
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
            case .none:
                EmptyView()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isSelected ? AppSectionAccent.cobalt.glow : Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(isSelected ? AppSectionAccent.cobalt.tint.opacity(0.55) : Color.white.opacity(0.26), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            guard isAvailable else { return }
            viewModel.selectLocalModel(model)
        }
        .opacity(isAvailable ? 1 : 0.66)
    }

    private func setupPermissionRow(_ row: AppSetupPermissionRowState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: permissionSymbol(for: row))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(permissionTint(for: row))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(permissionTint(for: row).opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.kind.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text(row.detail)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(row.isGranted ? VerbatimPalette.mutedInk : VerbatimPalette.ink)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button(row.actionTitle) {
                    viewModel.requestSetupPermission(row.kind)
                }
                .applyGlassButtonStyle(prominent: !row.isGranted)

                if !row.isGranted {
                    Button("Open Settings") {
                        viewModel.openSetupSystemSettings(for: row.kind)
                    }
                    .applyGlassButtonStyle()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(row.isGranted ? AppSectionAccent.mint.glow : Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(permissionTint(for: row).opacity(row.isGranted ? 0.42 : 0.24), lineWidth: 1)
                )
        )
    }

    private func permissionSymbol(for row: AppSetupPermissionRowState) -> String {
        row.isGranted ? "checkmark" : "exclamationmark"
    }

    private func permissionTint(for row: AppSetupPermissionRowState) -> Color {
        row.isGranted ? AppSectionAccent.mint.tint : AppSectionAccent.amber.tint
    }

    private func setupBadge(_ title: String, accent: AppSectionAccent) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(accent.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.glow)
            )
    }

    private func stepperState(for step: AppSetupStep) -> (symbol: String, tint: Color, background: Color) {
        let progressSteps = viewModel.setupProgressSteps
        guard let currentIndex = progressSteps.firstIndex(of: viewModel.setupStep),
              let stepIndex = progressSteps.firstIndex(of: step) else {
            return ("circle.fill", VerbatimPalette.mutedInk, Color.primary.opacity(0.08))
        }

        if stepIndex < currentIndex {
            return ("checkmark", AppSectionAccent.mint.tint, AppSectionAccent.mint.glow)
        }
        if stepIndex == currentIndex {
            return (stepIcon(for: step), AppSectionAccent.cobalt.tint, AppSectionAccent.cobalt.glow)
        }
        return (stepIcon(for: step), VerbatimPalette.mutedInk, Color.primary.opacity(0.08))
    }

    private func stepIcon(for step: AppSetupStep) -> String {
        switch step {
        case .welcome:
            return "sparkles"
        case .transcription:
            return "waveform"
        case .permissions:
            return "shield"
        case .activation:
            return "command"
        }
    }

    private var setupPrimaryActionTitle: String {
        viewModel.setupStep == .activation ? "Complete" : "Next"
    }

    private var setupPrimaryActionSymbol: String {
        viewModel.setupStep == .activation ? "checkmark" : "chevron.right"
    }

    private var setupHotkeyModeBinding: Binding<HotkeyTriggerMode> {
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

    private var setupEngineBinding: Binding<LocalTranscriptionEngineMode> {
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
}

struct SetupLockedSettingsView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.42),
                    Color(red: 0.88, green: 0.91, blue: 0.97).opacity(0.30),
                    Color(red: 0.80, green: 0.85, blue: 0.93).opacity(0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(.regularMaterial)
            .ignoresSafeArea()

            VStack(spacing: 18) {
                VerbatimBrandMark(size: 64)
                    .padding(18)
                    .applyInsetWellStyle(cornerRadius: 24, padding: 14)

                Text("Finish Setup In The Main Window")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.ink)

                Text("Settings unlock after Verbatim completes local transcription setup, permissions, and hotkey activation.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(30)
            .applyLiquidCardStyle(cornerRadius: 32, tone: .frost, padding: 30)
            .frame(maxWidth: 560)
        }
    }
}
