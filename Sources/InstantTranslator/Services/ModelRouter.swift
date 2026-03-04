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
    private static let trialGeminiModel = "gemini-flash-latest"

    static func route(
        provider: ProviderType,
        textLength: Int,
        isTrialMode: Bool,
        forceFast: Bool = false
    ) -> ModelRoutingDecision {
        if isTrialMode {
            return ModelRoutingDecision(
                provider: .gemini,
                model: trialGeminiModel,
                tier: .fast,
                isFallback: false
            )
        }

        let tier: ModelTier
        if forceFast {
            tier = .fast
        } else {
            tier = textLength >= longTextThreshold ? .robust : .fast
        }

        let model: String
        switch (provider, tier) {
        case (.openAI, .fast):
            model = "gpt-5-mini"
        case (.openAI, .robust):
            model = "gpt-5.2"
        case (.claude, .fast):
            model = "claude-4-5-haiku"
        case (.claude, .robust):
            model = "claude-4-6-opus"
        case (.gemini, .fast):
            model = "gemini-2.5-flash"
        case (.gemini, .robust):
            model = "gemini-3.1-pro"
        }

        return ModelRoutingDecision(
            provider: provider,
            model: model,
            tier: tier,
            isFallback: forceFast
        )
    }
}
