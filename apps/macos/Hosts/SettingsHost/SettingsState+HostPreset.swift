import VoyagerEntitiesAppPreferences
import VoyagerPagesSettings

extension SettingsState {
    static func hostPreset(for scenario: SettingsHostScenario) -> SettingsState {
        let hasAccountSession = scenario.sessionExpiresAt != nil
        return SettingsState(
            accountPresentation: AccountAccessPresentation(
                hasAccountSession: hasAccountSession,
            ),
            appearanceTheme: scenario.persistence == .populated ? .dark : nil,
        )
    }
}
