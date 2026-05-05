import AppKit
import SwiftUI

struct ColorDotView: View {
    let color: Color
    let size: CGFloat

    init(color: Color, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }

    init(nsColor: NSColor, size: CGFloat = 8) {
        self.init(color: Color(nsColor: nsColor), size: size)
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

final class ColorDotNSView: NSView {
    private let dotSize: CGFloat

    init(color: NSColor, size: CGFloat = 8) {
        dotSize = size
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
        update(color: color)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(color: NSColor) {
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = dotSize / 2
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: dotSize, height: dotSize)
    }
}

enum ColorDotImageFactory {
    static func make(color: NSColor, size: CGFloat = 11, inset: CGFloat = 1) -> NSImage {
        let imageSize = NSSize(width: size, height: size)

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
