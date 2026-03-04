import XCTest
@testable import InstantTranslator

final class ModelRouterTests: XCTestCase {

    func test_route_returnsFastOpenAIModel_whenTextIsShort() {
        let decision = ModelRouter.route(provider: .openAI, textLength: 319, isTrialMode: false)
        XCTAssertEqual(decision.model, "gpt-5-mini")
        XCTAssertEqual(decision.tier, .fast)
    }

    func test_route_returnsRobustOpenAIModel_whenTextIsLong() {
        let decision = ModelRouter.route(provider: .openAI, textLength: 320, isTrialMode: false)
        XCTAssertEqual(decision.model, "gpt-5.2")
        XCTAssertEqual(decision.tier, .robust)
    }

    func test_route_returnsFastClaudeModel_whenTextIsShort() {
        let decision = ModelRouter.route(provider: .claude, textLength: 80, isTrialMode: false)
        XCTAssertEqual(decision.model, "claude-4-5-haiku")
        XCTAssertEqual(decision.tier, .fast)
    }

    func test_route_returnsRobustClaudeModel_whenTextIsLong() {
        let decision = ModelRouter.route(provider: .claude, textLength: 1200, isTrialMode: false)
        XCTAssertEqual(decision.model, "claude-4-6-opus")
        XCTAssertEqual(decision.tier, .robust)
    }

    func test_route_returnsFastGeminiModel_whenTextIsShort() {
        let decision = ModelRouter.route(provider: .gemini, textLength: 10, isTrialMode: false)
        XCTAssertEqual(decision.model, "gemini-2.5-flash")
        XCTAssertEqual(decision.tier, .fast)
    }

    func test_route_returnsRobustGeminiModel_whenTextIsLong() {
        let decision = ModelRouter.route(provider: .gemini, textLength: 900, isTrialMode: false)
        XCTAssertEqual(decision.model, "gemini-3.1-pro")
        XCTAssertEqual(decision.tier, .robust)
    }

    func test_route_returnsTrialModel_whenTrialModeEnabled() {
        let decision = ModelRouter.route(provider: .openAI, textLength: 1000, isTrialMode: true)
        XCTAssertEqual(decision.provider, .gemini)
        XCTAssertEqual(decision.model, "gemini-flash-latest")
        XCTAssertEqual(decision.tier, .fast)
    }

    func test_route_returnsFastModel_whenForceFastEnabled() {
        let decision = ModelRouter.route(provider: .openAI, textLength: 1000, isTrialMode: false, forceFast: true)
        XCTAssertEqual(decision.model, "gpt-5-mini")
        XCTAssertEqual(decision.tier, .fast)
        XCTAssertTrue(decision.isFallback)
    }
}
