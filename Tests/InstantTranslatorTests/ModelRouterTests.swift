import XCTest
@testable import InstantTranslator

final class ModelRouterTests: XCTestCase {

    func test_route_returnsHostedModel_whenTrialModeEnabled() {
        let decision = ModelRouter.route(provider: .ctrlVCloud, textLength: 1200, isTrialMode: true)

        XCTAssertEqual(decision.provider, .ctrlVCloud)
        XCTAssertEqual(decision.model, Constants.hostedModelName)
        XCTAssertEqual(decision.tier, .fast)
        XCTAssertFalse(decision.isFallback)
    }

    func test_route_returnsHostedModel_whenPaidModeEnabled() {
        let decision = ModelRouter.route(provider: .ctrlVCloud, textLength: 40, isTrialMode: false)

        XCTAssertEqual(decision.provider, .ctrlVCloud)
        XCTAssertEqual(decision.model, Constants.hostedModelName)
        XCTAssertEqual(decision.tier, .fast)
        XCTAssertFalse(decision.isFallback)
    }

    func test_route_marksFallback_whenForceFastEnabled() {
        let decision = ModelRouter.route(provider: .ctrlVCloud, textLength: 3000, isTrialMode: false, forceFast: true)

        XCTAssertEqual(decision.provider, .ctrlVCloud)
        XCTAssertEqual(decision.model, Constants.hostedModelName)
        XCTAssertTrue(decision.isFallback)
    }
}
