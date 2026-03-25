import Foundation

enum AttachmentSummaryFormatter {
    static func summary(for attachments: [ChatAttachment]) -> String {
        guard !attachments.isEmpty else {
            return "No messages yet."
        }

        let imageCount = attachments.filter(\.isImage).count
        let fileCount = attachments.count - imageCount

        if imageCount > 0 && fileCount > 0 {
            return "Shared \(imageCount) image\(imageCount == 1 ? "" : "s") and \(fileCount) file\(fileCount == 1 ? "" : "s")."
        }

        if imageCount > 0 {
            return "Shared \(imageCount) image\(imageCount == 1 ? "" : "s")."
        }

        return "Shared \(fileCount) file\(fileCount == 1 ? "" : "s")."
    }
}
