import Foundation
import OSLog

let runtimeLogger = Logger(subsystem: "Verbatim", category: "Runtime")
let downloadLogger = Logger(subsystem: "Verbatim", category: "Downloads")
let transcriptionLogger = Logger(subsystem: "Verbatim", category: "Transcription")
let diagnosticsLogger = Logger(subsystem: "Verbatim", category: "Diagnostics")

enum VerbatimLogCategory: String, CaseIterable, Sendable {
    case runtime
    case downloads
    case transcription
    case diagnostics
}

final class VerbatimLogStore: @unchecked Sendable {
    private let lock = NSLock()
    let paths: VerbatimPaths

    init(paths: VerbatimPaths) {
        self.paths = paths
        try? paths.ensureDirectoriesExist()
    }

    func fileURL(for fileName: String) -> URL {
        paths.logsRoot.appendingPathComponent(fileName)
    }

    func append(_ message: String, category: VerbatimLogCategory) {
        append(message, fileName: "\(category.rawValue).log")
    }

    func append(_ message: String, fileName: String) {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let line = "[\(timestamp)] \(message)\n"
        let url = fileURL(for: fileName)

        lock.lock()
        defer { lock.unlock() }

        try? paths.ensureDirectoriesExist()
        if FileManager.default.fileExists(atPath: url.path) == false {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }

        do {
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            return
        }
    }

    func tail(fileName: String, maxCharacters: Int = 12_000) -> String {
        let url = fileURL(for: fileName)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        if text.count <= maxCharacters {
            return text
        }
        return String(text.suffix(maxCharacters))
    }
}

final class ProcessOutputCapture: @unchecked Sendable {
    let stdout = Pipe()
    let stderr = Pipe()

    private let logStore: VerbatimLogStore
    private let fileName: String
    private let streamLabel: String

    init(logStore: VerbatimLogStore, fileName: String, streamLabel: String) {
        self.logStore = logStore
        self.fileName = fileName
        self.streamLabel = streamLabel
    }

    func start() {
        stdout.fileHandleForReading.readabilityHandler = { [logStore, fileName, streamLabel] handle in
            let data = handle.availableData
            guard data.isEmpty == false,
                  let text = String(data: data, encoding: .utf8),
                  text.isEmpty == false else { return }
            logStore.append("[\(streamLabel):stdout] \(text.trimmingCharacters(in: .newlines))", fileName: fileName)
        }
        stderr.fileHandleForReading.readabilityHandler = { [logStore, fileName, streamLabel] handle in
            let data = handle.availableData
            guard data.isEmpty == false,
                  let text = String(data: data, encoding: .utf8),
                  text.isEmpty == false else { return }
            logStore.append("[\(streamLabel):stderr] \(text.trimmingCharacters(in: .newlines))", fileName: fileName)
        }
    }

    func stop() {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
    }
}
