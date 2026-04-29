import Foundation

struct CtrlVCloudProvider: TranslationProvider {
    let endpoint: URL
    let installID: String
    let sessionToken: String?
    let session: URLSession

    init(
        endpoint: URL,
        installID: String,
        sessionToken: String?,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.installID = installID
        self.sessionToken = sessionToken
        self.session = session
    }

    func translate(text: String, systemPrompt: String) async throws -> String {
        let data = try await performRequest(
            payload: GatewayTranslationRequest(
                text: text,
                systemPrompt: systemPrompt,
                installID: installID,
                sessionToken: normalized(sessionToken),
                warmupOnly: false
            )
        )

        let decoded = try JSONDecoder().decode(GatewayTranslationResponse.self, from: data)
        return decoded.translatedText
    }

    func warmup(systemPrompt: String) async throws {
        _ = try await performRequest(
            payload: GatewayTranslationRequest(
                text: "hola",
                systemPrompt: systemPrompt,
                installID: installID,
                sessionToken: nil,
                warmupOnly: true
            )
        )
    }

    private func performRequest(payload: GatewayTranslationRequest) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.networkError(underlying: URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 429 {
            let body = try? JSONDecoder().decode(GatewayErrorResponse.self, from: data)
            throw TranslationError.rateLimited(provider: .ctrlVCloud, retryAfter: body?.retryAfterSeconds)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = try? JSONDecoder().decode(GatewayErrorResponse.self, from: data)
            throw TranslationError.apiError(
                statusCode: httpResponse.statusCode,
                message: body?.error ?? "Translation service unavailable"
            )
        }
        return data
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct GatewayTranslationRequest: Encodable {
    let text: String
    let systemPrompt: String
    let installID: String
    let sessionToken: String?
    let warmupOnly: Bool
}

private struct GatewayTranslationResponse: Decodable {
    let translatedText: String
    let model: String
    let plan: String
}

private struct GatewayErrorResponse: Decodable {
    let error: String
    let retryAfterSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case error
        case retryAfterSeconds = "retry_after_seconds"
    }
}
