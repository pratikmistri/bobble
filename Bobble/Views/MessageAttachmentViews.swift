import AppKit
import QuickLookThumbnailing
import SwiftUI

struct AttachmentChipView: View {
    let attachment: ChatAttachment
    var removable: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        if removable, attachment.isImage {
            RemovableImageAttachmentChipView(attachment: attachment, onRemove: onRemove)
        } else {
            standardChip
        }
    }

    @ViewBuilder
    private var standardChip: some View {
        let chip = HStack(spacing: 6) {
            Image(systemName: attachment.systemImageName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DesignTokens.textSecondary)

            Text(attachment.fileName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DesignTokens.textPrimary)
                .lineLimit(1)

            if removable, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.textSecondary.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(DesignTokens.surfaceColor.opacity(0.8))
        )
        .overlay(
            Capsule()
                .stroke(DesignTokens.borderColor.opacity(0.8), lineWidth: 1)
        )

        if removable {
            chip
        } else {
            Button(action: openAttachment) {
                chip
            }
            .buttonStyle(.plain)
            .help("Open \(attachment.fileName)")
        }
    }

    private func openAttachment() {
        NSWorkspace.shared.open(attachment.fileURL)
    }
}

private struct RemovableImageAttachmentChipView: View {
    let attachment: ChatAttachment
    let onRemove: (() -> Void)?

    private let thumbnailSize: CGFloat = 60

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = NSImage(contentsOf: attachment.fileURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DesignTokens.surfaceColor.opacity(0.9))

                        Image(systemName: attachment.systemImageName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                }
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DesignTokens.borderColor.opacity(0.8), lineWidth: 1)
            )

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, Color.black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .help(attachment.fileName)
    }
}

struct ImageAttachmentPreviewView: View {
    let attachment: ChatAttachment

    @State private var isExpanded = false

    private let collapsedHeight: CGFloat = 128
    private let expandedHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = NSImage(contentsOf: attachment.fileURL) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 220)
                        .frame(height: isExpanded ? expandedHeight : collapsedHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DesignTokens.borderColor.opacity(0.7), lineWidth: 1)
                        )

                    Button(action: openAttachment) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignTokens.textPrimary)
                            .padding(6)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    withAnimation(DesignTokens.motionPress) {
                        isExpanded.toggle()
                    }
                }

                Text(attachment.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignTokens.textSecondary)
                    .lineLimit(1)
            } else {
                AttachmentChipView(attachment: attachment)
            }
        }
        .frame(maxWidth: 220, alignment: .leading)
        .help("Click to resize. Use the arrow button to open the image.")
    }

    private func openAttachment() {
        NSWorkspace.shared.open(attachment.fileURL)
    }
}

struct DocumentAttachmentPreviewView: View {
    let attachment: ChatAttachment

    @State private var textPreview = ""
    @State private var quickLookThumbnail: NSImage?
    @State private var didRequestPreview = false

    private let previewSize = CGSize(width: 440, height: 240)
    private let cardWidth: CGFloat = 220
    private let previewHeight: CGFloat = 110

    var body: some View {
        Button(action: openAttachment) {
            VStack(alignment: .leading, spacing: 10) {
                previewSurface
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
                    .background(previewBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DesignTokens.borderColor.opacity(0.75), lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 6) {
                            Text(attachment.previewBadgeLabel)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())

                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .padding(7)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(8)
                    }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: attachment.systemImageName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignTokens.textSecondary)
                        .frame(width: 18, height: 18)

                    Text(attachment.fileName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(width: cardWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(DesignTokens.surfaceColor.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DesignTokens.borderColor.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: cardWidth, alignment: .leading)
        .help("Open \(attachment.fileName)")
        .onAppear(perform: loadPreviewIfNeeded)
    }

    @ViewBuilder
    private var previewSurface: some View {
        switch attachment.preferredPreviewKind {
        case .textDocument:
            textDocumentSurface
        case .image:
            thumbnailSurface(image: NSImage(contentsOf: attachment.fileURL))
        case .document:
            thumbnailSurface(image: quickLookThumbnail)
        }
    }

    private var textDocumentSurface: some View {
        VStack(alignment: .leading, spacing: 6) {
            if textPreview.isEmpty {
                Text("Loading preview...")
                    .foregroundStyle(DesignTokens.textSecondary)
            } else {
                Text(textPreview)
                    .foregroundStyle(DesignTokens.textPrimary)
            }
        }
        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
        .lineSpacing(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    @ViewBuilder
    private func thumbnailSurface(image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            VStack(spacing: 8) {
                Image(systemName: attachment.systemImageName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)

                Text("Preview unavailable")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var previewBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                DesignTokens.surfaceAccent.opacity(0.2),
                DesignTokens.surfaceColor.opacity(0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func loadPreviewIfNeeded() {
        guard !didRequestPreview else { return }
        didRequestPreview = true

        switch attachment.preferredPreviewKind {
        case .textDocument:
            loadTextPreview()
        case .image:
            break
        case .document:
            loadQuickLookThumbnail()
        }
    }

    private func loadTextPreview() {
        let fileURL = attachment.fileURL

        Task.detached(priority: .utility) {
            let preview = readTextPreview(from: fileURL)
            await MainActor.run {
                textPreview = preview
            }
        }
    }

    private func loadQuickLookThumbnail() {
        let request = QLThumbnailGenerator.Request(
            fileAt: attachment.fileURL,
            size: previewSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let representation else { return }
            let image = NSImage(cgImage: representation.cgImage, size: previewSize)
            DispatchQueue.main.async {
                quickLookThumbnail = image
            }
        }
    }

    private func openAttachment() {
        NSWorkspace.shared.open(attachment.fileURL)
    }
}

private func readTextPreview(from fileURL: URL) -> String {
    guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
        return "Preview unavailable"
    }

    let previewData = data.prefix(2_400)
    let rawPreview = String(decoding: previewData, as: UTF8.self)
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !rawPreview.isEmpty else {
        return "Preview unavailable"
    }

    let collapsedLines = rawPreview
        .components(separatedBy: "\n")
        .prefix(6)
        .map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? " " : String(trimmed.prefix(62))
        }

    let preview = collapsedLines.joined(separator: "\n")
    return preview.count > 360 ? String(preview.prefix(360)) + "..." : preview
}
