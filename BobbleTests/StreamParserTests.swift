import XCTest
@testable import Bobble

final class StreamParserTests: XCTestCase {
    func testClaudeAssistantAndResultDoNotEmitDuplicateFinalMessages() {
        let parser = StreamParser(backend: .claude)
        var finalResults: [String] = []

        parser.onResult = { finalResults.append($0) }

        parser.feed(line("""
        {"type":"assistant","message":{"content":[{"type":"text","text":"Hello from Claude"}]}}
        """))
        parser.feed(line("""
        {"type":"result","result":"Hello from Claude"}
        """))

        XCTAssertEqual(finalResults, ["Hello from Claude"])
    }

    func testClaudeResultWithResultAndContentOnlyEmitsOneFinalMessage() {
        let parser = StreamParser(backend: .claude)
        var finalResults: [String] = []

        parser.onResult = { finalResults.append($0) }

        parser.feed(line("""
        {"type":"result","result":"A SQL query walks into a bar","content":[{"type":"text","text":"A SQL query walks into a bar"}]}
        """))

        XCTAssertEqual(finalResults, ["A SQL query walks into a bar"])
    }

    private func line(_ json: String) -> Data {
        Data((json + "\n").utf8)
    }
}
