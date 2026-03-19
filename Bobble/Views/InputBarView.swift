import SwiftUI

struct InputBarView: View {
    @ObservedObject var viewModel: ChatSessionViewModel

    @State private var sendBounce = false

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $viewModel.inputText,
                prompt: Text("Ask anything...").foregroundColor(DesignTokens.textSecondary.opacity(0.8))
            )
                .textFieldStyle(.plain)
                .font(DesignTokens.inputFont)
                .foregroundColor(DesignTokens.textPrimary)
                .onSubmit {
                    triggerSend()
                }

            Button(action: { triggerSend() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(canSend ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .scaleEffect(sendBounce ? 0.9 : 1.0)
                    .rotationEffect(.degrees(sendBounce ? -10 : 0))
                    .animation(DesignTokens.motionPlayful, value: sendBounce)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(DesignTokens.motionFade, value: canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func triggerSend() {
        guard canSend else { return }
        sendBounce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            sendBounce = false
        }
        viewModel.send()
    }
}
