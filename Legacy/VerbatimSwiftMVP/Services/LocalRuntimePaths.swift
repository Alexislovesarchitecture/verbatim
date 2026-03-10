import Foundation

struct LocalRuntimePaths {
    let fileManager: FileManager
    let appSupportRoot: URL

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            appSupportRoot = baseDirectoryURL.appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
        } else {
            let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            appSupportRoot = defaultRoot.appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
        }
    }

    var whisperKitRoot: URL {
        appSupportRoot.appendingPathComponent("WhisperKit", isDirectory: true)
    }

    var legacyWhisperRoot: URL {
        appSupportRoot.appendingPathComponent("Whisper", isDirectory: true)
    }

    var helperRoot: URL {
        appSupportRoot.appendingPathComponent("ManagedWhisperKitRuntime", isDirectory: true)
    }

    var helperLogsDirectory: URL {
        helperRoot.appendingPathComponent("logs", isDirectory: true)
    }

    var helperStateDirectory: URL {
        helperRoot.appendingPathComponent("state", isDirectory: true)
    }

    var helperAudioDirectory: URL {
        helperRoot.appendingPathComponent("audio", isDirectory: true)
    }

    func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: whisperKitRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: legacyWhisperRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: helperLogsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: helperStateDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: helperAudioDirectory, withIntermediateDirectories: true)
    }
}
