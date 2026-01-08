import ComposableArchitecture
import Foundation
import SwiftUI

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

            Section {
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
                            AppDelegate.shared?.checkForUpdates()
                        }
                    }
                }

                if let error = store.automaticUpdateError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section {
                HStack {
                    Text("Starting directory")
                    Spacer()
                    Menu {
                        let selected = store.selectedDirectoryOption
                        let standardOptions = DirectoryOption.standardOptions

                        if standardOptions.contains(selected) {
                            Button(
                                action: {
                                    store.send(.selectDirectoryOption(selected))
                                },
                                label: {
                                    HStack {
                                        selected.icon
                                            .frame(width: 14, height: 14)
                                        Text("\(selected.displayName) (default)")
                                    }
                                },
                            )

                            Divider()
                        }

                        if case .custom = selected,
                           !standardOptions.contains(selected)
                        {
                            Button(
                                action: {
                                    store.send(.selectDirectoryOption(selected))
                                },
                                label: {
                                    HStack {
                                        selected.icon
                                            .frame(width: 14, height: 14)
                                        Text("\(selected.displayName) (default)")
                                    }
                                },
                            )

                            Divider()
                        }

                        ForEach(standardOptions.filter { $0 != selected }, id: \.id) { option in
                            Button(
                                action: {
                                    store.send(.selectDirectoryOption(option))
                                },
                                label: {
                                    HStack {
                                        option.icon
                                            .frame(width: 14, height: 14)
                                        Text(option.displayName)
                                    }
                                },
                            )
                        }

                        Divider()

                        Button("Other…") {
                            store.send(.selectDirectoryOption(.other))
                        }
                    } label: {
                        HStack(spacing: 4) {
                            store.selectedDirectoryOption.icon
                                .frame(width: 14, height: 14)
                            Text(store.selectedDirectoryOption.displayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            store.send(.loadSettings)
        }
    }
}
