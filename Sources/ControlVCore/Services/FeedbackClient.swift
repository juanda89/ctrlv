import Foundation

public protocol FeedbackClientProtocol {
    func submit(_ submission: FeedbackSubmission) async throws
}

/// Posts feedback to the `submit-feedback` Edge Function. Errors are mapped
/// to `AuthError` so the UI can reuse the same user-facing messages.
public final class FeedbackClient: FeedbackClientProtocol {
    private let baseURL: URL?
    private let session: URLSession

    public init(baseURL: URL? = Constants.authAPIBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func submit(_ submission: FeedbackSubmission) async throws {
        guard let baseURL else { throw AuthError.missingBaseURL }
        var request = URLRequest(url: baseURL.appendingPathComponent("submit-feedback"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(submission)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }

        if http.statusCode == 429 {
            let body = try? JSONDecoder().decode(FeedbackErrorResponse.self, from: data)
            throw AuthError.rateLimited(retryAfterSeconds: body?.retryAfterSeconds)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(FeedbackErrorResponse.self, from: data)
            throw AuthError.server(statusCode: http.statusCode, message: body?.error ?? "Could not send feedback")
        }
    }
}

private struct FeedbackErrorResponse: Decodable {
    let error: String?
    let retryAfterSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case error
        case retryAfterSeconds = "retry_after_seconds"
    }
}
