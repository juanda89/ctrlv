import Foundation
import XCTest
@testable import InstantTranslator

final class CtrlVCloudProviderTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        CloudProviderURLProtocolStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudProviderURLProtocolStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        CloudProviderURLProtocolStub.reset()
        super.tearDown()
    }

    func test_translate_returnsTranslatedText_whenGatewaySucceeds() async throws {
        CloudProviderURLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(request.httpBody ?? requestBody(from: request.httpBodyStream))
            let payload = try JSONDecoder().decode(TestGatewayPayload.self, from: body)
            XCTAssertEqual(payload.installID, "install-1")
            XCTAssertEqual(payload.licenseKey, "license-1")
            XCTAssertEqual(payload.licenseInstanceID, "instance-1")
            return makeCloudResponse(
                statusCode: 200,
                json: #"{"translatedText":"Hola","model":"moonshotai/kimi-k2.5","plan":"trial"}"#
            )
        }

        let provider = CtrlVCloudProvider(
            endpoint: URL(string: "https://example.com/translate")!,
            installID: "install-1",
            licenseKey: "license-1",
            licenseInstanceID: "instance-1",
            session: session
        )

        let translated = try await provider.translate(text: "Hello", systemPrompt: "Translate to Spanish")

        XCTAssertEqual(translated, "Hola")
    }

    func test_translate_throwsRateLimited_whenGatewayReturns429() async {
        CloudProviderURLProtocolStub.requestHandler = { _ in
            makeCloudResponse(
                statusCode: 429,
                json: #"{"error":"rate limited","retry_after_seconds":42}"#
            )
        }

        let provider = CtrlVCloudProvider(
            endpoint: URL(string: "https://example.com/translate")!,
            installID: "install-1",
            licenseKey: nil,
            licenseInstanceID: nil,
            session: session
        )

        do {
            _ = try await provider.translate(text: "Hello", systemPrompt: "Translate")
            XCTFail("Expected rate limit error")
        } catch let error as TranslationError {
            guard case let .rateLimited(providerType, retryAfter) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(providerType, .ctrlVCloud)
            XCTAssertEqual(retryAfter, 42)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_warmup_sendsWarmupPayload_whenRequested() async throws {
        CloudProviderURLProtocolStub.requestHandler = { request in
            let body = try XCTUnwrap(request.httpBody ?? requestBody(from: request.httpBodyStream))
            let payload = try JSONDecoder().decode(TestGatewayWarmupPayload.self, from: body)
            XCTAssertEqual(payload.text, "hola")
            XCTAssertEqual(payload.installID, "install-1")
            XCTAssertTrue(payload.warmupOnly)
            return makeCloudResponse(
                statusCode: 200,
                json: #"{"warmed":true,"model":"moonshotai/kimi-k2.5"}"#
            )
        }

        let provider = CtrlVCloudProvider(
            endpoint: URL(string: "https://example.com/translate")!,
            installID: "install-1",
            licenseKey: "license-1",
            licenseInstanceID: "instance-1",
            session: session
        )

        try await provider.warmup(systemPrompt: "Translate to English")
    }
}

private struct TestGatewayPayload: Decodable {
    let installID: String
    let licenseKey: String?
    let licenseInstanceID: String?
}

private struct TestGatewayWarmupPayload: Decodable {
    let text: String
    let installID: String
    let warmupOnly: Bool
}

private final class CloudProviderURLProtocolStub: URLProtocol {
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

private func makeCloudResponse(statusCode: Int, json: String) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: URL(string: "https://example.com/translate")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(json.utf8))
}

private func requestBody(from stream: InputStream?) -> Data? {
    guard let stream else { return nil }

    stream.open()
    defer { stream.close() }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data.isEmpty ? nil : data
}
