import Foundation
import SwiftUI

enum SwiftUIColorResolutionScope {
    case fixed
    case dynamic
}

struct SwiftUISystemColor {
    let cssName: String
    let color: Color
    let resolutionScope: SwiftUIColorResolutionScope

    init(
        cssName: String,
        color: Color,
        resolutionScope: SwiftUIColorResolutionScope = .dynamic,
    ) {
        self.cssName = cssName
        self.color = color
        self.resolutionScope = resolutionScope
    }
}

@available(macOS 14.0, *)
@MainActor
func swiftUISystemColors() -> [SwiftUISystemColor] {
    [
        SwiftUISystemColor(cssName: "--swiftui-primary", color: .primary),
        SwiftUISystemColor(cssName: "--swiftui-secondary", color: .secondary),
        SwiftUISystemColor(cssName: "--swiftui-accent-color", color: .accentColor),
        SwiftUISystemColor(cssName: "--swiftui-black", color: .black, resolutionScope: .fixed),
        SwiftUISystemColor(cssName: "--swiftui-white", color: .white, resolutionScope: .fixed),
        SwiftUISystemColor(cssName: "--swiftui-clear", color: .clear, resolutionScope: .fixed),
        SwiftUISystemColor(cssName: "--swiftui-blue", color: .blue),
        SwiftUISystemColor(cssName: "--swiftui-brown", color: .brown),
        SwiftUISystemColor(cssName: "--swiftui-cyan", color: .cyan),
        SwiftUISystemColor(cssName: "--swiftui-gray", color: .gray),
        SwiftUISystemColor(cssName: "--swiftui-green", color: .green),
        SwiftUISystemColor(cssName: "--swiftui-indigo", color: .indigo),
        SwiftUISystemColor(cssName: "--swiftui-mint", color: .mint),
        SwiftUISystemColor(cssName: "--swiftui-orange", color: .orange),
        SwiftUISystemColor(cssName: "--swiftui-pink", color: .pink),
        SwiftUISystemColor(cssName: "--swiftui-purple", color: .purple),
        SwiftUISystemColor(cssName: "--swiftui-red", color: .red),
        SwiftUISystemColor(cssName: "--swiftui-teal", color: .teal),
        SwiftUISystemColor(cssName: "--swiftui-yellow", color: .yellow),
    ]
}

@available(macOS 14.0, *)
@MainActor
func resolve(
    _ tokens: [SwiftUISystemColor],
    colorScheme: ColorScheme,
    contrast: ColorSchemeContrast,
) -> [ResolvedColor] {
    var environment = EnvironmentValues()
    environment.colorScheme = colorScheme
    environment._colorSchemeContrast = contrast
    return tokens.map { token in
        ResolvedColor(
            cssName: token.cssName,
            hex: colorHex(token.color.resolve(in: environment)),
            resolutionScope: token.resolutionScope,
        )
    }
}

@available(macOS 14.0, *)
private func colorHex(_ color: Color.Resolved) -> String {
    let components = [color.red, color.green, color.blue, color.opacity]
    return "#" + components.map(componentHex).joined()
}

private func componentHex(_ component: Float) -> String {
    String(format: "%02x", Int((min(max(component, 0), 1) * 255).rounded()))
}
