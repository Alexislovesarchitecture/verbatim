import AVFoundation
import XCTest
@testable import VerbatimSwiftMVP

final class WhisperAudioLoaderTests: XCTestCase {
    func testLoadSamplesReadsReadyFormatDirectly() throws {
        let url = try makeAudioFile(
            sampleRate: 16_000,
            channelCount: 1,
            frameCount: 1_600
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try WhisperAudioLoader.loadSamples(from: url)

        XCTAssertEqual(samples.count, 1_600)
        XCTAssertNotNil(samples.first)
        XCTAssertEqual(Double(samples.first!), 0.25, accuracy: 0.001)
    }

    func testLoadSamplesConvertsNonTargetFormat() throws {
        let url = try makeAudioFile(
            sampleRate: 48_000,
            channelCount: 1,
            frameCount: 4_800
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try WhisperAudioLoader.loadSamples(from: url)

        XCTAssertFalse(samples.isEmpty)
        let peak = samples.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.1)
        XCTAssertLessThanOrEqual(peak, 0.3)
    }

    func testLoadSamplesRejectsEmptyAudioFile() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-whisper-empty-\(UUID().uuidString).wav")
        let _ = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try WhisperAudioLoader.loadSamples(from: url)) { error in
            guard case LocalTranscriptionError.invalidAudioFile(let message) = error else {
                return XCTFail("Expected invalidAudioFile, got \(error)")
            }
            XCTAssertTrue(message.contains("contained no audio samples"))
        }
    }

    private func makeAudioFile(
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        frameCount: AVAudioFrameCount
    ) throws -> URL {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-whisper-audio-\(UUID().uuidString).wav")
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        for channel in 0..<Int(channelCount) {
            let channelData = buffer.floatChannelData![channel]
            for index in 0..<Int(frameCount) {
                channelData[index] = channel == 0 ? 0.25 : 0.0
            }
        }

        try file.write(from: buffer)
        return url
    }
}
