import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct InputBarView: View {
    @ObservedObject var viewModel: ChatSessionViewModel

    @State private var sendBounce = false
    @State private var isDropTargeted = false
    @FocusState private var isInputFocused: Bool

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.pendingAttachments.isEmpty
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

                    ModelPickerMenu(selectedModel: viewModel.session.selectedModel) { model in
                        viewModel.selectModel(model)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let url = extractFileURL(from: item) else {
                        return
                    }
                    DispatchQueue.main.async {
                        viewModel.attachFiles(urls: [url])
                    }
                }
                continue
            }

            guard let imageTypeIdentifier = preferredImageType(for: provider) else {
                continue
            }

            handled = true
            provider.loadDataRepresentation(forTypeIdentifier: imageTypeIdentifier) { data, _ in
                guard let data else { return }
                DispatchQueue.main.async {
                    viewModel.attachImageData(data, suggestedName: provider.suggestedName)
                }
            }
        }

        return handled
    }

    private func preferredImageType(for provider: NSItemProvider) -> String? {
        let candidates = [
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.tiff.identifier,
            UTType.gif.identifier,
            UTType.image.identifier
        ]
        return candidates.first(where: provider.hasItemConformingToTypeIdentifier)
    }

    private func extractFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL, url.isFileURL {
            return url
        }

        if let url = item as? NSURL, let bridgedURL = url as URL?, bridgedURL.isFileURL {
            return bridgedURL
        }

        if let data = item as? Data {
            return decodeFileURL(from: data)
        }

        if let string = item as? String, let url = URL(string: string), url.isFileURL {
            return url
        }

        return nil
    }

    private func decodeFileURL(from data: Data) -> URL? {
        if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return url
        }

        let candidateStrings = [
            String(data: data, encoding: .utf8),
            String(data: data, encoding: .utf16LittleEndian),
            String(data: data, encoding: .utf16BigEndian)
        ]

        for candidate in candidateStrings.compactMap({ $0 }) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), url.isFileURL {
                return url
            }
        }

        return nil
    }

    private var supportedDropTypes: [String] {
        [
            UTType.fileURL.identifier,
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.tiff.identifier,
            UTType.gif.identifier,
            UTType.image.identifier
        ]
    }
}

struct ModelPickerMenu: View {
    let selectedModel: CodexModelOption
    let onSelect: (CodexModelOption) -> Void

    var body: some View {
        Menu {
            ForEach(CodexModelOption.allCases) { model in
                Button(action: { onSelect(model) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                            Text(model.subtitle)
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
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Text(selectedModel.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
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
        .help("Choose the Codex model for the next message")
    }
}
