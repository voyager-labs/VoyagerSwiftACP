import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class EntryGridCollectionViewItem: NSCollectionViewItem {
    struct Configuration {
        let entry: Entry
        let iconSize: CGFloat
        let textSize: CGFloat
        let isThumbnailReady: Bool
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
    private let nameField = NSTextField(labelWithString: "")
    private let infoField = NSTextField(labelWithString: "")
    private let tagStackView = NSStackView()

    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var iconBackgroundWidthConstraint: NSLayoutConstraint?
    private var iconBackgroundHeightConstraint: NSLayoutConstraint?

    private var entry: Entry?
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

        iconView.image = makeIcon(for: configuration.entry, isThumbnailReady: configuration.isThumbnailReady)
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

        if let additionalInfo = configuration.entry.additionalInfo, !additionalInfo.isEmpty {
            infoField.isHidden = false
            infoField.stringValue = additionalInfo
        } else {
            infoField.isHidden = true
        }

        updateTags(configuration.entry.tags)
        updateAppearance()
    }

    func beginRenaming() {
        guard isRenaming else { return }
        view.window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    private func setupViews() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 8

        backgroundView.wantsLayer = true
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

        nameField.translatesAutoresizingMaskIntoConstraints = false
        infoField.translatesAutoresizingMaskIntoConstraints = false
        infoField.font = NSFont.systemFont(ofSize: max(8, textSize - 1))
        infoField.textColor = NSColor.systemBlue
        infoField.alignment = .center
        infoField.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [tagStackView, nameField, infoField])
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
        let highlight = isSelected || isDropTargeted
        backgroundView.layer?.backgroundColor = highlight
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor
            : NSColor.clear.cgColor
        iconBackgroundView.layer?.backgroundColor = highlight
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        let nameColor: NSColor = highlight && !isRenaming ? .white : .labelColor
        let infoColor: NSColor = highlight ? .white : .systemBlue
        nameField.textColor = nameColor
        infoField.textColor = infoColor

        let alpha: CGFloat = (isHiddenEntry || isCut) ? 0.5 : 1.0
        iconView.alphaValue = alpha
        nameField.alphaValue = alpha
        infoField.alphaValue = alpha
        tagStackView.alphaValue = alpha
    }

    private func applyRenamingStyle(text: String) {
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.isBordered = true
        nameField.drawsBackground = true
        nameField.backgroundColor = NSColor.textBackgroundColor
        nameField.focusRingType = .default
        nameField.usesSingleLineMode = true
        nameField.stringValue = text
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

    private func updateTags(_ tags: [FileTag]?) {
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
            let color = EntryTagUtils.getTagColor(colorCode: tag.colorCode)
            let dot = TagDotView(color: NSColor(color), size: 8)
            tagStackView.addArrangedSubview(dot)
        }
    }

    private func makeIcon(for entry: Entry, isThumbnailReady: Bool) -> NSImage {
        if let cached = EntryIconUtils.getThumbnail(for: entry.fullPath), isThumbnailReady {
            return cached
        }

        let cacheKey: String = if entry.fullPath == "/" {
            "root:/"
        } else if entry.fileExtension.lowercased() == "voycoll" {
            "asset:\(EntryIconUtils.voycollIconName)"
        } else if entry.isDirectory {
            "dir:\(entry.fullPath)"
        } else {
            UTType(filenameExtension: entry.fileExtension)
                .map { "type:\($0.identifier)" }
                ?? "generic:file"
        }

        if let cached = EntryIconUtils.getCachedIcon(for: cacheKey) {
            return cached
        }

        let icon: NSImage = if entry.fullPath == "/" {
            workspaceClient?.iconForFile("/") ?? NSImage()
        } else if entry.fileExtension.lowercased() == "voycoll" {
            NSImage(named: EntryIconUtils.voycollIconName)
                ?? workspaceClient?.iconForType(.data)
                ?? NSImage()
        } else if entry.isDirectory {
            workspaceClient?.iconForFile(entry.fullPath) ?? NSImage()
        } else {
            if let utType = UTType(filenameExtension: entry.fileExtension) {
                workspaceClient?.iconForType(utType) ?? NSImage()
            } else {
                workspaceClient?.iconForType(.data) ?? NSImage()
            }
        }

        if icon.size != .zero {
            EntryIconUtils.setCachedIcon(icon, for: cacheKey)
        }
        return icon
    }
}

extension EntryGridCollectionViewItem: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard isRenaming else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard textField === nameField else { return }
        onRenameUpdate?(textField.stringValue)
    }

    func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard isRenaming else { return false }
        guard let textField = control as? NSTextField, textField === nameField else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onRenameCommit?()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onRenameCancel?()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            onRenameCommit?()
            return true
        }

        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard isRenaming else { return }
        guard let textField = notification.object as? NSTextField, textField === nameField else { return }
        onRenameCommit?()
    }
}

private final class TagDotView: NSView {
    private let dotSize: CGFloat

    init(color: NSColor, size: CGFloat) {
        dotSize = size
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = size / 2
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: dotSize, height: dotSize)
    }
}
