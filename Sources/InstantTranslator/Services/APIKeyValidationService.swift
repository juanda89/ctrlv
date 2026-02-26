import Foundation

struct APIKeyValidationResult: Equatable {
    let isValid: Bool
    let message: String
}

protocol APIKeyValidating {
    func validate(apiKey: String, for provider: ProviderType) async -> APIKeyValidationResult
}

struct APIKeyValidationService: APIKeyValidating {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(apiKey: String, for provider: ProviderType) async -> APIKeyValidationResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return APIKeyValidationResult(isValid: false, message: "API key is empty.")
        }

        do {
            let request = try validationRequest(for: provider, apiKey: trimmed)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return APIKeyValidationResult(
                    isValid: false,
                    message: "Could not validate key. Invalid server response."
                )
            }

            switch http.statusCode {
            case 200:
                return APIKeyValidationResult(isValid: true, message: "\(provider.rawValue) key verified.")
            case 429:
                return APIKeyValidationResult(
                    isValid: true,
                    message: "\(provider.rawValue) key verified (rate limited right now)."
                )
            case 401, 403:
                return APIKeyValidationResult(
                    isValid: false,
                    message: "Invalid \(provider.rawValue) API key."
                )
            default:
                let serverMessage = errorMessage(from: data) ?? "Provider returned status \(http.statusCode)."
                return APIKeyValidationResult(isValid: false, message: serverMessage)
            }
        } catch {
            let networkMessage = (error as? URLError)?.localizedDescription ?? error.localizedDescription
            return APIKeyValidationResult(
                isValid: false,
                message: "Could not validate key. \(networkMessage)"
            )
        }
    }

    private func validationRequest(for provider: ProviderType, apiKey: String) throws -> URLRequest {
        switch provider {
        case .openAI:
            guard let url = URL(string: "https://api.openai.com/v1/models") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            return request

        case .claude:
            guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            return request

        case .gemini:
            guard let encoded = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(encoded)") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            return request
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }

        return nil
    }
}
