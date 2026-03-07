import XCTest
@testable import VerbatimSwiftMVP

final class OpenAITranscriptionStreamingTests: XCTestCase {
    func testDecoderBuildsStableSyntheticIdentifiers() throws {
        let decoder = OpenAIStreamingEventDecoder()
        let payload = #"{"type":"transcript.delta","text":"hello","segments":[{"start":0.0,"end":0.5,"text":"hello"}]}"#

        let first = try decoder.decodeTranscriptEvents(
            payload: payload,
            eventID: nil,
            fallbackEventIndex: 7,
            modelID: "gpt-4o-mini-transcribe",
            responseFormat: "json"
        )
        let second = try decoder.decodeTranscriptEvents(
            payload: payload,
            eventID: nil,
            fallbackEventIndex: 7,
            modelID: "gpt-4o-mini-transcribe",
            responseFormat: "json"
        )

        guard case .delta(let firstDelta) = first[0],
              case .delta(let secondDelta) = second[0],
              case .segment(let firstSegment) = first[1],
              case .segment(let secondSegment) = second[1] else {
            return XCTFail("Expected delta + segment events")
        }

        XCTAssertEqual(firstDelta.id, "stream_7:delta")
        XCTAssertEqual(firstDelta.id, secondDelta.id)
        XCTAssertEqual(firstSegment.id, secondSegment.id)
    }

    func testDecoderEmitsDoneWithFinalTranscript() throws {
        let decoder = OpenAIStreamingEventDecoder()
        let payload = #"{"type":"transcript.completed","text":"final text","segments":[{"id":"seg-1","start":0.0,"end":1.0,"text":"final text"}]}"#

        let events = try decoder.decodeTranscriptEvents(
            payload: payload,
            eventID: "evt_final",
            fallbackEventIndex: 3,
            modelID: "gpt-4o-transcribe",
            responseFormat: "json"
        )

        guard case .segment(let segment) = events.first,
              case .done(let transcript) = events.last else {
            return XCTFail("Expected segment and done events")
        }

        XCTAssertEqual(segment.id, "seg-1")
        XCTAssertEqual(transcript.rawText, "final text")
        XCTAssertEqual(transcript.segments.map(\.id), ["seg-1"])
    }
}
