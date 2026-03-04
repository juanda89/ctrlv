import Foundation

struct OpenAIProvider: TranslationProvider, StreamingTranslationProvider {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    func translate(text: String, systemPrompt: String) async throws -> String {
        let request = try buildRequest(text: text, systemPrompt: systemPrompt, stream: false)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.networkError(underlying: URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw TranslationError.rateLimited(provider: .openAI, retryAfter: retryAfter)
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return parsed.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func translateStream(text: String, systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(text: text, systemPrompt: systemPrompt, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw TranslationError.networkError(underlying: URLError(.badServerResponse))
                    }

                    if httpResponse.statusCode == 429 {
                        let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                        throw TranslationError.rateLimited(provider: .openAI, retryAfter: retryAfter)
                    }

                    guard httpResponse.statusCode == 200 else {
                        var lines: [String] = []
                        for try await line in bytes.lines {
                            lines.append(line)
                            if lines.count >= 30 { break }
                        }
                        let message = lines.joined(separator: "\n")
                        throw TranslationError.apiError(
                            statusCode: httpResponse.statusCode,
                            message: message.isEmpty ? "Unknown error" : message
                        )
                    }

                    let parser = OpenAIStreamEventParser()
                    for try await line in bytes.lines {
                        switch try parser.parse(line: line) {
                        case .ignore:
                            continue
                        case .done:
                            continuation.finish()
                            return
                        case .content(let content):
                            continuation.yield(content)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildRequest(text: String, systemPrompt: String, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw TranslationError.apiError(statusCode: 0, message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = OpenAIRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text)
            ],
            stream: stream ? true : nil
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

struct OpenAIStreamEventParser {
    func parse(line: String) throws -> OpenAIStreamEvent {
        guard line.hasPrefix("data:") else { return .ignore }

        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return .ignore }
        if payload == "[DONE]" { return .done }

        guard let data = payload.data(using: .utf8) else {
            throw TranslationError.apiError(statusCode: 0, message: "Malformed streaming payload")
        }

        let event: OpenAIStreamChunk
        do {
            event = try JSONDecoder().decode(OpenAIStreamChunk.self, from: data)
        } catch {
            throw TranslationError.apiError(statusCode: 0, message: "Malformed streaming payload")
        }

        if let content = event.choices.first?.delta.content, !content.isEmpty {
            return .content(content)
        }
        return .ignore
    }
}

enum OpenAIStreamEvent: Equatable {
    case ignore
    case done
    case content(String)
}

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool?

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OpenAIResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct OpenAIStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}
