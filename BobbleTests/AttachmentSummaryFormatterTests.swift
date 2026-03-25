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
