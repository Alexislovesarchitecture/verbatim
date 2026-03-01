import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var controller: VerbatimController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome back")
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("Verbatim keeps your last dictations, fallback captures, and formatting behavior in one place.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        MetricCapsule(title: controller.streakText)
                        MetricCapsule(title: "\(controller.history.totalWords) words")
                        MetricCapsule(title: "\(controller.history.averageWPM) WPM")
                    }
                }

                if let lastCapture = controller.lastCapture {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Last fallback capture")
                                .font(.headline)
                            Text(lastCapture.transcript)
                            HStack {
                                Text(DateFormatter.verbatimTime.string(from: lastCapture.createdAt))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Paste") {
                                    controller.pasteLastCapture()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Today")
                        .font(.headline)
                    ForEach(controller.history) { record in
                        TranscriptCard(record: record)
                    }
                }
            }
        }
    }
}

private struct MetricCapsule: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}

private struct TranscriptCard: View {
    let record: TranscriptRecord

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(DateFormatter.verbatimTime.string(from: record.timestamp))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(record.formattedTranscript)
                HStack(spacing: 10) {
                    Label(record.activeAppName, systemImage: "app")
                    Label(record.engine.title, systemImage: "mic")
                    Label(record.outcome.rawValue, systemImage: icon(for: record.outcome))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let notes = record.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func icon(for outcome: InsertOutcome) -> String {
        switch outcome {
        case .inserted: return "checkmark.circle"
        case .clipboardReady: return "clipboard"
        case .failed: return "xmark.circle"
        }
    }
}
