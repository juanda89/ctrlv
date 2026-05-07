import Foundation

public enum ModelTier: String, Sendable {
    case fast
    case robust
}

public struct ModelRoutingDecision: Sendable {
    public let provider: ProviderType
    public let model: String
    public let tier: ModelTier
    public let isFallback: Bool

    public init(provider: ProviderType, model: String, tier: ModelTier, isFallback: Bool) {
        self.provider = provider
        self.model = model
        self.tier = tier
        self.isFallback = isFallback
    }
}

public enum ModelRouter {
    public static let longTextThreshold = 320
    private static let hostedModel = Constants.hostedModelName

    public static func route(
        provider: ProviderType,
        textLength: Int,
        isTrialMode: Bool,
        forceFast: Bool = false
    ) -> ModelRoutingDecision {
        return ModelRoutingDecision(
            provider: .ctrlVCloud,
            model: hostedModel,
            tier: .fast,
            isFallback: forceFast
        )
    }
}
