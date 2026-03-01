import SwiftUI

private let homeDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

struct HomePage: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Home")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("Hold Fn to dictate, or double tap Fn to lock recording.")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Button("Show me how") {
                        // Stub
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionCard(title: "Capture") {
                        HStack(spacing: 12) {
                            actionButton("Start listening", systemImage: "waveform", color: .accentColor) {
                                viewModel.startListening()
                            }
                            actionButton("Lock listening", systemImage: "lock.fill", color: .teal) {
                                viewModel.lockListening()
                            }
                            actionButton("Copy last capture", systemImage: "doc.on.clipboard", color: .blue) {
                                viewModel.copyLastCapture()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionCard(title: "Capture settings") {
                        Toggle("Auto insert", isOn: Binding(
                            get: { viewModel.autoInsertEnabled },
                            set: viewModel.setAutoInsertEnabled
                        ))
                        .toggleStyle(.switch)

                        Toggle("Clipboard fallback", isOn: Binding(
                            get: { viewModel.clipboardFallbackEnabled },
                            set: viewModel.setClipboardFallbackEnabled
                        ))
                        .toggleStyle(.switch)

                        HStack {
                            Text("History retention")
                            Stepper(value: Binding(
                                get: { viewModel.historyRetentionDays },
                                set: viewModel.setHistoryRetentionDays
                            ), in: 1...365)
                            Text("\(viewModel.historyRetentionDays) days")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("History")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        Picker("Filter", selection: $viewModel.filter) {
                            ForEach(HomeHistoryFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    let captures = viewModel.filteredCaptures
                    if captures.isEmpty {
                        sectionCard(title: "No captures yet") {
                            Text("Start dictation to create your first capture.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(captures) { capture in
                            captureCard(capture)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func actionButton(_ title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }

    private func captureCard(_ capture: CaptureRecord) -> some View {
        let isExpanded = viewModel.expandedRecordIds.contains(capture.id)
        VStack(spacing: 0) {
            Button {
                viewModel.toggleExpanded(capture.id)
            } label: {
                HStack(spacing: 12) {
                    Text(homeDateFormatter.string(from: capture.createdAt))
                        .font(.system(.callout, design: .monospaced))
                        .frame(width: 82, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(capture.sourceAppName)
                                .font(.subheadline.weight(.semibold))
                            Text(capture.resultStatus.title)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(backgroundColor(for: capture.resultStatus).opacity(0.2)))
                        }
                        Text(preview(for: capture))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(capture.wordCount) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(capture.wpm)) WPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(capture.rawText.isEmpty ? "(empty)" : capture.rawText)
                        .font(.body)
                        Text("Formatted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    Text(capture.formattedText.isEmpty ? "(empty)" : capture.formattedText)
                        .font(.body)

                    HStack {
                        Button("Copy raw") {
                            viewModel.copyText(capture.rawText)
                        }
                        Button("Copy formatted") {
                            viewModel.copyText(capture.formattedText)
                        }
                        Button("Save to Notes") {
                            viewModel.saveToNotes(capture)
                        }
                        Spacer()
                        Text("Engine: \(capture.engineUsed.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Locked: \(capture.wasLockedMode ? \"yes\" : \"no\")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func preview(for capture: CaptureRecord) -> String {
        let text = !capture.formattedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? capture.formattedText : capture.rawText
        let lines = text.split(whereSeparator: \.isNewline)
        let preview = lines.joined(separator: " ")
        return String(preview.prefix(110))
    }

    private func backgroundColor(for status: CaptureStatus) -> Color {
        switch status {
        case .inserted: return .green
        case .clipboard: return .blue
        case .failed: return .red
        }
    }
}
