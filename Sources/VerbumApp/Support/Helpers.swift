import Foundation

extension DateFormatter {
    static let verbumTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let verbumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sentenceCased() -> String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }

    func collapsingWhitespace() -> String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed()
    }
}

extension Array where Element == TranscriptRecord {
    var totalWords: Int {
        reduce(0) { partialResult, item in
            partialResult + item.formattedTranscript.split(separator: " ").count
        }
    }

    var averageWPM: Int {
        guard !isEmpty else { return 0 }
        return Int(Double(reduce(0) { $0 + $1.wordsPerMinute }) / Double(count))
    }
}
