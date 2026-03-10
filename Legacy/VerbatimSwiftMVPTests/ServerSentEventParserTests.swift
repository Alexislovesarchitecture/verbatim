import XCTest
@testable import VerbatimSwiftMVP

final class ServerSentEventParserTests: XCTestCase {
    func testParseCollectsMultilineDataAndIgnoresComments() async throws {
        let parser = ServerSentEventParser()
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(": keep-alive")
            continuation.yield("event: transcript")
            continuation.yield("id: evt_1")
            continuation.yield("data: {\"text\":\"hello\"}")
            continuation.yield("data: {\"text\":\"world\"}")
            continuation.yield("")
            continuation.yield("data: [DONE]")
            continuation.yield("")
            continuation.finish()
        }

        var events: [ServerSentEvent] = []
        for try await event in parser.parse(lines: lines) {
            events.append(event)
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].event, "transcript")
        XCTAssertEqual(events[0].id, "evt_1")
        XCTAssertEqual(events[0].data, "{\"text\":\"hello\"}\n{\"text\":\"world\"}")
        XCTAssertEqual(events[1].data, "[DONE]")
    }
}
