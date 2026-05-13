import AppKit
import SwiftUI

public enum VoyagerDS {
    public enum BrandPrimaryColor {
        public static let c900 = Color(hex: 0x754006)
        public static let c800 = Color(hex: 0xA55A09)
        public static let c700 = Color(hex: 0xBD670A)
        public static let c600 = Color(hex: 0xED810D)
        public static let c500 = Color(hex: 0xF79A30)
        public static let c400 = Color(hex: 0xF6A954)
        public static let c300 = Color(hex: 0xF8BA78)
        public static let c200 = Color(hex: 0xFACE9A)
        public static let c100 = Color(hex: 0xFDF0E1)
    }

    public enum BrandSecondaryColor {
        public static let c900 = Color(hex: 0x4C3C10)
        public static let c800 = Color(hex: 0x745E1C)
        public static let c700 = Color(hex: 0x9D7F24)
        public static let c600 = Color(hex: 0xC7A12E)
        public static let c500 = Color(hex: 0xD7B652) // 포인트 컬러(기존 UI에서 사용)
        public static let c400 = Color(hex: 0xE0C77B)
        public static let c300 = Color(hex: 0xEAD8A4)
        public static let c200 = Color(hex: 0xF3EACD)
        public static let c100 = Color(hex: 0xF9F4E6)
    }

    public enum SystemColor {
        public static let label = Color(nsColor: .labelColor)
        public static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
        public static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
        public static let quaternaryLabel = Color(nsColor: .quaternaryLabelColor)
        public static let quinaryLabel = Color(nsColor: .quinaryLabel)

        public static let separator = Color(nsColor: .separatorColor)

        public static let windowBackground = Color(nsColor: .windowBackgroundColor)
        public static let controlBackground = Color(nsColor: .controlBackgroundColor)
        public static let underPageBackground = Color(nsColor: .underPageBackgroundColor)
    }

    public enum Radius {
        public static let overlayCard: CGFloat = 12
        public static let control: CGFloat = 8
        public static let chipContainer: CGFloat = 6
        public static let chipItem: CGFloat = 4
        public static let toolbarButton: CGFloat = 5
        public static var composer: CGFloat {
            if #available(macOS 26.0, *) {
                return 16
            }
            return 10
        }

        public static var contentPane: CGFloat {
            if #available(macOS 26.0, *) {
                return 16
            }
            return 6
        }
    }

    public enum Spacing {
        // MARK: - Composer

        public static let composerHorizontalPadding: CGFloat = 7
        public static let composerTopPadding: CGFloat = 5
    }

    public enum Typography {
        public static let title = Font.system(size: 15, weight: .semibold)
        public static let body = Font.system(size: 13)
        public static let caption = Font.system(size: 12)
        public static let chip = Font.system(size: 11, weight: .medium)
        public static let smallButton = Font.system(size: 10, weight: .medium)
    }

    public enum Shadow {
        public static let popoverRadius: CGFloat = 8
        public static let popoverYOffset: CGFloat = 4
        public static func overlayColor(for scheme: ColorScheme) -> Color {
            Color.black.opacity(scheme == .dark ? 0.4 : 0.15)
        }

        public static func overlayRadius(for scheme: ColorScheme) -> CGFloat {
            scheme == .dark ? 24 : 16
        }

        public static func overlayYOffset(for scheme: ColorScheme) -> CGFloat {
            scheme == .dark ? 12 : 8
        }

        public static func popoverColor(for scheme: ColorScheme) -> Color {
            Color.black.opacity(scheme == .dark ? 0.4 : 0.15)
        }
    }

    public enum Surface {
        public static let overlayBorder = SystemColor.separator

        // MARK: - Composer (피그마: Materials + Stroke 검정 50%)

        public static let composerBorder = Color.black.opacity(0.5)

        public static let popoverBorder = SystemColor.separator

        public static let toolbarDivider = Color.black.opacity(0.15)

        public static func overlayBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? SystemColor.underPageBackground : SystemColor.windowBackground
        }

        public static func popoverBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? SystemColor.underPageBackground : SystemColor.windowBackground
        }

        public static func inputBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        }

        public static func inputBorder(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
        }

        public static func chipContainerBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
        }

        public static func chipItemBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
        }

        public static func chipItemBorder(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15)
        }

        public static func toolbarMenuButtonBackground(for scheme: ColorScheme) -> Color {
            if scheme == .dark {
                return SystemColor.controlBackground
            }
            // 기존 UI 톤을 유지하기 위한 값(추후 semantic token으로 재매핑 예정)
            return Color(red: 245 / 255.0, green: 245 / 255.0, blue: 245 / 255.0)
        }

        public static func popoverSearchFieldBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
        }

        // MARK: - Shell (Toolbar / Sidebar / SplitView)

        public static func shellBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? SystemColor.controlBackground
                : Color(hex: 0xF5F5F5)
        }

        public static func toolbarBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x2B2B2B)
                : SystemColor.controlBackground
        }

        public static func contentPaneBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x292929)
                : SystemColor.controlBackground
        }

        public static func inspectorPaneBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? SystemColor.controlBackground
                : Color(hex: 0xF5F5F5)
        }

        public static func sidebarSelectionBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.12)
        }

        // MARK: - Status Button / Folder Chip

        public static func statusButtonBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x373430)
                : Color(hex: 0xFBFBFB)
        }

        public static func statusButtonBorder(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x4D4943)
                : Color.black.opacity(0.06)
        }

        public static func statusButtonText(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0xDAD7D2)
                : Color(hex: 0x323232)
        }

        // MARK: - Chat Input

        public static func chatInputBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(hex: 0x2C2B28)
                : SystemColor.controlBackground
        }
    }

    public enum Interaction {
        public static func hoverFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }

        public static func controlHoverFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
        }

        public static func toolbarButtonHoverFill(for scheme: ColorScheme) -> Color {
            controlHoverFill(for: scheme)
        }

        public static func toolbarTitleHoverFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.08)
        }

        public static func composerBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(white: 0.12) : Color(white: 0.94)
        }
    }

    // MARK: - AppKit (NSColor) 토큰

    /// AppKit 레이어에서 사용하는 NSColor 기반 토큰
    /// NSAppearance.performAsCurrentDrawingAppearance 블록 내에서 사용
    public enum AppKitSurface {
        public static func shellBackground(isDark: Bool) -> NSColor {
            isDark
                ? .controlBackgroundColor
                : NSColor(hex: 0xF5F5F5)
        }

        public static func toolbarBackground(isDark: Bool) -> NSColor {
            isDark
                ? NSColor(hex: 0x2B2B2B)
                : .controlBackgroundColor
        }

        public static func contentPaneBackground(isDark: Bool) -> NSColor {
            isDark
                ? NSColor(hex: 0x292929)
                : .controlBackgroundColor
        }

        public static func inspectorPaneBackground(isDark: Bool) -> NSColor {
            isDark
                ? .controlBackgroundColor
                : NSColor(hex: 0xF5F5F5)
        }

        // MARK: - Content Pane Overlay (피그마: Materials/Ultrathick 근사치)

        /// Content pane 배경 오버레이 (블러 위에 반투명 레이어)
        public static func contentPaneOverlay(isDark: Bool) -> NSColor {
            if isDark {
                NSColor(white: 0.2, alpha: 0.75)
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
