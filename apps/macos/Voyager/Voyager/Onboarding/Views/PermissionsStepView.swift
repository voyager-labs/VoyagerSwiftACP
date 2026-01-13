import AppKit
import ComposableArchitecture
import SwiftUI

struct PermissionsStepView: View {
    let store: StoreOf<PermissionsFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            let statusColor: Color = viewStore.fullDiskAccessStatus == .granted ? .green : .secondary

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Full Disk Access")
                            .font(.system(size: 14, weight: .semibold))
                        Text(viewStore.fullDiskAccessStatus.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(statusColor)
                        Spacer()
                    }

                    Text(viewStore.fullDiskAccessStatusMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Text("Go to System Settings > Privacy & Security > Full Disk Access.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if viewStore.showsFullDiskAccessAction {
                        Button("Open System Settings") {
                            viewStore.send(.openSystemSettingsTapped)
                        }
                    }

                    if let error = viewStore.systemSettingsError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Files & Folders")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Let Voyager access Desktop, Documents, and Downloads.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("macOS will ask. Choose Allow.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button(viewStore.filesAndFoldersStatus == .granted ? "Done" : "Grant Access") {
                            viewStore.send(.requestFilesAndFoldersTapped)
                        }
                        .disabled(
                            viewStore.isRequestingFilesAndFolders || viewStore.filesAndFoldersStatus == .granted
                        )

                        if viewStore.isRequestingFilesAndFolders {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Text(viewStore.filesAndFoldersMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if !viewStore.folderAccessItems.isEmpty,
                       viewStore.filesAndFoldersStatus != .granted
                    {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewStore.folderAccessItems) { item in
                                HStack {
                                    Text(item.title)
                                        .font(.system(size: 13))
                                    Spacer()
                                    Text(item.status.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Launch at Login")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Toggle(
                            "",
                            isOn: viewStore.binding(
                                get: { $0.launchAtLoginEnabled },
                                send: { .launchAtLoginToggled($0) },
                            ),
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    if let error = viewStore.launchAtLoginError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                        Text("System Settings > Login Items")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                viewStore.send(.onAppear)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                viewStore.send(.appDidBecomeActive)
            }
        }
    }
}
