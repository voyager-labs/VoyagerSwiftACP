import AppKit
import SwiftUI

struct VisualEffectBackgroundView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let tintColor: NSColor?
    let tintOpacity: CGFloat

    init(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        tintColor: NSColor? = nil,
        tintOpacity: CGFloat = 0.0,
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
    }

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState

        if let tintColor {
            let tintView = NSView()
            tintView.wantsLayer = true
            tintView.layer?.backgroundColor = tintColor.cgColor
            tintView.alphaValue = tintOpacity
            tintView.autoresizingMask = [.width, .height]
            tintView.frame = view.bounds
            view.addSubview(tintView)
        }

        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        view.material = material
        view.blendingMode = blendingMode

        if let tintView = view.subviews.first {
            if let tintColor {
                tintView.layer?.backgroundColor = tintColor.cgColor
                tintView.alphaValue = tintOpacity
                tintView.isHidden = false
            } else {
                tintView.isHidden = true
            }
        } else if let tintColor {
            let tintView = NSView()
            tintView.wantsLayer = true
            tintView.layer?.backgroundColor = tintColor.cgColor
            tintView.alphaValue = tintOpacity
            tintView.autoresizingMask = [.width, .height]
            tintView.frame = view.bounds
            view.addSubview(tintView)
        }
    }
}
