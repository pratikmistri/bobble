import SwiftUI

// Legacy — retained for compilation; BobbleRootView is the active root.
struct ChatHeadStackView: View {
    @ObservedObject var manager: ChatHeadsManager
    let onHeadTapped: (ChatSession) -> Void

    @Namespace private var morphNamespace

    var body: some View {
        VStack(spacing: DesignTokens.headSpacing) {
            ForEach(manager.sessions) { session in
                ChatHeadView(
                    session: session,
                    showProviderBadge: manager.hasMixedProviders,
                    isExpanded: manager.expandedSessionId == session.id,
                    onTap: { onHeadTapped(session) },
                    morphNamespace: morphNamespace
                )
            }
        }
        .padding(DesignTokens.headInset)
    }
}
