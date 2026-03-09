import AVFoundation
import Foundation

enum CanonicalAudioFileWriter {
    private static let sampleRate: Double = 16_000
    private static let channelCount: AVAudioChannelCount = 1

    static func materializeCanonicalWAV(
        from sourceURL: URL,
        outputDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw LocalTranscriptionError.missingAudioFile
        }

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let inputFile = try AVAudioFile(forReading: sourceURL)
        guard inputFile.length > 0 else {
            throw LocalTranscriptionError.invalidAudioFile("Recorded audio file contained no audio samples. Try recording again.")
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not configure canonical audio conversion.")
        }

        let outputURL = outputDirectory.appendingPathComponent("canonical-\(UUID().uuidString).wav")
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: targetFormat.settings,
            commonFormat: targetFormat.commonFormat,
            interleaved: targetFormat.isInterleaved
        )

        if inputFile.processingFormat.commonFormat == .pcmFormatFloat32,
           inputFile.processingFormat.channelCount == channelCount,
           abs(inputFile.processingFormat.sampleRate - sampleRate) < 0.5,
           inputFile.processingFormat.isInterleaved == false {
            try copyFile(inputFile, to: outputFile)
            return outputURL
        }

        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: targetFormat) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not create canonical audio converter.")
        }

        let inputFrameCapacity = try wholeFileFrameCapacity(for: inputFile)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: inputFrameCapacity
        ) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not allocate input audio buffer.")
        }

        try inputFile.read(into: inputBuffer)
        guard inputBuffer.frameLength > 0 else {
            throw LocalTranscriptionError.invalidAudioFile("Recorded audio file contained no audio samples. Try recording again.")
        }

        let convertedFrameEstimate = Int(
            ceil(Double(inputBuffer.frameLength) * sampleRate / inputFile.processingFormat.sampleRate)
        ) + 64
        let outputFrameCapacity = AVAudioFrameCount(
            max(Int(inputBuffer.frameLength), max(1, convertedFrameEstimate))
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not allocate output audio buffer.")
        }

        var didConsumeInput = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if didConsumeInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            didConsumeInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion failed: \(conversionError.localizedDescription)")
        }

        switch status {
        case .haveData, .endOfStream:
            break
        case .inputRanDry:
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion ran dry before producing output.")
        case .error:
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion failed.")
        @unknown default:
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion returned an unknown status.")
        }

        guard convertedBuffer.frameLength > 0 else {
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion produced no samples.")
        }

        try outputFile.write(from: convertedBuffer)
        return outputURL
    }

    private static func copyFile(_ inputFile: AVAudioFile, to outputFile: AVAudioFile) throws {
        let frameCapacity = try wholeFileFrameCapacity(for: inputFile)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: frameCapacity
        ) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not allocate audio buffer.")
        }

        try inputFile.read(into: buffer)
        guard buffer.frameLength > 0 else {
            throw LocalTranscriptionError.invalidAudioFile("Recorded audio file contained no audio samples. Try recording again.")
        }
        try outputFile.write(from: buffer)
    }

    private static func wholeFileFrameCapacity(for inputFile: AVAudioFile) throws -> AVAudioFrameCount {
        guard inputFile.length > 0 else {
            throw LocalTranscriptionError.invalidAudioFile("Recorded audio file contained no audio samples. Try recording again.")
        }
        guard inputFile.length <= Int64(UInt32.max) else {
            throw LocalTranscriptionError.invalidAudioFile("Recorded audio file is too large for local Whisper.")
        }
        return AVAudioFrameCount(inputFile.length)
    }
}
