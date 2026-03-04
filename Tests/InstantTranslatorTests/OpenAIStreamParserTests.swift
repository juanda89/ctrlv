import XCTest
@testable import InstantTranslator

final class OpenAIStreamParserTests: XCTestCase {

    func test_parse_returnsContentEvent_whenPayloadContainsDeltaText() throws {
        let parser = OpenAIStreamEventParser()
        let line = #"data: {"choices":[{"delta":{"content":"Hola "}}]}"#
        let event = try parser.parse(line: line)
        XCTAssertEqual(event, .content("Hola "))
    }

    func test_parse_returnsDoneEvent_whenPayloadIsDoneMarker() throws {
        let parser = OpenAIStreamEventParser()
        let event = try parser.parse(line: "data: [DONE]")
        XCTAssertEqual(event, .done)
    }

    func test_parse_returnsIgnoreEvent_whenLineHasNoDataPrefix() throws {
        let parser = OpenAIStreamEventParser()
        let event = try parser.parse(line: "event: ping")
        XCTAssertEqual(event, .ignore)
    }

    func test_parse_returnsIgnoreEvent_whenDeltaHasNoContent() throws {
        let parser = OpenAIStreamEventParser()
        let line = #"data: {"choices":[{"delta":{}}]}"#
        let event = try parser.parse(line: line)
        XCTAssertEqual(event, .ignore)
    }

    func test_parse_throwsApiError_whenPayloadIsMalformedJSON() {
        let parser = OpenAIStreamEventParser()
        do {
            _ = try parser.parse(line: "data: {not-json}")
            XCTFail("Expected malformed payload error")
        } catch let error as TranslationError {
            guard case .apiError = error else {
                XCTFail("Expected apiError, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
