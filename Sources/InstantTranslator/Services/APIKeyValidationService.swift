import Foundation

enum APIKeyValidationOutcome: Equatable {
    case valid
    case rateLimited
    case invalid
    case networkError
}

struct APIKeyValidationResult: Equatable {
    let outcome: APIKeyValidationOutcome
    let message: String
    let retryAfter: Int?

    var isValid: Bool {
        switch outcome {
        case .valid, .rateLimited:
            return true
        case .invalid, .networkError:
            return false
        }
    }
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
            return APIKeyValidationResult(
                outcome: .invalid,
                message: "API key is empty.",
                retryAfter: nil
            )
        }

        do {
            let request = try validationRequest(for: provider, apiKey: trimmed)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return APIKeyValidationResult(
                    outcome: .networkError,
                    message: "Could not validate key. Invalid server response.",
                    retryAfter: nil
                )
            }

            switch http.statusCode {
            case 200:
                return APIKeyValidationResult(
                    outcome: .valid,
                    message: "\(provider.rawValue) key verified.",
                    retryAfter: nil
                )
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                return APIKeyValidationResult(
                    outcome: .rateLimited,
                    message: "\(provider.rawValue) rate limited right now.",
                    retryAfter: retryAfter
                )
            case 401, 403:
                return APIKeyValidationResult(
                    outcome: .invalid,
                    message: "Invalid \(provider.rawValue) API key.",
                    retryAfter: nil
                )
            default:
                let serverMessage = errorMessage(from: data) ?? "Provider returned status \(http.statusCode)."
                return APIKeyValidationResult(
                    outcome: .invalid,
                    message: serverMessage,
                    retryAfter: nil
                )
            }
        } catch {
            let networkMessage = (error as? URLError)?.localizedDescription ?? error.localizedDescription
            return APIKeyValidationResult(
                outcome: .networkError,
                message: "Could not validate key. \(networkMessage)",
                retryAfter: nil
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
