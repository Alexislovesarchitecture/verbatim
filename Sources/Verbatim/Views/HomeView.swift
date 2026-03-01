import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: VerbatimStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome back, \(store.settings.displayName)")
                            .font(.system(size: 34, weight: .bold))
                        Text("Verbatim keeps the last capture safe, even when insertion misses the first try.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        metricBadge(title: "Entries", value: "\(store.entries.count)")
                        metricBadge(title: "Words", value: "\(store.totalWordCount)")
                        metricBadge(title: "WPM", value: "\(store.averageWPM)")
                    }
                }

                HStack(spacing: 12) {
                    actionButton("Start listening", systemImage: "waveform") {
                        store.startListening(lockMode: false)
                    }
                    actionButton("Lock listening", systemImage: "lock.fill") {
                        store.startListening(lockMode: true)
                    }
                    actionButton("Copy last capture", systemImage: "doc.on.clipboard") {
                        store.copyLastCaptureToClipboard()
                    }
                }

                if let error = store.lastError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(14)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Today")
                        .font(.title3.weight(.semibold))
                    ForEach(store.entries) { entry in
                        DictationRow(entry: entry)
                    }
                }
            }
            .padding(32)
        }
    }

    private func metricBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct DictationRow: View {
    let entry: DictationEntry

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(Self.timeFormatter.string(from: entry.createdAt))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(entry.destinationApp)
                        .font(.subheadline.weight(.medium))
                    Text(entry.result.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
                Text(entry.formattedText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.inputWasSilent {
                    Text("Audio was silent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
