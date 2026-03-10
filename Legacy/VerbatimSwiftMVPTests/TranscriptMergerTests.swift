import XCTest
@testable import VerbatimSwiftMVP

final class TranscriptMergerTests: XCTestCase {
    func testDeltaEventsAppendAndRemainIdempotentByDeltaID() async {
        let sut = TranscriptMerger(fallbackModelID: "gpt-4o-mini-transcribe")

        let deltaA = TranscriptDelta(id: "d1", text: "hello")
        let deltaB = TranscriptDelta(id: "d2", text: " world")

        _ = await sut.apply(.delta(deltaA))
        _ = await sut.apply(.delta(deltaA))
        let snapshot = await sut.apply(.delta(deltaB))

        XCTAssertEqual(snapshot.draftText, "hello world")
        XCTAssertEqual(snapshot.displayText, "hello world")
        XCTAssertEqual(snapshot.currentTranscript.rawText, "hello world")
    }

    func testSegmentEventsReplaceBySegmentIDWithoutDuplication() async {
        let sut = TranscriptMerger(fallbackModelID: "gpt-4o-transcribe")

        let first = TranscriptSegment(id: "s1", start: 0.0, end: 1.0, speaker: nil, text: "first")
        let replacement = TranscriptSegment(id: "s1", start: 0.0, end: 1.0, speaker: nil, text: "first revised")
        let second = TranscriptSegment(id: "s2", start: 1.1, end: 2.0, speaker: nil, text: "second")

        _ = await sut.apply(.segment(first))
        _ = await sut.apply(.segment(replacement))
        let snapshot = await sut.apply(.segment(second))

        XCTAssertEqual(snapshot.segments.count, 2)
        XCTAssertEqual(snapshot.segments.map(\.id), ["s1", "s2"])
        XCTAssertEqual(snapshot.segments[0].text, "first revised")
        XCTAssertEqual(snapshot.displayText, "first revised\nsecond")
    }

    func testDoneEventBecomesAuthoritativeAndIsIdempotent() async {
        let sut = TranscriptMerger(fallbackModelID: "gpt-4o-transcribe")

        _ = await sut.apply(.delta(TranscriptDelta(id: "d1", text: "draft")))

        let final = Transcript(
            rawText: "final text",
            segments: [TranscriptSegment(id: "s1", start: nil, end: nil, speaker: nil, text: "final text")],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: "gpt-4o-transcribe",
            responseFormat: "json"
        )

        _ = await sut.apply(.done(final))
        let reapplied = await sut.apply(.done(final))

        XCTAssertEqual(reapplied.finalTranscript?.rawText, "final text")
        XCTAssertEqual(reapplied.displayText, "final text")
        XCTAssertEqual(reapplied.currentTranscript.rawText, "final text")
        XCTAssertEqual(reapplied.currentTranscript.segments.count, 1)
    }

    func testSegmentsAreRenderedInStartTimeOrder() async {
        let sut = TranscriptMerger(fallbackModelID: "gpt-4o-transcribe")

        _ = await sut.apply(.segment(TranscriptSegment(id: "later", start: 2.0, end: 3.0, speaker: nil, text: "later")))
        let snapshot = await sut.apply(.segment(TranscriptSegment(id: "earlier", start: 1.0, end: 1.5, speaker: nil, text: "earlier")))

        XCTAssertEqual(snapshot.segments.map(\.id), ["earlier", "later"])
        XCTAssertEqual(snapshot.displayText, "earlier\nlater")
    }
}
