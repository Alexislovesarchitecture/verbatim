import Foundation

struct AudioActivityAnalyzer {
    struct Thresholds: Equatable, Sendable {
        let minimumDuration: TimeInterval
        let minimumVoicedDuration: TimeInterval
        let minimumVoicedRatio: Double
        let rmsSpeechThreshold: Double
        let peakSpeechThreshold: Double

        static func forSensitivity(_ sensitivity: SilenceSensitivity) -> Thresholds {
            switch sensitivity {
            case .low:
                return Thresholds(
                    minimumDuration: 0.25,
                    minimumVoicedDuration: 0.08,
                    minimumVoicedRatio: 0.10,
                    rmsSpeechThreshold: 0.010,
                    peakSpeechThreshold: 0.030
                )
            case .normal:
                return Thresholds(
                    minimumDuration: 0.30,
                    minimumVoicedDuration: 0.12,
                    minimumVoicedRatio: 0.14,
                    rmsSpeechThreshold: 0.013,
                    peakSpeechThreshold: 0.045
                )
            case .high:
                return Thresholds(
                    minimumDuration: 0.40,
                    minimumVoicedDuration: 0.18,
                    minimumVoicedRatio: 0.18,
                    rmsSpeechThreshold: 0.017,
                    peakSpeechThreshold: 0.060
                )
            }
        }
    }

    func analyze(frames: AsyncStream<AudioPCM16Frame>, sensitivity: SilenceSensitivity = .normal) async -> AudioActivitySummary {
        let thresholds = Thresholds.forSensitivity(sensitivity)
        var totalDuration: TimeInterval = 0
        var voicedDuration: TimeInterval = 0
        var peakLevel: Double = 0
        var weightedPowerSum: Double = 0

        for await frame in frames {
            let frameDuration = frame.sampleRate > 0
                ? Double(frame.sampleCount) / frame.sampleRate
                : 0
            totalDuration += frameDuration

            let metrics = metrics(for: frame)
            peakLevel = max(peakLevel, metrics.peak)
            weightedPowerSum += metrics.rms * frameDuration

            if metrics.rms >= thresholds.rmsSpeechThreshold || metrics.peak >= thresholds.peakSpeechThreshold {
                voicedDuration += frameDuration
            }
        }

        let averagePower = totalDuration > 0 ? weightedPowerSum / totalDuration : 0
        let speechDetected = voicedDuration > 0

        return AudioActivitySummary(
            averagePower: averagePower,
            peakLevel: peakLevel,
            voicedDuration: voicedDuration,
            totalDuration: totalDuration,
            speechDetected: speechDetected
        )
    }

    func shouldSkipTranscription(
        summary: AudioActivitySummary,
        settings: InteractionSettings
    ) -> Bool {
        guard settings.silenceDetectionEnabled else {
            return false
        }

        let thresholds = Thresholds.forSensitivity(settings.silenceSensitivity)
        if summary.totalDuration < thresholds.minimumDuration {
            return !settings.alwaysTranscribeShortRecordings
        }

        if summary.voicedDuration < thresholds.minimumVoicedDuration {
            return true
        }

        return summary.voicedRatio < thresholds.minimumVoicedRatio
            && summary.peakLevel < thresholds.peakSpeechThreshold
    }

    private func metrics(for frame: AudioPCM16Frame) -> (rms: Double, peak: Double) {
        guard frame.sampleCount > 0 else {
            return (0, 0)
        }

        var sumOfSquares = 0.0
        var peak = 0.0

        frame.samples.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let normalized = abs(Double(sample)) / 32_768.0
                peak = max(peak, normalized)
                sumOfSquares += normalized * normalized
            }
        }

        let rms = sqrt(sumOfSquares / Double(frame.sampleCount))
        return (rms, peak)
    }
}
