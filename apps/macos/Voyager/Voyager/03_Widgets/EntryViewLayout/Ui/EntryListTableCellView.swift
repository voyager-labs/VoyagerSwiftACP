import AppKit

struct EntryListEntryCellViewConfiguration {
    let context: Context

    struct Context {
        let model: EntryModel
        let columnId: String
        let iconSize: CGFloat
        let textSize: CGFloat
        let dateModifiedWidth: CGFloat
        let thumbnail: NSImage?
        let isHidden: Bool
        let isCut: Bool
        let isRenaming: Bool
        let renamingText: String
        let workspaceClient: WorkspaceClient
        let onRenameUpdate: ((String) -> Void)?
        let onRenameCommit: (() -> Void)?
        let onRenameCancel: (() -> Void)?
    }
}

private enum EntryListCellTextFieldStyle {
    static func applyDefaultTextTruncation(to textField: NSTextField) {
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
    }
}

private enum EntryListCellDateFormatting {
    private struct CacheKey: Hashable {
        let template: String
        let localeIdentifier: String
        let timeZoneIdentifier: String
    }

    private static let lock = NSLock()
    private static var cache: [CacheKey: DateFormatter] = [:]

    static func template(forWidth width: CGFloat) -> String {
        guard width.isFinite, width > 0 else { return "yMd" }
        if width < 140 { return "yMd" }
        if width < 220 { return "MMMd" }
        return "yMMMdjm"
    }

    static func format(
        _ date: Date,
        width: CGFloat,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
    ) -> String {
        let template = template(forWidth: width)
        let key = CacheKey(
            template: template,
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: timeZone.identifier,
        )

        lock.lock()
        defer { lock.unlock() }

        let formatter = cache[key] ?? {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            cache[key] = formatter
            return formatter
        }()

        return formatter.string(from: date)
    }
}

final class EntryListGroupHeaderCellView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        EntryListCellTextFieldStyle.applyDefaultTextTruncation(to: titleField)
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        addSubview(titleField)
        textField = titleField

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(title: String, colorCode: Int?) {
        guard let colorCode else {
            titleField.stringValue = title
            return
        }

        let attachment = NSTextAttachment()
        attachment.image = TagDotImageFactory.make(
            tagColor: TagColor(colorCode: colorCode),
            size: 10,
            inset: 1,
        )
        attachment.bounds = NSRect(x: 0, y: -1, width: 10, height: 10)

        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.append(NSAttributedString(string: " "))
        attributed.append(NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)],
        ))
        titleField.attributedStringValue = attributed
    }
}

final class EntryListEmptyCellView: NSTableCellView {}

final class EntryListEntryCellView: NSTableCellView {
    private let customImageView = NSImageView()
    private let customTextField = NSTextField(labelWithString: "")

    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var textLeadingToIconConstraint: NSLayoutConstraint?
    private var textLeadingToViewConstraint: NSLayoutConstraint?

    private var isRenaming: Bool = false
    private var isHiddenEntry: Bool = false
    private var isCutEntry: Bool = false
    var onRenameUpdate: ((String) -> Void)?
    var onRenameCommit: (() -> Void)?
    var onRenameCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        customImageView.translatesAutoresizingMaskIntoConstraints = false
        customImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(customImageView)
        imageView = customImageView

        customTextField.translatesAutoresizingMaskIntoConstraints = false
        EntryListCellTextFieldStyle.applyDefaultTextTruncation(to: customTextField)
        addSubview(customTextField)
        textField = customTextField

        let iconLeading = customImageView.leadingAnchor.constraint(equalTo: leadingAnchor)
        let iconCenterY = customImageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        let iconWidth = customImageView.widthAnchor.constraint(equalToConstant: 16)
        let iconHeight = customImageView.heightAnchor.constraint(equalToConstant: 16)

        iconWidthConstraint = iconWidth
        iconHeightConstraint = iconHeight

        textLeadingToIconConstraint = customTextField.leadingAnchor.constraint(
            equalTo: customImageView.trailingAnchor,
            constant: 6,
        )
        textLeadingToViewConstraint = customTextField.leadingAnchor.constraint(equalTo: leadingAnchor)
        let textTrailing = customTextField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        let textCenterY = customTextField.centerYAnchor.constraint(equalTo: centerYAnchor)

