import Foundation
import XCTest
@testable import VerbatimSwiftMVP

final class WhisperModelManagerTests: XCTestCase {
    func testDownloadModelStagesItForInstall() async throws {
        let tempRoot = makeTempRoot()
        let manager = makeManager(tempRoot: tempRoot)

        let state = await manager.downloadModel(.whisperBase)

        if case .downloaded(let stagedURL) = state {
            XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        } else {
            XCTFail("Expected downloaded state, got \(state)")
        }
    }

    func testInstallModelMovesStagedFileIntoReadyState() async throws {
        let tempRoot = makeTempRoot()
        let manager = makeManager(tempRoot: tempRoot)

        _ = await manager.downloadModel(.whisperBase)
        let state = await manager.installModel(.whisperBase)
        let installedURL = await manager.installedModelURL(for: .whisperBase)

        if case .ready = state {
            XCTAssertNotNil(installedURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: installedURL!.path))
        } else {
            XCTFail("Expected ready state, got \(state)")
        }
    }

    func testInstalledModelPersistsAcrossManagerReload() async throws {
        let tempRoot = makeTempRoot()
        let manager = makeManager(tempRoot: tempRoot)

        _ = await manager.downloadModel(.whisperBase)
        _ = await manager.installModel(.whisperBase)

        let reloaded = makeManager(tempRoot: tempRoot)
        let state = await reloaded.installState(for: .whisperBase)

        if case .ready = state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected ready state after reload, got \(state)")
        }
    }

    func testRemoveModelClearsStagedAndInstalledFiles() async throws {
        let tempRoot = makeTempRoot()
        let manager = makeManager(tempRoot: tempRoot)

        _ = await manager.downloadModel(.whisperBase)
        _ = await manager.installModel(.whisperBase)
        try await manager.removeModel(.whisperBase)

        let state = await manager.installState(for: .whisperBase)
        if case .notDownloaded = state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected notDownloaded state, got \(state)")
        }
    }

    private func makeManager(tempRoot: URL) -> WhisperModelManager {
        WhisperModelManager(
            baseDirectoryURL: tempRoot,
            manifest: testManifest,
            downloadHandler: { _ in
                let downloadedURL = tempRoot.appendingPathComponent("downloaded-model.bin")
                try Data(count: 64).write(to: downloadedURL)
                return downloadedURL
            },
            runtimeStatusProvider: {
                WhisperRuntimeStatus(
                    isSupported: true,
                    message: "Whisper runtime ready."
                )
            }
        )
    }

    private func makeTempRoot() -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-whisper-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        return tempRoot
    }

    private var testManifest: [LocalTranscriptionModel: WhisperDownloadManifestEntry] {
        [
            .whisperBase: WhisperDownloadManifestEntry(
                model: .whisperBase,
                backendModelName: "base",
                fileName: "ggml-base.bin",
                downloadURL: URL(string: "https://example.com/ggml-base.bin")!,
                approximateSizeLabel: "64 B",
                qualityNote: "Test model",
                minimumValidBytes: 32
            )
        ]
    }
}
