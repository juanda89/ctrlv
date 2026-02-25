import Foundation

protocol LemonLicenseClientProtocol {
    func activate(licenseKey: String, instanceName: String) async throws -> LemonActivationResult
    func validate(licenseKey: String, instanceID: String?) async throws -> LemonValidationResult
    func deactivate(licenseKey: String, instanceID: String) async throws -> Bool
}

final class LemonLicenseClient: LemonLicenseClientProtocol {
    private let session: URLSession
    private let baseURL: URL

    init(
        baseURL: URL? = Constants.lemonLicenseAPIBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.session = session
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LemonActivationResult {
        let payload: [String: Any] = [
            "license_key": licenseKey,
            "instance_name": instanceName
        ]
        let body = try await post(path: "/v1/licenses/activate", payload: payload)

        guard body.bool(at: "activated") == true,
              let instanceID = body.string(at: "instance.id") else {
            let reason = body.string(at: "error") ?? "Activation failed"
            throw LemonLicenseError.activationFailed(reason)
        }

        let planName = body.string(at: "license_key.variant_name")
        return LemonActivationResult(instanceID: instanceID, planName: planName)
    }

    func validate(licenseKey: String, instanceID: String?) async throws -> LemonValidationResult {
        var payload: [String: Any] = ["license_key": licenseKey]
        if let instanceID, !instanceID.isEmpty {
            payload["instance_id"] = instanceID
        }

        let body = try await post(path: "/v1/licenses/validate", payload: payload)
        let status = LemonValidationStatus(raw: body.string(at: "license_key.status"))
        let isValid = body.bool(at: "valid") ?? (status == .active)
        let reason = body.string(at: "error")
        let planName = body.string(at: "license_key.variant_name")
        let resolvedInstanceID = body.string(at: "instance.id") ?? instanceID

        return LemonValidationResult(
            isValid: isValid,
            status: status,
            planName: planName,
            instanceID: resolvedInstanceID,
            reason: reason
        )
    }

    func deactivate(licenseKey: String, instanceID: String) async throws -> Bool {
        let payload: [String: Any] = [
            "license_key": licenseKey,
            "instance_id": instanceID
        ]
        let body = try await post(path: "/v1/licenses/deactivate", payload: payload)
        return body.bool(at: "deactivated") == true
    }

    private func post(path: String, payload: [String: Any]) async throws -> [String: Any] {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appendingPathComponent(normalizedPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LemonLicenseError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw LemonLicenseError.serverError(message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LemonLicenseError.invalidResponse
        }
        return json
    }

    private func formEncodedBody(_ payload: [String: Any]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let parts = payload.compactMap { key, rawValue -> String? in
            let value = String(describing: rawValue)
            guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed),
                  let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
                return nil
            }
            return "\(encodedKey)=\(encodedValue)"
        }
        return parts.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private static var defaultBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.lemonsqueezy.com"
        return components.url ?? URL(fileURLWithPath: "/")
    }
}

enum LemonLicenseError: LocalizedError, Equatable {
    case invalidResponse
    case serverError(String)
    case activationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from Lemon Squeezy"
        case .serverError(let message):
            message
        case .activationFailed(let message):
            message
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func bool(at keyPath: String) -> Bool? {
        value(at: keyPath) as? Bool
    }

    func string(at keyPath: String) -> String? {
        value(at: keyPath) as? String
    }

    func value(at keyPath: String) -> Any? {
        let components = keyPath.split(separator: ".").map(String.init)
        guard !components.isEmpty else { return nil }

        var current: Any = self
        for component in components {
            guard let object = current as? [String: Any],
                  let next = object[component] else {
                return nil
            }
            current = next
        }
        return current
    }
}
