import AppKit
import ComposableArchitecture
import SwiftUI

struct GeneralSettingsView: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Startup", isOn: Binding(
                    get: { store.generalSettings.launchAtStartup },
                    set: { store.send(.general(.toggleLaunchAtStartup($0))) }
                ))

                if let error = store.generalSettings.launchAtStartupError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section {
                HStack {
                    Text("Starting Directory")
                    Spacer()
                    Menu {
                        let selected = store.generalSettings.selectedDirectoryOption
                        let standardOptions = DirectoryOption.standardOptions

                        if standardOptions.contains(selected) {
                            Button(
                                action: {
                                    store.send(.general(.selectDirectoryOption(selected)))
                                },
                                label: {
                                    HStack {
                                        selected.icon
                                            .frame(width: 14, height: 14)
                                        Text("\(selected.displayName) (default)")
                                    }
                                }
                            )

                            Divider()
                        }

                        if case .custom = selected,
                           !standardOptions.contains(selected)
                        {
                            Button(
                                action: {
                                    store.send(.general(.selectDirectoryOption(selected)))
                                },
                                label: {
                                    HStack {
                                        selected.icon
                                            .frame(width: 14, height: 14)
                                        Text("\(selected.displayName) (default)")
                                    }
                                }
                            )

                            Divider()
                        }

                        ForEach(standardOptions.filter { $0 != selected }, id: \.id) { option in
                            Button(
                                action: {
                                    store.send(.general(.selectDirectoryOption(option)))
                                },
                                label: {
                                    HStack {
                                        option.icon
                                            .frame(width: 14, height: 14)
                                        Text(option.displayName)
                                    }
                                }
                            )
                        }

                        Divider()

                        Button("Other…") {
                            store.send(.general(.selectDirectoryOption(.other)))
                        }
                    } label: {
                        HStack(spacing: 4) {
                            store.generalSettings.selectedDirectoryOption.icon
                                .frame(width: 14, height: 14)
                            Text(store.generalSettings.selectedDirectoryOption.displayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(store.generalSettings.isSelectingDirectory)
                }

                if let error = store.generalSettings.startingDirectoryError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
