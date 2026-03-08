import Foundation
import XCTest
@testable import VerbatimSwiftMVP

final class WhisperModelManagerTests: XCTestCase {
    func testDownloadModelMarksItInstalled() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-whisper-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let manager = WhisperModelManager(
            baseDirectoryURL: tempRoot,
            downloadHandler: { _ in
                let downloadedURL = tempRoot.appendingPathComponent("downloaded-model.bin")
                try Data("model".utf8).write(to: downloadedURL)
                return downloadedURL
            }
        )

        let state = await manager.downloadModel(.whisperBase)
        let installedURL = await manager.installedModelURL(for: .whisperBase)

        if case .installed = state {
            XCTAssertNotNil(installedURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: installedURL!.path))
        } else {
            XCTFail("Expected installed state, got \(state)")
        }
    }

    func testRemoveModelReturnsToNotInstalled() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-whisper-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let manager = WhisperModelManager(
            baseDirectoryURL: tempRoot,
            downloadHandler: { _ in
                let downloadedURL = tempRoot.appendingPathComponent("downloaded-model.bin")
                try Data("model".utf8).write(to: downloadedURL)
                return downloadedURL
            }
        )

        _ = await manager.downloadModel(.whisperBase)
        try await manager.removeModel(.whisperBase)

        let state = await manager.installState(for: .whisperBase)
        if case .notInstalled = state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected notInstalled state, got \(state)")
        }
    }
}
