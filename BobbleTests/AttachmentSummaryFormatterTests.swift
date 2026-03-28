import XCTest
@testable import Bobble

final class AttachmentSummaryFormatterTests: XCTestCase {
    func testSingleImageSummary() {
        XCTAssertEqual(
            AttachmentSummaryFormatter.summary(for: [makeAttachment(kind: .image, name: "preview.png")]),
            "Shared 1 image."
        )
    }

    func testMultipleFileSummary() {
        XCTAssertEqual(
            AttachmentSummaryFormatter.summary(for: [
                makeAttachment(kind: .file, name: "notes.md"),
                makeAttachment(kind: .file, name: "todo.txt")
            ]),
            "Shared 2 files."
        )
    }

    func testMixedAttachmentSummary() {
        XCTAssertEqual(
            AttachmentSummaryFormatter.summary(for: [
                makeAttachment(kind: .image, name: "diagram.png"),
                makeAttachment(kind: .file, name: "notes.md")
            ]),
            "Shared 1 image and 1 file."
        )
    }

    func testRunningPreviewWinsOverStaleMessage() {
        let session = ChatSession(
            name: "Preview Test",
            messages: [
                ChatMessage(role: .assistant, content: "Old response")
            ],
            state: .running
        )

        XCTAssertEqual(
            ChatHeadPreviewFormatter.preview(for: session),
            ChatHeadPreviewSnapshot(
                senderLabel: "Live",
                message: "Working on your latest message..."
            )
        )
    }

    private func makeAttachment(kind: ChatAttachment.Kind, name: String) -> ChatAttachment {
        ChatAttachment(
            kind: kind,
            fileName: name,
            filePath: "/tmp/\(name)",
            relativePath: name
        )
    }
}

final class ChatTimelineBehaviorTests: XCTestCase {
    func testPrimaryTimelineVisibilityFiltersSystemNoise() {
        let visibleThought = ChatMessage(role: .system, content: "Agent thought\nPlanning...", kind: .agentThought)
        let visibleApproval = ChatMessage(role: .system, content: "Approval needed", kind: .permission)
        let hiddenTool = ChatMessage(role: .system, content: "Running command: ls", kind: .toolUse)
        let hiddenRegular = ChatMessage(role: .system, content: "Codex item started", kind: .regular)
        let user = ChatMessage(role: .user, content: "Hi")
        let assistant = ChatMessage(role: .assistant, content: "Hello")
        let error = ChatMessage(role: .error, content: "Oops")

        XCTAssertTrue(user.isVisibleInPrimaryTimeline)
        XCTAssertTrue(assistant.isVisibleInPrimaryTimeline)
        XCTAssertTrue(error.isVisibleInPrimaryTimeline)
        XCTAssertTrue(visibleThought.isVisibleInPrimaryTimeline)
        XCTAssertTrue(visibleApproval.isVisibleInPrimaryTimeline)
        XCTAssertFalse(hiddenTool.isVisibleInPrimaryTimeline)
        XCTAssertFalse(hiddenRegular.isVisibleInPrimaryTimeline)
    }

    func testAssistantMergeReplacesGrowingSnapshot() {
        XCTAssertEqual(
            ChatSessionViewModel.mergeAssistantContent(current: "Hello", incoming: "Hello world"),
            "Hello world"
        )
    }

    func testAssistantMergeIgnoresStaleOrDuplicateSnapshot() {
        XCTAssertNil(ChatSessionViewModel.mergeAssistantContent(current: "Hello world", incoming: "Hello"))
        XCTAssertNil(ChatSessionViewModel.mergeAssistantContent(current: "Hello world", incoming: "Hello world"))
        XCTAssertNil(ChatSessionViewModel.mergeAssistantContent(current: "Hello world", incoming: "world"))
    }

    func testAssistantMergeAppendsTrueDelta() {
        XCTAssertEqual(
            ChatSessionViewModel.mergeAssistantContent(current: "Hello", incoming: " world"),
            "Hello world"
        )
    }

    func testAssistantMergeDoesNotDropLegitChunkThatAppearsEarlier() {
        XCTAssertEqual(
            ChatSessionViewModel.mergeAssistantContent(current: "Today there was noise. Then", incoming: " there were birds."),
            "Today there was noise. Then there were birds."
        )
    }

    func testAssistantMergeUsesSuffixPrefixOverlapToAvoidDuplication() {
        XCTAssertEqual(
            ChatSessionViewModel.mergeAssistantContent(current: "The cat sat on", incoming: "on the mat."),
            "The cat sat on the mat."
        )
    }

    func testThoughtNormalizationAndMergeHandlesReasoningAndAgentThoughtLabels() {
        XCTAssertEqual(
            ChatSessionViewModel.normalizeThoughtEventText("Reasoning\nThinking"),
            "Agent thought\nThinking"
        )

        XCTAssertEqual(
            ChatSessionViewModel.mergeThoughtEventText(
                existing: "Reasoning\nThinking",
                incoming: "Agent thought\n about options"
            ),
            "Agent thought\nThinking about options"
        )
    }
}
