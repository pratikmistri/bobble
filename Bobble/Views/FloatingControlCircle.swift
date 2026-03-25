import SwiftUI
import AppKit

struct ChatHeadAvatarView: View {
    let imageName: String
    let size: CGFloat

    init(imageName: String, size: CGFloat = DesignTokens.headControlDiameter) {
        self.imageName = imageName
        self.size = size
    }

    var body: some View {
        Group {
            if let image = NSImage(named: NSImage.Name(imageName)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct FloatingControlCircle<Content: View>: View {
    let isHighlighted: Bool
    let diameter: CGFloat
    let content: Content

    init(
        isHighlighted: Bool = false,
        diameter: CGFloat = DesignTokens.headDiameter,
        @ViewBuilder content: () -> Content
    ) {
        self.isHighlighted = isHighlighted
        self.diameter = diameter
        self.content = content()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(DesignTokens.addButtonColor.opacity(0.95))
                .overlay(
                    Circle()
                        .strokeBorder(
                            DesignTokens.borderColor.opacity(isHighlighted ? 0.95 : 0.85),
                            lineWidth: 1.2
                        )
                )

            content
        }
        .frame(width: diameter, height: diameter)
        .shadow(
            color: .black.opacity(isHighlighted ? 0.18 : 0.12),
            radius: isHighlighted ? 8 : DesignTokens.headShadowRadius,
            y: isHighlighted ? 3 : DesignTokens.headShadowY
        )
    }
}

struct SessionFlyoutSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let contentPadding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = 18,
        contentPadding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DesignTokens.surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(DesignTokens.borderColor.opacity(0.75), lineWidth: 1)
                    )
            )
    }
}

struct SessionFlyoutRowContent: View {
    let chatHeadImageName: String
    let title: String
    let subtitle: String
    let trailingLabel: String?
    let subtitleLineLimit: Int
    let isHighlighted: Bool
    let showsLeadingAvatar: Bool

    init(
        chatHeadImageName: String,
        title: String,
        subtitle: String,
        trailingLabel: String? = nil,
        subtitleLineLimit: Int = 2,
        isHighlighted: Bool = false,
        showsLeadingAvatar: Bool = true
    ) {
        self.chatHeadImageName = chatHeadImageName
        self.title = title
        self.subtitle = subtitle
        self.trailingLabel = trailingLabel
        self.subtitleLineLimit = subtitleLineLimit
        self.isHighlighted = isHighlighted
        self.showsLeadingAvatar = showsLeadingAvatar
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsLeadingAvatar {
                ChatHeadAvatarView(imageName: chatHeadImageName, size: 30)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let trailingLabel, !trailingLabel.isEmpty {
                        Text(trailingLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(subtitleLineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(DesignTokens.surfaceElevated.opacity(isHighlighted ? 0.42 : 0))
    }
}
