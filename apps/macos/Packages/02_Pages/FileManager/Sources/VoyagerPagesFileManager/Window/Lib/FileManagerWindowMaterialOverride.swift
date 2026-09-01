import AppKit

struct FileManagerWindowMaterialOverride {
    struct Surface {
        let material: NSVisualEffectView.Material
        let blendingMode: NSVisualEffectView.BlendingMode
        let alphaValue: CGFloat

        @MainActor
        func apply(to view: NSVisualEffectView) {
            view.material = material
            view.blendingMode = blendingMode
            view.alphaValue = alphaValue
        }
    }

    let windowShell: Surface
    let contentBackground: Surface
    let listHeader: Surface
    let groupRowLightOpacity: CGFloat
    let groupRowDarkOpacity: CGFloat
}
