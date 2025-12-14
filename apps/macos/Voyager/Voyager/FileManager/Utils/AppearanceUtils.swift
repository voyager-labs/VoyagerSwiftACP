import AppKit

func isDarkMode() -> Bool {
    let appearance = NSApp.effectiveAppearance
    return appearance.name == .darkAqua || appearance.name == .vibrantDark
}
