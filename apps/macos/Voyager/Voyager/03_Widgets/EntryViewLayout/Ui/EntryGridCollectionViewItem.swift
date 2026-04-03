import AppKit
import UniformTypeIdentifiers

final class EntryGridCollectionViewItem: NSCollectionViewItem {
    struct Configuration {
        let entry: EntryModel
        let iconSize: CGFloat
        let textSize: CGFloat
        let thumbnail: NSImage?
        let isCut: Bool
        let isHidden: Bool
        let isRenaming: Bool
        let renamingText: String
        let isDropTargeted: Bool
        let workspaceClient: WorkspaceClient
        let onRenameUpdate: (String) -> Void
        let onRenameCommit: () -> Void
        let onRenameCancel: () -> Void
    }

    private let backgroundView = NSView()
    private let iconView = NSImageView()
    private let iconBackgroundView = NSView()
    private let nameContainerView = NSView()
    private let nameHighlightView = NSView()
    private let nameField = NSTextField(string: "")
    private let infoField = NSTextField(labelWithString: "")
    private let tagStackView = NSStackView()

    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var iconBackgroundWidthConstraint: NSLayoutConstraint?
    private var iconBackgroundHeightConstraint: NSLayoutConstraint?

    private var entry: EntryModel?
    private var iconSize: CGFloat = 64
    private var textSize: CGFloat = 12
    private var isCut: Bool = false
    private var isHiddenEntry: Bool = false
    private var isRenaming: Bool = false
    private var isDropTargeted: Bool = false
    private var workspaceClient: WorkspaceClient?

    var onRenameUpdate: ((String) -> Void)?
    var onRenameCommit: (() -> Void)?
    var onRenameCancel: (() -> Void)?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    override var isSelected: Bool {
        didSet {
            updateAppearance()
        }
    }

    func configure(_ configuration: Configuration) {
        entry = configuration.entry
        iconSize = configuration.iconSize
        textSize = configuration.textSize
        isCut = configuration.isCut
        isHiddenEntry = configuration.isHidden
        isRenaming = configuration.isRenaming
        isDropTargeted = configuration.isDropTargeted
        workspaceClient = configuration.workspaceClient
        onRenameUpdate = configuration.onRenameUpdate
        onRenameCommit = configuration.onRenameCommit
        onRenameCancel = configuration.onRenameCancel

        iconView.image = configuration.workspaceClient.entryIcon(
            for: configuration.entry,
            thumbnail: configuration.thumbnail,
        )
        iconView.imageScaling = .scaleProportionallyUpOrDown

        nameField.font = NSFont.systemFont(ofSize: textSize)
        nameField.alignment = .center
        nameField.maximumNumberOfLines = 2
        nameField.lineBreakMode = .byTruncatingMiddle

        infoField.font = NSFont.systemFont(ofSize: max(8, textSize - 1))
        updateIconConstraints()

        if configuration.isRenaming {
            applyRenamingStyle(text: configuration.renamingText)
        } else {
            applyDisplayStyle(text: configuration.entry.name)
        }

        let display = EntryDisplayModel(entry: configuration.entry)
        if !configuration.isRenaming, let supplementaryInfoText = display.supplementaryInfoText {
            infoField.isHidden = false
            infoField.stringValue = supplementaryInfoText
        } else {
            infoField.isHidden = true
        }

        updateTags(configuration.entry.facets.tags)
        updateAppearance()
    }

    func beginRenaming() {
        guard isRenaming else { return }
        view.window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
        if let entry,
           let editor = nameField.currentEditor() as? NSTextView
        {
            let range = EntryInlineRenameEditorRules.initialSelectionRange(
                for: entry.name,
                isFolder: entry.isFolder,
            )
            editor.setSelectedRange(range)
        }
    }

    // swiftlint:disable:next function_body_length
    private func setupViews() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 8

