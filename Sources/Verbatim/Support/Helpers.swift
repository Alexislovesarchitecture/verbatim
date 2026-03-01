import Foundation

let verbatimDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = Locale.current
    return formatter
}()

func formatDuration(_ durationMs: Int) -> String {
    let seconds = max(0, durationMs) / 1000
    let mins = seconds / 60
    let secs = seconds % 60
    return String(format: "%d:%02d", mins, secs)
}
