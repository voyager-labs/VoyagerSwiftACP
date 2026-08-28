import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerShared

struct GeneralSettingsView: View {
    let store: StoreOf<GeneralSettingsFeature>

    var body: some View {
        Form {
            Section {
                Toggle("Launch at startup", isOn: Binding(
                    get: { store.launchAtStartup },
                    set: { store.send(.toggleLaunchAtStartup($0)) },
                ))

                if let error = store.launchAtStartupError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Toggle("Alert before app quit", isOn: Binding(
                    get: { store.alertBeforeQuit },
                    set: { store.send(.toggleAlertBeforeQuit($0)) },
                ))
            }

            Section("Updates") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Automatically download and install updates", isOn: Binding(
                        get: { store.automaticUpdate },
                        set: { store.send(.toggleAutomaticUpdate($0)) },
                    ))

                    Divider()

                    HStack {
                        Text("Version: \(AppVersionInfo.displayText)")
                            .font(.body)

                        Spacer()

                        Button("Check for updates...") {
                            store.send(.checkForUpdates)
                        }
                    }
                }

                if let error = store.automaticUpdateError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("Workspace") {
                HStack {
                    Text("Initial page")
                    Spacer()
                    Menu {
                        ForEach(StartPageOption.allCases, id: \.id) { option in
                            Button(
                                action: {
                                    store.send(.selectStartPageOption(option))
                                },
                                label: {
                                    HStack {
                                        Image(systemName: option.iconName)
                                            .frame(width: 14, height: 14)
                                            .accessibilityHidden(true)
                                        Text(option.displayName(using: store.standardDirectories))
                                    }
                                },
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: store.selectedStartPageOption.iconName)
                                .frame(width: 14, height: 14)
                                .accessibilityHidden(true)
                            Text(store.selectedStartPageOption.displayName(using: store.standardDirectories))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(store.isSelectingDirectory)
                }

                if let error = store.startingDirectoryError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // SET-010 Default File Viewer
            Section("Default File Viewer") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(statusMessage)
                        .accessibilityIdentifier("defaultFileViewerStatusText")

                    Button(actionButtonTitle) {
                        store.send(actionButtonAction)
                    }
                    .disabled(isActionDisabled)
                    .accessibilityIdentifier("defaultFileViewerActionButton")

                    if let error = store.defaultFileViewerErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Text("A system restart may be required for changes to take effect.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("defaultFileViewerRestartHint")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            store.send(.defaultFileViewerSectionAppeared)
        }
    }
}

private extension GeneralSettingsView {
    /// contract default_file_viewer_contract.toml L85-89 정확 매핑
    var statusMessage: String {
        switch store.defaultFileViewerStatus {
        case .voyagerIsDefault:
            "Voyager is the default file viewer."
        case .finderIsDefault:
            "Finder is the default file viewer. Set Voyager as default?"
        case let .otherIsDefault(_, appDisplayName):
            "\(appDisplayName) is the default file viewer. Switch to Voyager?"
        case .unknown:
            "Could not determine the default file viewer status."
        }
    }

    var actionButtonTitle: String {
        switch store.defaultFileViewerStatus {
        case .voyagerIsDefault:
            "Restore Finder"
        case .finderIsDefault:
            "Set Voyager as Default"
        case .otherIsDefault:
            "Switch to Voyager"
        case .unknown:
            "Check Again"
        }
    }

    // G16: unknown → retry만
    var actionButtonAction: GeneralSettingsAction {
        switch store.defaultFileViewerStatus {
        case .voyagerIsDefault:
            .restoreDefaultFileViewerTapped
        case .finderIsDefault, .otherIsDefault:
            .setAsDefaultFileViewerTapped
        case .unknown:
            .defaultFileViewerDiagnoseRequested(.manual)
        }
    }

    // G4: 진행 중 비활성화
    var isActionDisabled: Bool {
        store.isDiagnosingDefaultFileViewer
            || store.isSettingDefaultFileViewer
            || store.isRestoringDefaultFileViewer
    }
}
