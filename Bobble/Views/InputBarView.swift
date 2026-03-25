import SwiftUI
import AppKit
struct InputBarView: View {
    @ObservedObject var viewModel: ChatSessionViewModel
    let showProviderBadge: Bool

    @State private var sendBounce = false
    @State private var isDropTargeted = false
    @FocusState private var isInputFocused: Bool

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.pendingAttachments.isEmpty
    }

    private var isConversationRunning: Bool {
        if case .running = viewModel.session.state {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.pendingAttachments) { attachment in
                            AttachmentChipView(attachment: attachment, removable: true) {
                                viewModel.removePendingAttachment(id: attachment.id)
                            }
                        }
                    }
                }
            }

            if isDropTargeted {
                Text("Drop files or images to attach")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignTokens.textSecondary)
            }

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .onSubmit {
                triggerSend()
            }

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 10) {
                    Button(action: selectAttachments) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Attach files")

                    Button(action: viewModel.captureScreenshot) {
                        Image(systemName: viewModel.isCapturingScreenshot ? "hourglass" : "viewfinder")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isCapturingScreenshot)
                    .help("Capture screenshot")

                    if showProviderBadge && viewModel.session.provider != .codex {
                        ProviderBadgeView(provider: viewModel.session.provider)
                            .help("Switch providers from the menu bar icon")
                    }

                    ProviderModelMenu(
                        provider: viewModel.session.provider,
                        selectedModel: viewModel.session.selectedModel,
                        isDisabled: isConversationRunning
                    ) { model in
                        viewModel.selectModel(model)
                    }

                    ConversationModeMenu(
                        selectedMode: viewModel.session.conversationMode,
                        isDisabled: isConversationRunning
                    ) { mode in
                        viewModel.updateConversationMode(mode)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 10) {
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
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignTokens.surfaceAccent.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isDropTargeted ? DesignTokens.surfaceAccent : DesignTokens.borderColor.opacity(0.8),
                            lineWidth: isDropTargeted ? 1.5 : 1
                        )
                )
        )
        .padding(12)
        .onDrop(of: supportedDropTypes, isTargeted: $isDropTargeted, perform: handleDrop)
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
            NSApp.activate(ignoringOtherApps: true)

            let selector = Selector(("startDictation:"))
            let keyWindow = NSApp.keyWindow ?? NSApp.windows.first(where: \.isKeyWindow)

            if let responder = keyWindow?.firstResponder, responder.responds(to: selector) {
                NSApp.sendAction(selector, to: responder, from: nil)
                return
            }

            if let fieldEditor = keyWindow?.fieldEditor(false, for: nil), fieldEditor.responds(to: selector) {
                NSApp.sendAction(selector, to: fieldEditor, from: nil)
                return
            }

            NSApp.sendAction(selector, to: nil, from: nil)
        }
    }

    private func selectAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return }
        viewModel.attachFiles(urls: panel.urls)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        viewModel.attachDroppedItems(from: providers)
    }

    private var supportedDropTypes: [String] {
        ChatSessionViewModel.supportedDropTypeIdentifiers
    }
}

struct ProviderModelMenu: View {
    let provider: CLIBackend
    let selectedModel: ProviderModelOption
    let isDisabled: Bool
    let onSelect: (ProviderModelOption) -> Void

    var body: some View {
        Menu {
            ForEach(ProviderModelOption.availableOptions(for: provider)) { model in
                Button(action: { onSelect(model) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName(for: provider))
                            Text(model.subtitle(for: provider))
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        if model == selectedModel {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(selectedModel.normalized(for: provider).shortLabel(for: provider))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(DesignTokens.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignTokens.surfaceAccent.opacity(0.32))
                )
                .overlay(
                    Capsule()
                        .stroke(DesignTokens.borderColor.opacity(0.9), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1.0)
        .help(isDisabled ? "Model changes apply after the current turn finishes" : "Choose the \(provider.shortLabel) model for the next message")
    }
}

struct ConversationModeMenu: View {
    let selectedMode: ConversationExecutionMode
    let isDisabled: Bool
    let onSelect: (ConversationExecutionMode) -> Void

    var body: some View {
        Menu {
            ForEach(ConversationExecutionMode.allCases) { mode in
                Button(action: { onSelect(mode) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                            Text(mode.helpText)
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        if mode == selectedMode {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(selectedMode.displayName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(DesignTokens.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignTokens.surfaceAccent.opacity(0.32))
                )
                .overlay(
                    Capsule()
                        .stroke(DesignTokens.borderColor.opacity(0.9), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1.0)
        .help(isDisabled ? "Mode changes apply after the current turn finishes" : "Choose Ask or Bypass for this conversation")
    }
}