        NSLayoutConstraint.activate([
            iconLeading,
            iconCenterY,
            iconWidth,
            iconHeight,
            textTrailing,
            textCenterY,
        ])
    }

    func configure(_ configuration: EntryListEntryCellViewConfiguration) {
        let context = configuration.context
        onRenameUpdate = context.onRenameUpdate
        onRenameCommit = context.onRenameCommit
        onRenameCancel = context.onRenameCancel
        configureEntryCell(context: context)
    }

    func beginRenaming() {
        guard isRenaming else { return }
        window?.makeFirstResponder(customTextField)
        customTextField.selectText(nil)
    }

    private func configureEntryCell(context: EntryListEntryCellViewConfiguration.Context) {
        isRenaming = context.isRenaming
        isHiddenEntry = context.isHidden
        isCutEntry = context.isCut
        let display = EntryDisplayModel(entry: context.model)

        switch EntryListColumn(rawValue: context.columnId) {
        case .name:
            customImageView.isHidden = false
            iconWidthConstraint?.constant = context.iconSize
            iconHeightConstraint?.constant = context.iconSize
            textLeadingToViewConstraint?.isActive = false
            textLeadingToIconConstraint?.isActive = true

            customImageView.image = context.workspaceClient.entryIcon(for: context.model, thumbnail: context.thumbnail)

            customTextField.font = .systemFont(ofSize: context.textSize)
            customTextField.lineBreakMode = .byTruncatingMiddle
            customTextField.usesSingleLineMode = true

            if isRenaming {
                applyRenamingStyle(text: context.renamingText)
            } else {
                applyDisplayStyle()
                customTextField.stringValue = context.model.name
            }

        case .dateModified:
            hideIconAndSetupTextOnly(textSize: max(10, context.textSize - 1))
            customTextField.stringValue = EntryListCellDateFormatting.format(
                context.model.modifiedDate,
                width: context.dateModifiedWidth,
            )

        case .size:
            hideIconAndSetupTextOnly(textSize: max(10, context.textSize - 1))
            customTextField.stringValue = display.formattedSize

        case .kind:
            hideIconAndSetupTextOnly(textSize: max(10, context.textSize - 1))
            let kindText = context.model.fileExtension.lowercased() == CollectionConstants
                .fileExtension ? "Voyager Collection" : context.model.facets.kind
            customTextField.stringValue = kindText

        default:
            hideIconAndSetupTextOnly(textSize: context.textSize)
            customTextField.stringValue = ""
        }

        applyContentAlpha()
    }

    private func hideIconAndSetupTextOnly(textSize: CGFloat) {
        customImageView.isHidden = true
        customImageView.image = nil
        textLeadingToIconConstraint?.isActive = false
        textLeadingToViewConstraint?.isActive = true
        customTextField.font = .systemFont(ofSize: textSize)
        EntryListCellTextFieldStyle.applyDefaultTextTruncation(to: customTextField)
        applyDisplayStyle()
    }

    private func applyDisplayStyle() {
        customTextField.isEditable = false
        customTextField.isSelectable = false
        customTextField.isBordered = false
        customTextField.drawsBackground = false
        customTextField.focusRingType = .none
        customTextField.delegate = nil
        applyContentAlpha()
    }

    private func applyRenamingStyle(text: String) {
        customTextField.isEditable = true
        customTextField.isSelectable = true
        customTextField.isBordered = true
        customTextField.drawsBackground = true
        customTextField.backgroundColor = .textBackgroundColor
        customTextField.focusRingType = .default

        customTextField.stringValue = EntryGridRenameEditorRules.sanitizeInput(text)
        customTextField.delegate = self
        applyContentAlpha()
    }

    private func applyContentAlpha() {
        let alpha: CGFloat = (isHiddenEntry || isCutEntry) ? 0.5 : 1.0
        customImageView.alphaValue = alpha
        customTextField.alphaValue = alpha
    }
}

extension EntryListEntryCellView: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard isRenaming else { return }
        guard let textField = notification.object as? NSTextField, textField === customTextField else { return }
        let sanitized = EntryGridRenameEditorRules.sanitizeInput(textField.stringValue)
        if sanitized != textField.stringValue {
            textField.stringValue = sanitized
        }
        onRenameUpdate?(sanitized)
    }

    func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard isRenaming else { return false }
        guard let textField = control as? NSTextField, textField === customTextField else { return false }

        switch EntryGridRenameEditorRules.commandAction(for: commandSelector) {
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
        guard let textField = notification.object as? NSTextField, textField === customTextField else { return }
        onRenameCommit?()
    }
}
