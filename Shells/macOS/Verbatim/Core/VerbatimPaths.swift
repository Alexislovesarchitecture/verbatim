import Foundation
import OSLog

enum VerbatimBundle {
    static let current: Bundle = {
#if SWIFT_PACKAGE
        Bundle.module
#else
        Bundle.main
#endif
    }()
}

struct VerbatimPaths {
    let fileManager: FileManager
    let rootURL: URL
    private let legacyRootURL: URL?

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        appSupportDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
            self.legacyRootURL = nil
        } else {
            let appSupport = appSupportDirectory
                ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.rootURL = appSupport.appendingPathComponent("Verbatim", isDirectory: true)
            self.legacyRootURL = appSupport.appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
        }
    }

    var modelsRoot: URL {
        rootURL.appendingPathComponent("Models", isDirectory: true)
    }

    var whisperModelsRoot: URL {
        modelsRoot.appendingPathComponent("Whisper", isDirectory: true)
    }

    var parakeetModelsRoot: URL {
        modelsRoot.appendingPathComponent("Parakeet", isDirectory: true)
    }

    var runtimeRoot: URL {
        rootURL.appendingPathComponent("Runtime", isDirectory: true)
    }

    var logsRoot: URL {
        rootURL.appendingPathComponent("Logs", isDirectory: true)
    }

    var tempRecordingsRoot: URL {
        rootURL.appendingPathComponent("Recordings", isDirectory: true)
    }

    var databaseURL: URL {
        rootURL.appendingPathComponent("transcript_history.sqlite")
    }

    var electronOpenWhisprCacheRoot: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("openwhispr", isDirectory: true)
    }

    func ensureDirectoriesExist() throws {
        try migrateLegacyRootIfNeeded()
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: whisperModelsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: parakeetModelsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempRecordingsRoot, withIntermediateDirectories: true)
    }

    private func migrateLegacyRootIfNeeded() throws {
        guard let legacyRootURL else { return }
        guard legacyRootURL.standardizedFileURL != rootURL.standardizedFileURL else { return }

        let rootExists = fileManager.fileExists(atPath: rootURL.path)
        let legacyExists = fileManager.fileExists(atPath: legacyRootURL.path)
        guard legacyExists, rootExists == false else { return }

        try fileManager.createDirectory(
            at: rootURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: legacyRootURL, to: rootURL)
    }
}

enum RuntimeBinaryInstaller {
    static func installIfNeeded(paths: VerbatimPaths, resourceBaseURL: URL? = VerbatimBundle.current.resourceURL) throws {
        try paths.ensureDirectoriesExist()
        guard let resourceBaseURL else {
            return
        }

        let candidateFiles = try candidateBinaryURLs(resourceBaseURL: resourceBaseURL)
        for sourceURL in candidateFiles {
            let destinationURL = paths.runtimeRoot.appendingPathComponent(sourceURL.lastPathComponent)
            if shouldReplace(sourceURL: sourceURL, destinationURL: destinationURL) {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
                runtimeLogger.info("Staged runtime dependency \(sourceURL.lastPathComponent, privacy: .public)")
            }
        }
    }

    private static func candidateBinaryURLs(resourceBaseURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let roots = [
            resourceBaseURL.appendingPathComponent("Binaries", isDirectory: true),
            resourceBaseURL,
        ]

        var filesByName: [String: URL] = [:]
        for root in roots where fileManager.fileExists(atPath: root.path) {
            let children = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            for child in children where isRuntimeResource(named: child.lastPathComponent) {
                filesByName[child.lastPathComponent] = child
            }
        }

        return filesByName.values.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isRuntimeResource(named fileName: String) -> Bool {
        fileName.hasSuffix(".dylib") ||
        fileName == "whisper-server-darwin-arm64" ||
        fileName == "sherpa-onnx-ws-darwin-arm64"
    }

    private static func shouldReplace(sourceURL: URL, destinationURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: destinationURL.path) else { return true }
        let sourceValues = try? sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let destinationValues = try? destinationURL.resourceValues(forKeys: [.fileSizeKey])
        return sourceValues?.fileSize != destinationValues?.fileSize
    }
}
