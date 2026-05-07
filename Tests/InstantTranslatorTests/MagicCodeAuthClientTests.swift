import Foundation
import XCTest
@testable import InstantTranslator

final class MagicCodeAuthClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        AuthURLProtocolStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        AuthURLProtocolStub.reset()
        super.tearDown()
    }

    func test_requestMagicCode_postsCorrectPayload() async throws {
        AuthURLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/request-magic-code")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(request.httpBody ?? readBody(request.httpBodyStream))
            let payload = try JSONDecoder().decode([String: String].self, from: body)
            XCTAssertEqual(payload["email"], "user@example.com")

            return makeResponse(statusCode: 200, json: #"{"ok":true}"#)
        }

        let client = MagicCodeAuthClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: session
        )

        try await client.requestMagicCode(email: "user@example.com")
    }

    func test_verifyMagicCode_returnsSessionToken() async throws {
        AuthURLProtocolStub.requestHandler = { _ in
            makeResponse(statusCode: 200, json: #"{"sessionToken":"tok-abc-123"}"#)
        }

        let client = MagicCodeAuthClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: session
        )

        let token = try await client.verifyMagicCode(email: "u@x.com", code: "123456")
        XCTAssertEqual(token, "tok-abc-123")
    }

    func test_refreshSubscriptionStatus_decodesActive() async throws {
        AuthURLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-token")
            return makeResponse(
                statusCode: 200,
                json: #"{"status":"active","planName":"Pro","trialDaysRemaining":null}"#
            )
        }

        let client = MagicCodeAuthClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: session
        )

        let status = try await client.refreshSubscriptionStatus(token: "my-token")
        XCTAssertEqual(status.status, .active)
        XCTAssertEqual(status.planName, "Pro")
    }

    func test_createCheckoutSession_returnsURL() async throws {
        AuthURLProtocolStub.requestHandler = { _ in
            makeResponse(
                statusCode: 200,
                json: #"{"url":"https://checkout.stripe.com/abc","sessionId":"cs_test_123"}"#
            )
        }

        let client = MagicCodeAuthClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: session
        )

        let url = try await client.createCheckoutSession(token: "tok")
        XCTAssertEqual(url.absoluteString, "https://checkout.stripe.com/abc")
    }

    func test_request_throwsRateLimited_whenServerReturns429() async {
        AuthURLProtocolStub.requestHandler = { _ in
            makeResponse(statusCode: 429, json: #"{"error":"slow down","retry_after_seconds":120}"#)
        }

        let client = MagicCodeAuthClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: session
        )

        do {
            try await client.requestMagicCode(email: "u@x.com")
            XCTFail("Expected rate-limited error")
        } catch let error as AuthError {
            guard case .rateLimited(let retry) = error else {
                return XCTFail("Unexpected: \(error)")
            }
            XCTAssertEqual(retry, 120)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_request_throwsServerError_whenNon2xx() async {
        AuthURLProtocolStub.requestHandler = { _ in
            makeResponse(statusCode: 500, json: #"{"error":"oops"}"#)
        }

        let client = MagicCodeAuthClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: session
        )

        do {
            try await client.requestMagicCode(email: "u@x.com")
            XCTFail("Expected error")
        } catch let error as AuthError {
            guard case .server(let status, _) = error else {
                return XCTFail("Unexpected: \(error)")
            }
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Stub plumbing

private final class AuthURLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

    static func reset() { requestHandler = nil }
}

private func makeResponse(statusCode: Int, json: String) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: URL(string: "https://api.example.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(json.utf8))
}

private func readBody(_ stream: InputStream?) -> Data? {
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
