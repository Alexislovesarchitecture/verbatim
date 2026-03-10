import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject private var viewModel: TranscriptionViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if viewModel.shouldShowSetupWizard {
            AppSetupWizardView()
        } else {
            mainApplicationView
        }
    }

    private var mainApplicationView: some View {
        ZStack {
            background

            VerbatimGlassGroup(spacing: 18) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 18) {
                                engineCard
                                hotkeyCard
                                    .frame(width: 320)
                            }

                            VStack(spacing: 18) {
                                engineCard
                                hotkeyCard
                            }
                        }

                        transcriptCard
                    }
                    .padding(24)
                    .frame(maxWidth: 1120)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            MainWindowConfigurator()
                .frame(width: 0, height: 0)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.10, green: 0.12, blue: 0.17),
                    Color(red: 0.13, green: 0.16, blue: 0.23),
                    Color(red: 0.09, green: 0.11, blue: 0.16)
                ]
                : [
                    Color(red: 0.95, green: 0.97, blue: 0.99),
                    Color(red: 0.87, green: 0.90, blue: 0.96),
                    Color(red: 0.94, green: 0.96, blue: 0.99)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(spacing: 14) {
                VerbatimBrandMark(size: 34)
                    .padding(14)
                    .applyLiquidCardStyle(cornerRadius: 22, tone: .rail, padding: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Verbatim")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text("Local transcription only. Choose Apple Speech or Whisper, record, and copy the plain result.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Label(viewModel.statusMessage, systemImage: viewModel.statusSymbol)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusTint)
                    .multilineTextAlignment(.trailing)

                Button("Settings") {
                    openSettingsWindow()
                }
                .applyGlassButtonStyle()
            }
        }
        .padding(24)
        .applyLiquidCardStyle(cornerRadius: 30, tone: .frost, padding: 0)
    }

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: "Transcription Engine",
                subtitle: "Only local engines are available in this build."
            )

            Picker("Engine", selection: engineBinding) {
                ForEach(LocalTranscriptionEngineMode.userFacingCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.selectedLocalEngineMode == .appleSpeech {
                appleSpeechCard
            } else {
                whisperCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(24)
        .applyLiquidCardStyle(cornerRadius: 30, tone: .frost, padding: 0)
    }

    private var appleSpeechCard: some View {
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

    private var whisperCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Whisper Models")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)

            Text("WhisperKit runs fully on this Mac and auto-detects language in this build.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            VStack(spacing: 10) {
                ForEach(LocalTranscriptionModel.userFacingCases) { model in
                    whisperModelRow(model)
                }
            }
        }
    }

    private func whisperModelRow(_ model: LocalTranscriptionModel) -> some View {
        let isSelected = viewModel.selectedLocalModel == model
        let badge = viewModel.localModelBadgeText(model)
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

                Text(badge)
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

    private var hotkeyCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: "Activation",
                subtitle: "Use the button below or your configured global hotkey."
            )

            VStack(alignment: .leading, spacing: 12) {
                summaryRow(label: "Hotkey", value: viewModel.effectiveHotkeyBindingTitle)
                summaryRow(label: "Mode", value: viewModel.interactionSettings.hotkeyTriggerMode == .tapToToggle ? "Tap" : "Hold")
                summaryRow(label: "Accessibility", value: viewModel.hotkeyPermissionGranted ? "Enabled" : "Required")
            }

            Divider()

            Text(viewModel.hotkeyStatusMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Button("Open Hotkey Settings") {
                openSettingsWindow()
            }
            .applyGlassButtonStyle()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(24)
        .applyLiquidCardStyle(cornerRadius: 30, tone: .frost, padding: 0)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                sectionHeader(
                    title: "Transcript",
                    subtitle: "The plain transcription stays visible here and is copied to the clipboard after each run."
                )

                Spacer()
            }

            ScrollView {
                Text(transcriptBodyText)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(viewModel.transcriptText.isEmpty ? VerbatimPalette.mutedInk : VerbatimPalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .padding(18)
            .applyInsetWellStyle(cornerRadius: 24, padding: 0)

            HStack(spacing: 12) {
                Button(viewModel.primaryButtonTitle) {
                    toggleRecording()
                }
                .applyGlassButtonStyle(prominent: true)
                .disabled(!viewModel.canToggleRecording)

                Button("Copy Transcript") {
                    viewModel.copyTranscript()
                }
                .applyGlassButtonStyle()
                .disabled(viewModel.transcriptText.isEmpty)

                Spacer()

                Text(copyStatusText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(24)
        .applyLiquidCardStyle(cornerRadius: 30, tone: .frost, padding: 0)
    }

    private var transcriptBodyText: String {
        let text = viewModel.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Record a sample to see the plain transcript here." : text
    }

    private var copyStatusText: String {
        viewModel.lastInsertionResult?.userMessage ?? "Nothing copied yet."
    }

    private var statusTint: Color {
        switch viewModel.state {
        case .idle, .done:
            return AppSectionAccent.mint.tint
        case .recording:
            return AppSectionAccent.amber.tint
        case .transcribing, .formatting:
            return AppSectionAccent.cobalt.tint
        case .error:
            return .orange
        }
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

    private func sectionHeader(title: String, subtitle: String) -> some View {
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

    private func toggleRecording() {
        switch viewModel.state {
        case .recording:
            viewModel.stop()
        default:
            viewModel.start()
        }
    }

    private func openSettingsWindow() {
#if canImport(AppKit)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
#endif
    }
}

#if canImport(AppKit)
private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(from: nsView)
        }
    }

    private func configureWindow(from nsView: NSView) {
        guard let window = nsView.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
    }
}
#else
private struct MainWindowConfigurator: View {
    var body: some View {
        EmptyView()
    }
}
#endif
