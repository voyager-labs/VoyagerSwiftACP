import AppKit
import SwiftUI

final class EntryGridSectionHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let toggleButton = NSButton()
    private let colorDotView = NSView()
    private var onToggle: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String?,
        count: Int,
        colorCode: Int?,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void,
    ) {
        self.onToggle = onToggle
        titleLabel.stringValue = title ?? ""
        countLabel.stringValue = "(\(count))"

        toggleButton.image = NSImage(
            systemSymbolName: isCollapsed ? "chevron.right" : "chevron.down",
            accessibilityDescription: nil,
        )
        toggleButton.isHidden = title == nil

        if let colorCode {
            colorDotView.isHidden = false
            let color = EntryTagUtils.getTagColor(colorCode: colorCode)
            colorDotView.layer?.backgroundColor = NSColor(color).cgColor
        } else {
            colorDotView.isHidden = true
        }
    }

    private func setupViews() {
        wantsLayer = true

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        countLabel.textColor = NSColor.secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        toggleButton.bezelStyle = .regularSquare
        toggleButton.isBordered = false
        toggleButton.contentTintColor = NSColor.secondaryLabelColor
        toggleButton.target = self
        toggleButton.action = #selector(handleToggle)
        toggleButton.translatesAutoresizingMaskIntoConstraints = false

        colorDotView.wantsLayer = true
        colorDotView.layer?.cornerRadius = 4
        colorDotView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [colorDotView, titleLabel, countLabel, toggleButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            colorDotView.widthAnchor.constraint(equalToConstant: 8),
            colorDotView.heightAnchor.constraint(equalToConstant: 8),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc
    private func handleToggle() {
        onToggle?()
    }
}
