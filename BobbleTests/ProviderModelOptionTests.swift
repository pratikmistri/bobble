import XCTest
@testable import Bobble

final class ProviderModelOptionTests: XCTestCase {
    func testAvailableOptionsMatchProviderCatalog() {
        XCTAssertEqual(
            ProviderModelOption.availableOptions(for: .codex),
            [.automatic, .gpt5Codex, .gpt53Codex, .gpt52Codex, .gpt51Codex, .gpt51CodexMax, .gpt51CodexMini]
        )
        XCTAssertEqual(
            ProviderModelOption.availableOptions(for: .claude),
            [.automatic, .claudeSonnet46, .claudeOpus46, .claudeHaiku45]
        )
        XCTAssertEqual(
            ProviderModelOption.availableOptions(for: .copilot),
            [.automatic, .copilotClaudeSonnet45, .copilotClaudeOpus45, .copilotClaudeOpus46, .copilotGPT51CodexMax, .copilotGPT52Codex]
        )
    }

    func testUnavailableModelNormalizesToAutomatic() {
        XCTAssertEqual(ProviderModelOption.gpt53Codex.normalized(for: .claude), .automatic)
        XCTAssertEqual(ProviderModelOption.claudeOpus46.normalized(for: .copilot), .automatic)
    }

    func testAutomaticModelHasProviderSpecificSubtitleAndNoCLIValue() {
        XCTAssertEqual(ProviderModelOption.automatic.cliValue(for: .codex), nil)
        XCTAssertEqual(ProviderModelOption.automatic.subtitle(for: .codex), "Use the Codex CLI default model.")
        XCTAssertEqual(ProviderModelOption.automatic.subtitle(for: .claude), "Use Claude Code's default model.")
        XCTAssertEqual(ProviderModelOption.automatic.subtitle(for: .copilot), "Use GitHub Copilot's default model.")
    }

    func testKnownOptionMetadataRemainsStable() {
        XCTAssertEqual(ProviderModelOption.gpt53Codex.displayName(for: .codex), "GPT-5.3 Codex")
        XCTAssertEqual(ProviderModelOption.gpt53Codex.shortLabel(for: .codex), "5.3 Codex")
        XCTAssertEqual(ProviderModelOption.gpt53Codex.subtitle(for: .codex), "Most capable current Codex model.")

        XCTAssertEqual(ProviderModelOption.copilotGPT52Codex.displayName(for: .copilot), "GPT-5.2 Codex")
        XCTAssertEqual(ProviderModelOption.copilotGPT52Codex.shortLabel(for: .copilot), "5.2 Codex")
        XCTAssertEqual(ProviderModelOption.copilotGPT52Codex.cliValue(for: .copilot), "GPT-5.2-Codex")
    }
}
