import XCTest
import Foundation
@testable import Verbatim

@MainActor
final class LocalWhisperClientTests: XCTestCase {
    private let client = LocalWhisperClient()

    func testParsesObjectTextPayload() throws {
        let payload = #"{"text":"Hello\nworld"}"#.data(using: .utf8)!
        let parsed = try client.parseResponse(payload)
        XCTAssertEqual(parsed, "Hello world")
    }

    func testParsesObjectTranscriptionPayload() throws {
        let payload = #"{"transcription":[{"text":"hello"},{"text":"world"}]}"#.data(using: .utf8)!
        let parsed = try client.parseResponse(payload)
        XCTAssertEqual(parsed, "hello world")
    }

    func testParsesPlainTextPayload() throws {
        let payload = "Hello\nfrom\nplain".data(using: .utf8)!
        let parsed = try client.parseResponse(payload)
        XCTAssertEqual(parsed, "Hello from plain")
    }

    func testParsesJsonStringPayload() throws {
        let payload = "\"Hello\\nthere\"".data(using: .utf8)!
        let parsed = try client.parseResponse(payload)
        XCTAssertEqual(parsed, "Hello there")
    }

    func testRejectsBlankMarker() {
        let payload = "[BLANK_AUDIO]".data(using: .utf8)!
        XCTAssertThrowsError(try client.parseResponse(payload)) { error in
            guard let typed = error as? TranscriptionEngineError else {
                return XCTFail("Expected TranscriptionEngineError")
            }
            guard case .emptyTranscript = typed else {
                return XCTFail("Expected emptyTranscript, got \(typed)")
            }
        }
    }
}

@MainActor
final class WhisperModelCatalogTests: XCTestCase {
    func testNormalizedModelIdFallsBackToBase() {
        XCTAssertEqual(WhisperModelCatalog.normalizedModelId("BASE"), "base")
        XCTAssertEqual(WhisperModelCatalog.normalizedModelId("nope"), "base")
        XCTAssertEqual(WhisperModelCatalog.normalizedModelId(""), "base")
    }
}
