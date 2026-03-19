import SwiftUI
import AppKit

struct InputBarView: View {
    @ObservedObject var viewModel: ChatSessionViewModel

    @State private var sendBounce = false
    @FocusState private var isInputFocused: Bool

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $viewModel.inputText,
                prompt: Text("Ask anything...").foregroundColor(DesignTokens.textSecondary.opacity(0.8)),
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(DesignTokens.inputFont)
                .foregroundColor(DesignTokens.textPrimary)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit {
                    triggerSend()
                }

            Button(action: startDictation) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Start Dictation")

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

    private func startDictation() {
        isInputFocused = true
        DispatchQueue.main.async {
            NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
        }
    }
}
