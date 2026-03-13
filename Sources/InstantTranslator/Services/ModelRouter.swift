import Foundation

enum ModelTier: String {
    case fast
    case robust
}

struct ModelRoutingDecision {
    let provider: ProviderType
    let model: String
    let tier: ModelTier
    let isFallback: Bool
}

enum ModelRouter {
    static let longTextThreshold = 320
    private static let hostedModel = Constants.hostedModelName

    static func route(
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
