import Foundation

protocol MagicCodeAuthClientProtocol {
    func requestMagicCode(email: String) async throws
    func verifyMagicCode(email: String, code: String) async throws -> String
    func refreshSubscriptionStatus(token: String) async throws -> SubscriptionStatus
    func createCheckoutSession(token: String) async throws -> URL
    func createPortalSession(token: String) async throws -> URL
}

enum AuthError: LocalizedError {
    case missingBaseURL
    case invalidResponse
    case rateLimited(retryAfterSeconds: Int?)
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL: return "Auth service not configured"
        case .invalidResponse: return "Invalid server response"
        case .rateLimited(let retry):
            if let retry = retry {
                let minutes = max(1, retry / 60)
                return "Too many requests. Try again in \(minutes) minute\(minutes == 1 ? "" : "s")."
            }
            return "Too many requests. Try again in a few minutes."
        case .server(_, let message): return message
        }
    }
}

final class MagicCodeAuthClient: MagicCodeAuthClientProtocol {
    private let baseURL: URL?
    private let session: URLSession

    init(baseURL: URL? = Constants.authAPIBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func requestMagicCode(email: String) async throws {
        let url = try endpoint("/request-magic-code")
        let payload = ["email": email]
        let _: EmptyResponse = try await postJSON(url: url, payload: payload, bearerToken: nil)
    }

    func verifyMagicCode(email: String, code: String) async throws -> String {
        let url = try endpoint("/verify-magic-code")
        let payload = ["email": email, "code": code]
        let response: SessionTokenResponse = try await postJSON(url: url, payload: payload, bearerToken: nil)
        return response.sessionToken
    }

    func refreshSubscriptionStatus(token: String) async throws -> SubscriptionStatus {
        let url = try endpoint("/subscription-status")
        let response: SubscriptionStatusResponse = try await postJSON(url: url, payload: EmptyPayload(), bearerToken: token)
        return SubscriptionStatus(
            status: SubscriptionStatusValue(raw: response.status),
            planName: response.planName,
            trialDaysRemaining: response.trialDaysRemaining
        )
    }

    func createCheckoutSession(token: String) async throws -> URL {
        let url = try endpoint("/create-checkout-session")
        let response: URLResponse = try await postJSON(url: url, payload: EmptyPayload(), bearerToken: token)
        guard let result = URL(string: response.url) else {
            throw AuthError.invalidResponse
        }
        return result
    }

    func createPortalSession(token: String) async throws -> URL {
        let url = try endpoint("/create-portal-session")
        let response: URLResponse = try await postJSON(url: url, payload: EmptyPayload(), bearerToken: token)
        guard let result = URL(string: response.url) else {
            throw AuthError.invalidResponse
        }
        return result
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let baseURL = baseURL else { throw AuthError.missingBaseURL }
        return baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func postJSON<P: Encodable, R: Decodable>(
        url: URL,
        payload: P,
        bearerToken: String?
    ) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken = bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            let body = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.rateLimited(retryAfterSeconds: body?.retryAfterSeconds)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.server(
                statusCode: httpResponse.statusCode,
                message: body?.error ?? "Request failed"
            )
        }

        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw AuthError.invalidResponse
        }
    }
}

private struct EmptyPayload: Encodable {}
private struct EmptyResponse: Decodable {}

private struct SessionTokenResponse: Decodable {
    let sessionToken: String
}

private struct SubscriptionStatusResponse: Decodable {
    let status: String
    let planName: String?
    let trialDaysRemaining: Int?
}

private struct URLResponse: Decodable {
    let url: String
}

private struct ErrorResponse: Decodable {
    let error: String?
    let retryAfterSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case error
        case retryAfterSeconds = "retry_after_seconds"
    }
}
