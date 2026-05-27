import Foundation
import VoyagerEntitiesAppPreferences

final class ThemeApplyRecorder: @unchecked Sendable {
    private let recorder = MutationRecorder<AppTheme>()

    func record(_ theme: AppTheme) {
        recorder.record(theme)
    }

    var values: [AppTheme] {
        recorder.values
    }
}
