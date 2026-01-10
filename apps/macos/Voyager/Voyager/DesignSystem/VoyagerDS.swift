import AppKit
import SwiftUI

enum VoyagerDS {
    enum BrandPrimaryColor {
        static let c900 = Color(hex: 0x754006)
        static let c800 = Color(hex: 0xA55A09)
        static let c700 = Color(hex: 0xBD670A)
        static let c600 = Color(hex: 0xED810D)
        static let c500 = Color(hex: 0xF79A30)
        static let c400 = Color(hex: 0xF6A954)
        static let c300 = Color(hex: 0xF8BA78)
        static let c200 = Color(hex: 0xFACE9A)
        static let c100 = Color(hex: 0xFDF0E1)
    }

    enum BrandSecondaryColor {
        static let c900 = Color(hex: 0x4C3C10)
        static let c800 = Color(hex: 0x745E1C)
        static let c700 = Color(hex: 0x9D7F24)
        static let c600 = Color(hex: 0xC7A12E)
        static let c500 = Color(hex: 0xD7B652) // 포인트 컬러(기존 UI에서 사용)
        static let c400 = Color(hex: 0xE0C77B)
        static let c300 = Color(hex: 0xEAD8A4)
        static let c200 = Color(hex: 0xF3EACD)
        static let c100 = Color(hex: 0xF9F4E6)
    }

    enum SystemColor {
        static let label = Color(nsColor: .labelColor)
        static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
        static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
        static let quaternaryLabel = Color(nsColor: .quaternaryLabelColor)
        static let quinaryLabel = Color(nsColor: .quinaryLabel)

        static let separator = Color(nsColor: .separatorColor)

        static let windowBackground = Color(nsColor: .windowBackgroundColor)
        static let controlBackground = Color(nsColor: .controlBackgroundColor)
        static let underPageBackground = Color(nsColor: .underPageBackgroundColor)
    }

    enum Radius {
        static let overlayCard: CGFloat = 12
        static let composer: CGFloat = 18
        static let contentPane: CGFloat = 23
        static let control: CGFloat = 8
        static let chipContainer: CGFloat = 6
        static let chipItem: CGFloat = 4
        static let toolbarButton: CGFloat = 5
    }

    enum Spacing {
        // MARK: - Composer

        static let composerHorizontalPadding: CGFloat = 7
        static let composerTopPadding: CGFloat = 5
    }

    enum Typography {
        static let title = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 12)
        static let chip = Font.system(size: 11, weight: .medium)
        static let smallButton = Font.system(size: 10, weight: .medium)
    }

    enum Shadow {
        static func overlayColor(for scheme: ColorScheme) -> Color {
            Color.black.opacity(scheme == .dark ? 0.4 : 0.15)
        }

        static func overlayRadius(for scheme: ColorScheme) -> CGFloat {
            scheme == .dark ? 24 : 16
        }

        static func overlayYOffset(for scheme: ColorScheme) -> CGFloat {
            scheme == .dark ? 12 : 8
        }

        static func popoverColor(for scheme: ColorScheme) -> Color {
            Color.black.opacity(scheme == .dark ? 0.4 : 0.15)
        }

        static let popoverRadius: CGFloat = 8
        static let popoverYOffset: CGFloat = 4
    }

    enum Surface {
        static func overlayBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? SystemColor.underPageBackground : SystemColor.windowBackground
        }

        static let overlayBorder = SystemColor.separator

        // MARK: - Composer (피그마: Materials + Stroke 검정 50%)

        static let composerBorder = Color.black.opacity(0.5)

        static func popoverBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? SystemColor.underPageBackground : SystemColor.windowBackground
        }

        static let popoverBorder = SystemColor.separator

        static func inputBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        }

        static func inputBorder(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
        }

        static func chipContainerBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
        }

        static func chipItemBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
        }

        static func chipItemBorder(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15)
        }

        static func toolbarMenuButtonBackground(for scheme: ColorScheme) -> Color {
            if scheme == .dark {
                return SystemColor.controlBackground
            }
            // 기존 UI 톤을 유지하기 위한 값(추후 semantic token으로 재매핑 예정)
            return Color(red: 245 / 255.0, green: 245 / 255.0, blue: 245 / 255.0)
        }

        static func popoverSearchFieldBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
        }

        // MARK: - Shell (Toolbar / Sidebar / SplitView)

        static func shellBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? SystemColor.controlBackground
                : Color(hex: 0xF5F5F5)
        }

        static func toolbarBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x2B2B2B)
                : SystemColor.controlBackground
        }

        static func contentPaneBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x292929)
                : SystemColor.controlBackground
        }

        static func inspectorPaneBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? SystemColor.controlBackground
                : Color(hex: 0xF5F5F5)
        }

        static let toolbarDivider = Color.black.opacity(0.15)

        // MARK: - Status Button / Folder Chip

        static func statusButtonBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x373430)
                : Color(hex: 0xFBFBFB)
        }

        static func statusButtonBorder(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x4D4943)
                : Color.black.opacity(0.06)
        }

        static func statusButtonText(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0xDAD7D2)
                : Color(hex: 0x323232)
        }

        // MARK: - Chat Input

        static func chatInputBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x2C2B28)
                : SystemColor.controlBackground
        }
    }

    enum Interaction {
        static func hoverFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }

        static func controlHoverFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
        }

        static func toolbarButtonHoverFill(for scheme: ColorScheme) -> Color {
            controlHoverFill(for: scheme)
        }
    }

    // MARK: - AppKit (NSColor) 토큰

    /// AppKit 레이어에서 사용하는 NSColor 기반 토큰
    /// NSAppearance.performAsCurrentDrawingAppearance 블록 내에서 사용
    enum AppKitSurface {
        static func shellBackground(isDark: Bool) -> NSColor {
            isDark
                ? .controlBackgroundColor
                : NSColor(hex: 0xF5F5F5)
        }

        static func toolbarBackground(isDark: Bool) -> NSColor {
            isDark
                ? NSColor(hex: 0x2B2B2B)
                : .controlBackgroundColor
        }

        static func contentPaneBackground(isDark: Bool) -> NSColor {
            isDark
                ? NSColor(hex: 0x292929)
                : .controlBackgroundColor
        }

        static func inspectorPaneBackground(isDark: Bool) -> NSColor {
            isDark
                ? .controlBackgroundColor
                : NSColor(hex: 0xF5F5F5)
        }

        // MARK: - Content Pane Overlay (피그마: Materials/Ultrathick 근사치)

        /// Content pane 배경 오버레이 (블러 위에 반투명 레이어)
        static func contentPaneOverlay(isDark: Bool) -> NSColor {
            if isDark {
                NSColor(white: 0.1, alpha: 0.75)
            } else {
                NSColor(white: 0.95, alpha: 0.85)
            }
        }
    }

    // MARK: - Material 참조 (문서화용)

    // 피그마 Materials → AppKit NSVisualEffectView.Material 매핑:
    // - thin-dark → .hudWindow (가장 유사)
    // - ultrathick → 직접 매핑 없음, 반투명 색상으로 대체
}
