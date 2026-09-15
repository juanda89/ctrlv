import ControlVCore
import Foundation
import XCTest
@testable import InstantTranslator

final class FeedbackClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        FeedbackURLProtocolStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackURLProtocolStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        FeedbackURLProtocolStub.reset()
        super.tearDown()
    }

    func test_submit_postsFullPayload_toSubmitFeedback() async throws {
        FeedbackURLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/submit-feedback")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(request.httpBody ?? readStream(request.httpBodyStream))
            let payload = try JSONDecoder().decode(FeedbackSubmission.self, from: body)
            XCTAssertEqual(payload.rating, 4)
            XCTAssertEqual(payload.category, .idea)
            XCTAssertEqual(payload.message, "Add Portuguese slang")
            XCTAssertEqual(payload.installID, "install-1")
            XCTAssertEqual(payload.sessionToken, "tok")
            XCTAssertEqual(payload.appVersion, "2.3.0")
            XCTAssertEqual(payload.platform, "macos")
            return feedbackResponse(status: 200, json: #"{"ok":true,"emailed":true}"#)
        }
        let client = FeedbackClient(baseURL: URL(string: "https://api.example.com")!, session: session)

        try await client.submit(FeedbackSubmission(
            rating: 4, category: .idea, message: "Add Portuguese slang", contactEmail: nil,
            installID: "install-1", sessionToken: "tok", appVersion: "2.3.0"
        ))
    }

    func test_submit_mapsRateLimit_and_serverErrors() async {
        FeedbackURLProtocolStub.requestHandler = { _ in
            feedbackResponse(status: 429, json: #"{"error":"Too much feedback for today.","retry_after_seconds":3600}"#)
        }
        let client = FeedbackClient(baseURL: URL(string: "https://api.example.com")!, session: session)
        let submission = FeedbackSubmission(rating: 5, category: .praise, message: "", contactEmail: nil,
                                            installID: "i", sessionToken: nil, appVersion: "x")
        do {
            try await client.submit(submission)
            XCTFail("Expected rate limit")
        } catch let error as AuthError {
            guard case .rateLimited = error else { return XCTFail("Unexpected: \(error)") }
        } catch { XCTFail("Unexpected: \(error)") }

        FeedbackURLProtocolStub.requestHandler = { _ in feedbackResponse(status: 500, json: #"{"error":"Could not save feedback"}"#) }
        do {
            try await client.submit(submission)
            XCTFail("Expected server error")
        } catch let error as AuthError {
            guard case .server(let status, let message) = error else { return XCTFail("Unexpected: \(error)") }
            XCTAssertEqual(status, 500)
            XCTAssertEqual(message, "Could not save feedback")
        } catch { XCTFail("Unexpected: \(error)") }
    }
}

final class FeedbackPromptTrackerTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "tests.feedback.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func test_shouldInvite_onlyAfterThreshold_andNotAfterDismissOrSubmit() {
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let tracker = FeedbackPromptTracker(userDefaults: defaults)

        XCTAssertFalse(tracker.shouldInvite)
        for _ in 0..<(FeedbackPromptTracker.inviteThreshold - 1) { tracker.recordTranslation() }
        XCTAssertFalse(tracker.shouldInvite, "One short of the threshold must not invite")
        tracker.recordTranslation()
        XCTAssertTrue(tracker.shouldInvite)

        tracker.markDismissed()
        XCTAssertFalse(tracker.shouldInvite)

        let again = FeedbackPromptTracker(userDefaults: defaults)
        XCTAssertEqual(again.translationCount, FeedbackPromptTracker.inviteThreshold)
        XCTAssertTrue(again.isDismissed, "Dismissal must persist across launches")

        again.markSubmitted()
        XCTAssertTrue(again.hasSubmitted)
        XCTAssertFalse(again.shouldInvite)
    }
}

@MainActor
final class FeedbackViewModelTests: XCTestCase {
    private final class MockFeedbackClient: FeedbackClientProtocol {
        var submitted: [FeedbackSubmission] = []
        var error: Error?
        func submit(_ submission: FeedbackSubmission) async throws {
            if let error { throw error }
            submitted.append(submission)
        }
    }

    private func makeVM(client: MockFeedbackClient, rating: Int? = nil) -> (FeedbackViewModel, FeedbackPromptTracker) {
        let defaults = UserDefaults(suiteName: "tests.feedbackvm.\(UUID().uuidString)")!
        let tracker = FeedbackPromptTracker(userDefaults: defaults)
        let vm = FeedbackViewModel(client: client, tracker: tracker, installID: "install-1", sessionToken: "tok",
                                   contactEmail: "User@Example.com", appVersion: "2.3.0", initialRating: rating)
        return (vm, tracker)
    }

    func test_canSend_requiresRatingOrMessage() {
        let (vm, _) = makeVM(client: MockFeedbackClient())
        XCTAssertFalse(vm.canSend)
        vm.message = "   \n"
        XCTAssertFalse(vm.canSend, "Whitespace is not a message")
        vm.message = "hola"
        XCTAssertTrue(vm.canSend)
        vm.message = ""
        vm.rating = 5
        XCTAssertTrue(vm.canSend, "A rating alone is enough")
    }

    func test_send_submitsTrimmedPayload_andMarksTracker() async {
        let client = MockFeedbackClient()
        let (vm, tracker) = makeVM(client: client, rating: 3)
        vm.category = .bug
        vm.message = "  doesn't paste in Slack  \n"

        await vm.send()

        XCTAssertTrue(vm.didSend)
        XCTAssertNil(vm.lastError)
        XCTAssertTrue(tracker.hasSubmitted)
        let sent = client.submitted.first
        XCTAssertEqual(sent?.rating, 3)
        XCTAssertEqual(sent?.category, .bug)
        XCTAssertEqual(sent?.message, "doesn't paste in Slack")
        XCTAssertEqual(sent?.contactEmail, "user@example.com")
        XCTAssertEqual(sent?.sessionToken, "tok")
    }

    func test_send_surfacesError_andKeepsFormOpen() async {
        let client = MockFeedbackClient()
        client.error = AuthError.server(statusCode: 500, message: "Could not save feedback")
        let (vm, tracker) = makeVM(client: client, rating: 4)

        await vm.send()

        XCTAssertFalse(vm.didSend)
        XCTAssertEqual(vm.lastError, "Could not save feedback")
        XCTAssertFalse(tracker.hasSubmitted)
    }
}

// MARK: - Stub plumbing

private final class FeedbackURLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    static func reset() { requestHandler = nil }
}

private func feedbackResponse(status: Int, json: String) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: URL(string: "https://api.example.com")!, statusCode: status, httpVersion: nil,
                     headerFields: ["Content-Type": "application/json"])!, Data(json.utf8))
}

private func readStream(_ stream: InputStream?) -> Data? {
    guard let stream else { return nil }
    stream.open(); defer { stream.close() }
    let size = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size); defer { buffer.deallocate() }
    var data = Data()
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: size)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data.isEmpty ? nil : data
}
