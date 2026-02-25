import XCTest
@testable import InstantTranslator

final class PromptBuilderTests: XCTestCase {

    func test_buildSystemPrompt_containsTargetLanguage() {
        let prompt = PromptBuilder.buildSystemPrompt(targetLanguage: "Spanish", tone: .original)
        XCTAssertTrue(prompt.contains("Spanish"))
    }

    func test_buildSystemPrompt_formalTone_containsFormal() {
        let prompt = PromptBuilder.buildSystemPrompt(targetLanguage: "English", tone: .formal)
        XCTAssertTrue(prompt.contains("formal"))
    }

    func test_buildSystemPrompt_casualTone_containsCasual() {
        let prompt = PromptBuilder.buildSystemPrompt(targetLanguage: "English", tone: .casual)
        XCTAssertTrue(prompt.contains("casual") || prompt.contains("conversational"))
    }

    func test_buildSystemPrompt_conciseTone_containsBrief() {
        let prompt = PromptBuilder.buildSystemPrompt(targetLanguage: "English", tone: .concise)
        XCTAssertTrue(prompt.contains("brief") || prompt.contains("concise"))
    }

    func test_buildSystemPrompt_containsNoExplanationsRule() {
        let prompt = PromptBuilder.buildSystemPrompt(targetLanguage: "French", tone: .original)
        XCTAssertTrue(prompt.contains("ONLY the translated text"))
    }

    func test_buildSystemPrompt_containsSameLanguageRule() {
        let prompt = PromptBuilder.buildSystemPrompt(targetLanguage: "German", tone: .original)
        XCTAssertTrue(prompt.contains("grammar"))
    }

    func test_buildSystemPrompt_customTone_containsCustomInstruction() {
        let prompt = PromptBuilder.buildSystemPrompt(
            targetLanguage: "English",
            tone: .custom,
            customTonePrompt: "Use a warm and playful tone."
        )
        XCTAssertTrue(prompt.contains("warm and playful"))
    }
}
