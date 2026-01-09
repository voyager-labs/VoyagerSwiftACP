import AppKit
import SwiftUI

enum VoyagerDS {
    // Figma_DesignSystem/Color.png 기반 (Primary/Secondary scale)
    // SwiftLint(nesting) 규칙 때문에 1단계 중첩까지만 사용합니다.
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
        static let control: CGFloat = 8
        static let chipContainer: CGFloat = 6
        static let chipItem: CGFloat = 4
        static let toolbarButton: CGFloat = 5
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
    }

    enum Interaction {
        static func hoverFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }

        static func controlHoverFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
        }
    }
}
