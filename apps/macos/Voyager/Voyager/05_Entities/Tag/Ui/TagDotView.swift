// TODO(sunset VOY-272): UI component — remains app-layer; move to appropriate UI layer when 05_Entities is sunset.
import AppKit
import SwiftUI

import VoyagerEntitiesEntry
import VoyagerEntitiesTag

struct TagDotView: View {
    let tagColor: TagColor
    let size: CGFloat

    init(tagColor: TagColor, size: CGFloat = 8) {
        self.tagColor = tagColor
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(Color(nsColor: tagColor.nsColor))
            .frame(width: size, height: size)
    }
}

final class TagDotNSView: NSView {
    private var dotSize: CGFloat

    init(tagColor: TagColor, size: CGFloat = 8) {
        dotSize = size
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
        update(tagColor: tagColor)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(tagColor: TagColor) {
        layer?.backgroundColor = tagColor.nsColor.cgColor
        layer?.cornerRadius = dotSize / 2
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: dotSize, height: dotSize)
    }
}

enum TagDotImageFactory {
    static func make(tagColor: TagColor, size: CGFloat = 11, inset: CGFloat = 1) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        let color = tagColor.nsColor

        let image = NSImage(size: imageSize, flipped: false) { rect in
            let circleRect = rect.insetBy(dx: inset, dy: inset)
            color.setFill()
            NSBezierPath(ovalIn: circleRect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
