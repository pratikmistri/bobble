import AppKit

private struct UsageMenuItemGroup {
    let item: NSMenuItem
    let rowView: UsageMenuRowView
}

private final class UsageMenuRowView: NSView {
    private static let rowSize = NSSize(width: 264, height: 72)
    private static let horizontalInset: CGFloat = 16
    private static let verticalInset: CGFloat = 8

    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let captionLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()

    override var intrinsicContentSize: NSSize {
        Self.rowSize
    }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingHead

        captionLabel.font = .systemFont(ofSize: 10)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.lineBreakMode = .byWordWrapping
        captionLabel.cell?.wraps = true
        captionLabel.cell?.usesSingleLineMode = false

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [titleLabel, valueLabel])
        headerStack.orientation = .horizontal
        headerStack.distribution = .fill
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [headerStack, progressIndicator, captionLabel])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 5
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalInset),

            headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            progressIndicator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 10),
            captionLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ summary: ProviderUsageSummary) {
        titleLabel.stringValue = summary.title
        valueLabel.stringValue = summary.valueText
        captionLabel.stringValue = summary.caption

        switch summary.progressState {
        case .determinate(let fraction):
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0
            progressIndicator.maxValue = 1
            progressIndicator.doubleValue = max(0, min(fraction, 1))
            progressIndicator.alphaValue = 1
        case .indeterminate:
            progressIndicator.isIndeterminate = true
            progressIndicator.alphaValue = 1
            progressIndicator.startAnimation(nil)
        case .informational:
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0
            progressIndicator.maxValue = 1
            progressIndicator.doubleValue = 0
            progressIndicator.alphaValue = 0.2
        case .unavailable:
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0
            progressIndicator.maxValue = 1
            progressIndicator.doubleValue = 0
            progressIndicator.alphaValue = 0.45
        }
    }
}

final class StatusBarController: NSObject, NSMenuDelegate {
    var onSelectProvider: ((CLIBackend) -> Void)?
    var onSelectLayoutMode: ((ChatHeadsLayoutMode) -> Void)?
    var onQuit: (() -> Void)?

    private let usageMonitor: UsageMonitor
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var providerMenuItems: [CLIBackend: NSMenuItem] = [:]
    private var layoutMenuItems: [ChatHeadsLayoutMode: NSMenuItem] = [:]
    private var usageMenuItems: [CLIBackend: UsageMenuItemGroup] = [:]
    private var refreshUsageMenuItem: NSMenuItem?
    private var isRefreshingUsage = false

    init(usageMonitor: UsageMonitor = UsageMonitor()) {
        self.usageMonitor = usageMonitor
        super.init()
    }

    func install(selectedProvider: CLIBackend, selectedLayoutMode: ChatHeadsLayoutMode) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusBarIcon()
            button.toolTip = "Bobble"
        }

        let menu = makeStatusMenu()
        statusMenu = menu
        statusItem?.menu = menu
        updateSelectedProvider(selectedProvider)
        updateSelectedLayoutMode(selectedLayoutMode)
        refreshUsage()
    }

    func updateSelectedProvider(_ provider: CLIBackend) {
        for (candidate, item) in providerMenuItems {
            item.state = candidate == provider ? .on : .off
        }

        statusItem?.button?.toolTip = "Bobble (\(provider.displayName))"
    }

    func updateSelectedLayoutMode(_ layoutMode: ChatHeadsLayoutMode) {
        for (candidate, item) in layoutMenuItems {
            item.state = candidate == layoutMode ? .on : .off
        }
    }

    func refreshUsage(force: Bool = false) {
        guard !isRefreshingUsage else { return }

        isRefreshingUsage = true
        refreshUsageMenuItem?.title = "Refreshing Usage..."
        refreshUsageMenuItem?.isEnabled = false

        usageMonitor.refresh(force: force) { [weak self] summaries in
            guard let self else { return }

            for provider in CLIBackend.allCases {
                guard let group = self.usageMenuItems[provider] else { continue }
                let summary = summaries[provider] ?? ProviderUsageSummary.unavailable(
                    for: provider,
                    caption: "No local usage source found."
                )
                group.rowView.apply(summary)
            }

            self.refreshUsageMenuItem?.title = "Refresh Usage"
            self.refreshUsageMenuItem?.isEnabled = true
            self.isRefreshingUsage = false
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        refreshUsage()
    }

    private func makeStatusBarIcon() -> NSImage? {
        let icon = NSImage(named: NSImage.Name("menubar"))
            ?? NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "Bobble")
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        return icon
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let providerRoot = NSMenuItem(title: "Agents", action: nil, keyEquivalent: "")
        let providerSubmenu = NSMenu()
        providerMenuItems.removeAll()

        for provider in CLIBackend.allCases {
            let item = NSMenuItem(
                title: provider.displayName,
                action: #selector(selectProvider(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = provider.rawValue
            providerMenuItems[provider] = item
            providerSubmenu.addItem(item)
        }

        providerRoot.submenu = providerSubmenu
        menu.addItem(providerRoot)
        menu.addItem(.separator())

        let layoutRoot = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        let layoutSubmenu = NSMenu()
        layoutMenuItems.removeAll()

        for layoutMode in ChatHeadsLayoutMode.allCases {
            let item = NSMenuItem(
                title: layoutMode.menuTitle,
                action: #selector(selectLayoutMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = layoutMode.rawValue
            layoutMenuItems[layoutMode] = item
            layoutSubmenu.addItem(item)
        }

        layoutRoot.submenu = layoutSubmenu
        menu.addItem(layoutRoot)
        menu.addItem(.separator())

        let usageHeader = NSMenuItem(title: "Usage", action: nil, keyEquivalent: "")
        usageHeader.isEnabled = false
        menu.addItem(usageHeader)
        usageMenuItems.removeAll()

        for provider in CLIBackend.allCases {
            let item = NSMenuItem()
            item.isEnabled = false

            let rowView = UsageMenuRowView()
            rowView.apply(.loading(for: provider))
            item.view = rowView

            usageMenuItems[provider] = UsageMenuItemGroup(item: item, rowView: rowView)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh Usage", action: #selector(refreshUsageMenuAction(_:)), keyEquivalent: "")
        refreshItem.target = self
        refreshUsageMenuItem = refreshItem
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Bobble", action: #selector(quitAction(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let provider = CLIBackend(rawValue: rawValue) else {
            return
        }

        onSelectProvider?(provider)
    }

    @objc private func selectLayoutMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let layoutMode = ChatHeadsLayoutMode(rawValue: rawValue) else {
            return
        }

        onSelectLayoutMode?(layoutMode)
    }

    @objc private func refreshUsageMenuAction(_ sender: Any?) {
        refreshUsage(force: true)
    }

    @objc private func quitAction(_ sender: Any?) {
        onQuit?()
    }
}
