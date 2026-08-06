import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess
import VoyagerPagesSettings

extension SettingsState {
    static func hostPreset(for scenario: SettingsHostScenario) -> SettingsState {
        let hasAccountSession = scenario.sessionExpiresAt != nil
        let accessStatus: AccessStatus = switch scenario.accountAuth {
        case .signedIn:
            .coreLicenseActive
        case .authExpired:
            .trialExpired
        case .signedOut, .loading, .error:
            .none
        }

        return SettingsState(
            accessStatus: accessStatus,
            accountPresentation: AccountAccessPresentation(
                hasAccountSession: hasAccountSession,
            ),
            appearanceTheme: scenario.persistence == .populated ? .dark : nil,
        )
    }
}
