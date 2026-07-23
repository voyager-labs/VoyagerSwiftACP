import SwiftUI

public struct VisualEffectBackgroundView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode
    public let state: NSVisualEffectView.State
    public let materialOpacity: CGFloat
    public let tintColor: NSColor?
    public let tintOpacity: CGFloat

    public init(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .followsWindowActiveState,
        materialOpacity: CGFloat = 1.0,
        tintColor: NSColor? = nil,
        tintOpacity: CGFloat = 0.0,
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.materialOpacity = materialOpacity
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
    }

    public init(surfaceRole: VoyagerDS.SurfaceMaterialRole) {
        let configuration = surfaceRole.appKitConfiguration
        self.init(
            material: configuration.material,
            blendingMode: configuration.blendingMode,
            state: configuration.state,
            materialOpacity: configuration.opacity,
        )
    }

    public func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        applyConfiguration(to: view)

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

    public func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        applyConfiguration(to: view)

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

    func applyConfiguration(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.alphaValue = materialOpacity
    }
}
