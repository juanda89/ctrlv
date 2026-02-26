import Foundation
import XCTest
@testable import InstantTranslator

final class APIKeyValidationServiceTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        APIKeyURLProtocolStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIKeyURLProtocolStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        APIKeyURLProtocolStub.reset()
        super.tearDown()
    }

    func test_validate_returnsValid_whenOpenAIReturns200() async {
        APIKeyURLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            return makeValidationResponse(statusCode: 200, json: #"{"data":[]}"#)
        }

        let service = APIKeyValidationService(session: session)
        let result = await service.validate(apiKey: "sk-test", for: .openAI)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.message.contains("verified"))
    }

    func test_validate_returnsInvalid_whenClaudeReturns401() async {
        APIKeyURLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
            return makeValidationResponse(
                statusCode: 401,
                json: #"{"error":{"message":"invalid x-api-key"}}"#
            )
        }

        let service = APIKeyValidationService(session: session)
        let result = await service.validate(apiKey: "sk-ant-test", for: .claude)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.message.contains("Invalid Claude API key"))
    }

    func test_validate_returnsValid_whenGeminiReturns429() async {
        APIKeyURLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1beta/models")
            XCTAssertEqual(request.httpMethod, "GET")
            return makeValidationResponse(statusCode: 429, json: #"{"error":{"message":"quota exceeded"}}"#)
        }

        let service = APIKeyValidationService(session: session)
        let result = await service.validate(apiKey: "AIza-test", for: .gemini)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.message.contains("rate limited"))
    }

    func test_validate_returnsNetworkMessage_whenRequestFails() async {
        APIKeyURLProtocolStub.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let service = APIKeyValidationService(session: session)
        let result = await service.validate(apiKey: "sk-test", for: .openAI)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.message.contains("Could not validate key"))
    }
}

private final class APIKeyURLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        requestHandler = nil
    }
}

private func makeValidationResponse(statusCode: Int, json: String) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: URL(string: "https://validation.test/mock")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(json.utf8))
}
