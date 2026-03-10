import Foundation

struct TranscriptMergeSnapshot: Equatable, Sendable {
    let draftText: String
    let segments: [TranscriptSegment]
    let finalTranscript: Transcript?
    let displayText: String
    let currentTranscript: Transcript
}

actor TranscriptMerger {
    private var draftBuffer: String = ""
    private var appliedDeltaIDs: Set<String> = []
    private var segmentOrder: [String] = []
    private var segmentsByID: [String: TranscriptSegment] = [:]
    private var finalTranscript: Transcript?
    private let fallbackModelID: String
    private let fallbackResponseFormat: String

    init(fallbackModelID: String, fallbackResponseFormat: String = "text") {
        self.fallbackModelID = fallbackModelID
        self.fallbackResponseFormat = fallbackResponseFormat
    }

    func reset() {
        draftBuffer = ""
        appliedDeltaIDs.removeAll()
        segmentOrder.removeAll()
        segmentsByID.removeAll()
        finalTranscript = nil
    }

    @discardableResult
    func apply(_ event: TranscriptEvent) -> TranscriptMergeSnapshot {
        switch event {
        case .delta(let delta):
            if appliedDeltaIDs.insert(delta.id).inserted {
                draftBuffer.append(delta.text)
            }
        case .segment(let segment):
            if segmentsByID[segment.id] == nil {
                segmentOrder.append(segment.id)
            }
            segmentsByID[segment.id] = segment
        case .done(let transcript):
            finalTranscript = transcript
            draftBuffer = transcript.rawText
            appliedDeltaIDs.removeAll(keepingCapacity: true)
            segmentOrder = transcript.segments.map(\.id)
            segmentsByID = Dictionary(uniqueKeysWithValues: transcript.segments.map { ($0.id, $0) })
        }

        return makeSnapshot()
    }

    private func makeSnapshot() -> TranscriptMergeSnapshot {
        let orderedSegments = resolvedSegments()
        let displayText: String
        let currentTranscript: Transcript

        if let finalTranscript {
            displayText = finalTranscript.rawText
            currentTranscript = finalTranscript
        } else {
            if !orderedSegments.isEmpty {
                displayText = orderedSegments
                    .map(\.text)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            } else {
                displayText = draftBuffer
            }

            let segments = orderedSegments.isEmpty && !draftBuffer.isEmpty
                ? [TranscriptSegment(start: nil, end: nil, speaker: nil, text: draftBuffer)]
                : orderedSegments

            currentTranscript = Transcript(
                rawText: displayText,
                segments: segments,
                tokenLogprobs: nil,
                lowConfidenceSpans: [],
                modelID: fallbackModelID,
                responseFormat: fallbackResponseFormat
            )
        }

        return TranscriptMergeSnapshot(
            draftText: draftBuffer,
            segments: orderedSegments,
            finalTranscript: finalTranscript,
            displayText: displayText,
            currentTranscript: currentTranscript
        )
    }

    private func resolvedSegments() -> [TranscriptSegment] {
        let seeded = segmentOrder.compactMap { segmentsByID[$0] }

        return seeded.sorted { lhs, rhs in
            switch (lhs.start, rhs.start) {
            case let (.some(left), .some(right)):
                if left == right {
                    return lhs.id < rhs.id
                }
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.id < rhs.id
            }
        }
    }
}
