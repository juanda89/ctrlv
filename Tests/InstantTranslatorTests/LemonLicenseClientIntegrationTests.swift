import Foundation
import XCTest
@testable import InstantTranslator

final class LemonLicenseClientIntegrationTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        URLProtocolStub.reset()
        super.tearDown()
    }

    func test_activateAndValidate_returnsSuccess_whenServerReturnsActiveResponses() async throws {
        URLProtocolStub.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == "/v1/licenses/activate" {
                return makeResponse(
                    statusCode: 200,
                    json: """
                    {
                      "activated": true,
                      "instance": { "id": "instance-1" },
                      "license_key": { "variant_name": "Pro Plan" }
                    }
                    """
                )
            }
            return makeResponse(
                statusCode: 200,
                json: """
                {
                  "valid": true,
                  "instance": { "id": "instance-1" },
                  "license_key": {
                    "status": "active",
                    "variant_name": "Pro Plan"
                  }
                }
                """
            )
        }

        let client = LemonLicenseClient(
            baseURL: URL(string: "https://license.test")!,
            session: session
        )

        let activation = try await client.activate(licenseKey: "test-key", instanceName: "Test Mac")
        let validation = try await client.validate(licenseKey: "test-key", instanceID: activation.instanceID)

        XCTAssertEqual(activation.instanceID, "instance-1")
        XCTAssertEqual(activation.planName, "Pro Plan")
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.status, .active)
        XCTAssertEqual(validation.planName, "Pro Plan")
    }

    func test_activate_throwsActivationFailed_whenServerReturnsActivationLimitReached() async {
        URLProtocolStub.requestHandler = { _ in
            makeResponse(
                statusCode: 200,
                json: """
                {
                  "activated": false,
                  "error": "Activation limit reached"
                }
                """
            )
        }

        let client = LemonLicenseClient(
            baseURL: URL(string: "https://license.test")!,
            session: session
        )

        do {
            _ = try await client.activate(licenseKey: "test-key", instanceName: "Test Mac")
            XCTFail("Expected activation failure")
        } catch let error as LemonLicenseError {
            guard case .activationFailed(let message) = error else {
                return XCTFail("Unexpected Lemon error: \(error)")
            }
            XCTAssertTrue(message.contains("Activation limit"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_validate_returnsInvalid_whenServerReturnsExpiredStatus() async throws {
        URLProtocolStub.requestHandler = { _ in
            makeResponse(
                statusCode: 200,
                json: """
                {
                  "valid": false,
                  "error": "License expired",
                  "license_key": { "status": "expired" }
                }
                """
            )
        }

        let client = LemonLicenseClient(
            baseURL: URL(string: "https://license.test")!,
            session: session
        )

        let validation = try await client.validate(licenseKey: "test-key", instanceID: "instance-1")

        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.status, .expired)
        XCTAssertEqual(validation.reason, "License expired")
    }

    func test_validate_throwsNetworkError_whenRequestTimesOut() async {
        URLProtocolStub.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let client = LemonLicenseClient(
            baseURL: URL(string: "https://license.test")!,
            session: session
        )

        do {
            _ = try await client.validate(licenseKey: "test-key", instanceID: "instance-1")
            XCTFail("Expected timeout error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

private final class URLProtocolStub: URLProtocol {
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

private func makeResponse(statusCode: Int, json: String) -> (HTTPURLResponse, Data) {
    let data = Data(json.utf8)
    let response = HTTPURLResponse(
        url: URL(string: "https://license.test/mock")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
}
