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

                    Text(
                        "Enable it manually in System Settings > Privacy & Security > Full Disk Access. "
                            + "Voyager cannot add itself or change this toggle.",
                    )
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
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Files & Folders")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Click Grant Access to request Desktop, Documents, and Downloads.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("macOS will show a permission prompt. Choose Allow to grant access.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Grant Access") {
                            viewStore.send(.requestFilesAndFoldersTapped)
                        }
                        .disabled(viewStore.isRequestingFilesAndFolders)

                        if viewStore.isRequestingFilesAndFolders {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let message = viewStore.filesAndFoldersMessage {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    if !viewStore.folderAccessItems.isEmpty {
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
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "Launch at Login",
                        isOn: viewStore.binding(
                            get: { $0.launchAtLoginEnabled },
                            send: { .launchAtLoginToggled($0) },
                        ),
                    )
                    Text("Optional. It does not affect onboarding completion.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

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
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewStore.showsIndexingPresetPreview {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Indexing Preset (OBT)")
                                .font(.system(size: 14, weight: .semibold))
                            Text(viewStore.indexingPresetStatusLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        Text("Indexing runs in the background and continues after onboarding.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        Text("You will not see a single \"indexing complete\" message.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text("This is a read-only summary of what will be included and excluded.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                viewStore.send(.onAppear)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                viewStore.send(.appDidBecomeActive)
            }
        }
    }
}
