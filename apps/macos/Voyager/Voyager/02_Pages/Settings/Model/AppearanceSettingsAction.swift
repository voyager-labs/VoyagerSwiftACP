import ComposableArchitecture
import CoreGraphics

@CasePathable
enum AppearanceSettingsAction: CasePathable, Sendable {
    case loadSettings
    case setTheme(AppTheme)
    case setListIconSize(CGFloat)
    case setGridIconSize(CGFloat)
    case setListTextSize(CGFloat)
    case setGridTextSize(CGFloat)
    case setShowHiddenFiles(Bool)
}
