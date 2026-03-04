import SwiftUI

@available(macOS 26.0, *)
@available(iOS 26.0, *)
struct ContentView: View {
    @EnvironmentObject private var viewModel: TranscriptionViewModel

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 22) {
                VStack(spacing: 16) {
                    header

                    apiKeyCard
                        .glassCard(cornerRadius: 22)

                    recordingCard
                        .glassCard(cornerRadius: 20)

                    transcriptCard
                        .glassCard(cornerRadius: 24)
                }
                .frame(maxWidth: 860, alignment: .top)
            }
            .padding(24)
        }
        .background(.clear)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.copyTranscript()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
                .disabled(viewModel.transcript.isEmpty)

                Button {
                    viewModel.clearTranscript()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.glass)
                .disabled(viewModel.transcript.isEmpty)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Verbatim")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Modern macOS transcription workspace")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(stateLabel, systemImage: statusSymbol)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OpenAI API Key")
                .font(.headline)

            SecureField(
                "Paste OpenAI API key",
                text: Binding(
                    get: { viewModel.apiKey },
                    set: { viewModel.apiKey = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .onSubmit {
                viewModel.saveApiKey()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription Model")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Transcription Model", selection: $viewModel.selectedModel) {
                    ForEach(TranscriptionModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }

            HStack(spacing: 8) {
                Button("Save Key") {
                    viewModel.saveApiKey()
                }
                .buttonStyle(.glassProminent)
                .disabled(!viewModel.canSaveApiKey)

                Button("Clear Key") {
                    viewModel.clearStoredApiKey()
                }
                .buttonStyle(.glass)
                .disabled(!viewModel.canClearApiKey)

                Spacer()
            }

            Text(viewModel.keyStatusMessage)
                .font(.caption)
                .foregroundStyle(viewModel.hasApiKeyConfigured ? Color.secondary : Color.orange)
        }
    }

    private var recordingCard: some View {
        VStack(spacing: 12) {
            Label(viewModel.statusMessage, systemImage: statusSymbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: handlePrimaryAction) {
                Label(viewModel.primaryButtonTitle, systemImage: primaryButtonSymbol)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(!viewModel.canToggleRecording)
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript")
                    .font(.headline)

                Spacer()

                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(viewModel.transcript.isEmpty ? "Your transcript will appear here after recording." : viewModel.transcript)
                    .font(.body)
                    .foregroundStyle(viewModel.transcript.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )

            HStack(spacing: 8) {
                Button("Copy") {
                    viewModel.copyTranscript()
                }
                .buttonStyle(.glass)
                .disabled(viewModel.transcript.isEmpty)

                Button("Clear") {
                    viewModel.clearTranscript()
                }
                .buttonStyle(.glass)
                .disabled(viewModel.transcript.isEmpty)
            }
        }
    }

    private var statusSymbol: String {
        switch viewModel.state {
        case .idle:
            return "checkmark.circle"
        case .recording:
            return "waveform"
        case .transcribing:
            return "hourglass"
        case .ready:
            return "checkmark.seal"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private var primaryButtonSymbol: String {
        if viewModel.state == .recording {
            return "stop.fill"
        }
        return "mic.fill"
    }

    private var stateLabel: String {
        switch viewModel.state {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .ready:
            return "Complete"
        case .error:
            return "Error"
        }
    }

    private var wordCount: Int {
        viewModel.transcript
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private func handlePrimaryAction() {
        switch viewModel.state {
        case .recording:
            viewModel.stop()
        default:
            viewModel.start()
        }
    }
}

@available(macOS 26.0, *)
@available(iOS 26.0, *)
private extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