        iconBackgroundView.identifier = NSUserInterfaceItemIdentifier("entryGrid.iconBackground")
        nameContainerView.identifier = NSUserInterfaceItemIdentifier("entryGrid.nameContainer")
        nameHighlightView.identifier = NSUserInterfaceItemIdentifier("entryGrid.nameHighlight")
        nameField.identifier = NSUserInterfaceItemIdentifier("entryGrid.nameField")
        tagStackView.identifier = NSUserInterfaceItemIdentifier("entryGrid.tagStack")

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 8
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)

        iconBackgroundView.wantsLayer = true
        iconBackgroundView.layer?.cornerRadius = 8
        iconBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBackgroundView.addSubview(iconView)

        tagStackView.orientation = .horizontal
        tagStackView.alignment = .centerY
        tagStackView.spacing = 4
        tagStackView.translatesAutoresizingMaskIntoConstraints = false
        tagStackView.setContentHuggingPriority(.required, for: .horizontal)
        tagStackView.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameContainerView.translatesAutoresizingMaskIntoConstraints = false
        nameContainerView.setContentHuggingPriority(.required, for: .horizontal)
        nameContainerView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        nameHighlightView.wantsLayer = true
        nameHighlightView.layer?.cornerRadius = 4
        nameHighlightView.translatesAutoresizingMaskIntoConstraints = false
        nameContainerView.addSubview(nameHighlightView)

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameContainerView.addSubview(nameField)
        infoField.translatesAutoresizingMaskIntoConstraints = false
        infoField.font = NSFont.systemFont(ofSize: max(8, textSize - 1))
        infoField.textColor = NSColor.systemBlue
        infoField.alignment = .center
        infoField.lineBreakMode = .byTruncatingTail

        NSLayoutConstraint.activate([
            nameHighlightView.leadingAnchor.constraint(equalTo: nameContainerView.leadingAnchor),
            nameHighlightView.trailingAnchor.constraint(equalTo: nameContainerView.trailingAnchor),
            nameHighlightView.topAnchor.constraint(equalTo: nameContainerView.topAnchor),
            nameHighlightView.bottomAnchor.constraint(equalTo: nameContainerView.bottomAnchor),

            nameField.leadingAnchor.constraint(equalTo: nameContainerView.leadingAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: nameContainerView.trailingAnchor, constant: -6),
            nameField.topAnchor.constraint(equalTo: nameContainerView.topAnchor, constant: 2),
            nameField.bottomAnchor.constraint(equalTo: nameContainerView.bottomAnchor, constant: -2),
        ])

        let textStack = NSStackView(views: [tagStackView, nameContainerView, infoField])
        textStack.orientation = .vertical
        textStack.alignment = .centerX
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [iconBackgroundView, textStack])
        rootStack.orientation = .vertical
        rootStack.alignment = .centerX
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        activateConstraints(rootStack: rootStack)
        cacheIconConstraints()
        applyDisplayStyle(text: "")
    }

    private func activateConstraints(rootStack: NSStackView) {
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: iconBackgroundView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackgroundView.centerYAnchor),
            iconWidthConstraint ?? iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconHeightConstraint ?? iconView.heightAnchor.constraint(equalToConstant: iconSize),

            iconBackgroundWidthConstraint ?? iconBackgroundView.widthAnchor.constraint(equalToConstant: iconSize + 16),
            iconBackgroundHeightConstraint ?? iconBackgroundView.heightAnchor
                .constraint(equalToConstant: iconSize + 16),

            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
        ])
    }

    private func cacheIconConstraints() {
        iconWidthConstraint = iconView.constraints.first { $0.firstAttribute == .width }
        iconHeightConstraint = iconView.constraints.first { $0.firstAttribute == .height }
        iconBackgroundWidthConstraint = iconBackgroundView.constraints.first { $0.firstAttribute == .width }
        iconBackgroundHeightConstraint = iconBackgroundView.constraints.first { $0.firstAttribute == .height }
    }

    private func updateIconConstraints() {
        iconWidthConstraint?.constant = iconSize
        iconHeightConstraint?.constant = iconSize
        iconBackgroundWidthConstraint?.constant = iconSize + 16
        iconBackgroundHeightConstraint?.constant = iconSize + 16
    }

    private func updateAppearance() {
        let isHighlighted = isSelected
        let dropHighlighted = isDropTargeted
        let selectionBackground = (view.window?.isKeyWindow ?? true)
            ? NSColor.selectedTextBackgroundColor
            : NSColor.unemphasizedSelectedTextBackgroundColor
        let dropBackground = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.22)

        // 선택 스타일은 라벨(name/info) 강조를 기본으로 하고,
        // drop target 하이라이트만 타일(border/background)을 사용합니다.
        if dropHighlighted {
            backgroundView.layer?.backgroundColor = dropBackground.cgColor
            backgroundView.layer?.borderWidth = 1.5
            backgroundView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
            backgroundView.layer?.borderWidth = 0
            backgroundView.layer?.borderColor = nil
        }
        iconBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor

        if isHighlighted, !isRenaming {
            nameHighlightView.isHidden = false
            nameHighlightView.layer?.backgroundColor = selectionBackground.cgColor
            nameField.textColor = .selectedTextColor
        } else if !isRenaming {
            nameHighlightView.isHidden = true
            nameHighlightView.layer?.backgroundColor = nil
            nameField.textColor = .labelColor
        }

        infoField.isBordered = false
        infoField.drawsBackground = isHighlighted
        infoField.backgroundColor = isHighlighted ? selectionBackground : .clear
        infoField.textColor = isHighlighted ? .selectedTextColor : .systemBlue

        let alpha: CGFloat = (isHiddenEntry || isCut) ? 0.5 : 1.0
        iconView.alphaValue = alpha
        nameField.alphaValue = alpha
        infoField.alphaValue = alpha
        tagStackView.alphaValue = alpha
    }

    private func applyRenamingStyle(text: String) {
        nameHighlightView.isHidden = true
        nameHighlightView.layer?.backgroundColor = nil
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.isBordered = true
        nameField.drawsBackground = true
        nameField.backgroundColor = NSColor.textBackgroundColor
        nameField.focusRingType = .default
        nameField.usesSingleLineMode = true
        nameField.lineBreakMode = .byTruncatingTail
        nameField.maximumNumberOfLines = 1
        nameField.cell?.wraps = false
        nameField.cell?.isScrollable = true
        nameField.stringValue = EntryInlineRenameEditorRules.sanitizeInput(text)
        nameField.delegate = self
    }

    private func applyDisplayStyle(text: String) {
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.usesSingleLineMode = false
        nameField.stringValue = text
        nameField.delegate = nil
    }

    private func updateTags(_ tags: [Tag]?) {
        for view in tagStackView.arrangedSubviews {
            tagStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let tags, !tags.isEmpty else {
            tagStackView.isHidden = true
            return
        }

        tagStackView.isHidden = false
        let visibleTags = tags.prefix(3)
        for tag in visibleTags {
            let dot = TagDotNSView(tagColor: tag.tagColor, size: 8)
            tagStackView.addArrangedSubview(dot)
        }
    }
}

extension EntryGridCollectionViewItem: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard isRenaming else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard textField === nameField else { return }
        let sanitized = EntryInlineRenameEditorRules.sanitizeInput(textField.stringValue)
        if sanitized != textField.stringValue {
            textField.stringValue = sanitized
        }
        onRenameUpdate?(sanitized)
    }

    func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard isRenaming else { return false }
        guard let textField = control as? NSTextField, textField === nameField else { return false }

        switch EntryInlineRenameEditorRules.commandAction(for: commandSelector) {
        case .commit:
            onRenameCommit?()
            return true
        case .cancel:
            onRenameCancel?()
            return true
        case .none:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard isRenaming else { return }
        guard let textField = notification.object as? NSTextField, textField === nameField else { return }
        guard let movement = notification.userInfo?["NSTextMovement"] as? Int else { return }

        switch movement {
        case NSReturnTextMovement, NSTabTextMovement:
            onRenameCommit?()
        case NSCancelTextMovement:
            onRenameCancel?()
        default:
            return
        }
    }
}
