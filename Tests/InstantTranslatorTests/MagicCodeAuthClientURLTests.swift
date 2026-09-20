import XCTest
@testable import ControlVCore

final class MagicCodeAuthClientURLTests: XCTestCase {
    func test_validatedBillingURL_returnsURL_whenStripeCheckoutOverHTTPS() {
        XCTAssertNotNil(MagicCodeAuthClient.validatedBillingURL("https://checkout.stripe.com/c/pay/cs_test_123"))
        XCTAssertNotNil(MagicCodeAuthClient.validatedBillingURL("https://billing.stripe.com/p/session/abc"))
        XCTAssertNotNil(MagicCodeAuthClient.validatedBillingURL("https://control-v.info/success"))
    }

    func test_validatedBillingURL_rejects_whenSchemeOrHostIsNotAllowed() {
        XCTAssertNil(MagicCodeAuthClient.validatedBillingURL("http://checkout.stripe.com/c/pay/x"))
        XCTAssertNil(MagicCodeAuthClient.validatedBillingURL("file:///etc/passwd"))
        XCTAssertNil(MagicCodeAuthClient.validatedBillingURL("x-apple.systempreferences:com.apple.preference.security"))
        XCTAssertNil(MagicCodeAuthClient.validatedBillingURL("https://stripe.com.evil.example/pay"))
        XCTAssertNil(MagicCodeAuthClient.validatedBillingURL("not a url"))
    }
}
