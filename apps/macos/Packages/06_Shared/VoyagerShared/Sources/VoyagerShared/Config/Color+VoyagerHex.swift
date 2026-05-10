import AppKit
import SwiftUI

public extension Color {
    /// 브랜드 팔레트(Primary/Secondary)처럼 "고정 색상"이 필요한 경우에만 사용합니다.
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

public extension NSColor {
    /// 브랜드 팔레트(Primary/Secondary)처럼 "고정 색상"이 필요한 경우에만 사용합니다.
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
