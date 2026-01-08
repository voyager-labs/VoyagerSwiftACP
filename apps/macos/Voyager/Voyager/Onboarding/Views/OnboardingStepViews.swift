import AppKit
import ComposableArchitecture
import SwiftUI

struct WelcomeStepView: View {
    let store: StoreOf<WelcomeFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { _ in
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome")
                    .font(.system(size: 20, weight: .semibold))
                Text("Let's get Voyager ready for your first run.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BetaAccessStepView: View {
    let store: StoreOf<BetaAccessFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                Text("Beta Access")
                    .font(.system(size: 20, weight: .semibold))

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "email@example.com",
                            text: viewStore.binding(
                                get: \.email,
                                send: { .emailChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Token")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        SecureField(
                            "Paste your token here",
                            text: viewStore.binding(
                                get: \.token,
                                send: { .tokenChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    Text("Enter the email and token from your invitation email.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewStore.statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                    if let message = viewStore.statusMessage {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(8)

                HStack(spacing: 8) {
                    Button(viewStore.showsRetry ? "Retry" : "Check") {
                        viewStore.send(viewStore.showsRetry ? .retryTapped : .checkTapped)
                    }
                    .disabled(!viewStore.canSubmit)

                    if viewStore.isVerifying {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }
}

struct PermissionsStepView: View {
    let store: StoreOf<PermissionsFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            let statusColor: Color = viewStore.fullDiskAccessStatus == .granted ? .green : .secondary

            VStack(alignment: .leading, spacing: 16) {
                Text("Permissions")
                    .font(.system(size: 20, weight: .semibold))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Full Disk Access")
                            .font(.system(size: 13, weight: .semibold))
                        Text(viewStore.fullDiskAccessStatus.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(statusColor)
                        Spacer()
                    }

                    Text(viewStore.fullDiskAccessStatusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if viewStore.showsFullDiskAccessAction {
                        Button("Open System Settings") {
                            viewStore.send(.openSystemSettingsTapped)
                        }
                    }

                    Text("System Settings > Privacy & Security > Full Disk Access")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let error = viewStore.systemSettingsError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Files & Folders")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Allow access to Desktop, Documents, and Downloads.")
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
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if !viewStore.folderAccessItems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewStore.folderAccessItems) { item in
                                HStack {
                                    Text(item.title)
                                        .font(.system(size: 12))
                                    Spacer()
                                    Text(item.status.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "Launch at Login",
                        isOn: viewStore.binding(
                            get: { $0.launchAtLoginEnabled },
                            send: { .launchAtLoginToggled($0) },
                        ),
                    )
                    Text("Start Voyager automatically when you log in.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if let error = viewStore.launchAtLoginError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("System Settings > Login Items")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Indexing is running in the background from `/`.")
                        .font(.system(size: 12))
                    Text(
                        "Indexing runs via the backend binary launched by VoyagerHelper. "
                            + "Full Disk Access can't be delegated by Voyager.",
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                if viewStore.showsIndexingPresetPreview {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Indexing Preset (OBT)")
                                .font(.system(size: 13, weight: .semibold))
                            Text(viewStore.indexingPresetStatusLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        Text("Editing will be available later (OBT).")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Included Paths")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(["~/", "/Applications"], id: \.self) { path in
                                Text("• \(path)")
                                    .font(.system(size: 11))
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Excluded Paths")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(["~/Library", "/System"], id: \.self) { path in
                                Text("• \(path)")
                                    .font(.system(size: 11))
                            }
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
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

struct CompleteStepView: View {
    let store: StoreOf<CompleteFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                Text("Complete")
                    .font(.system(size: 20, weight: .semibold))
                Text("You're all set. We'll open a file manager window next.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Start using Voyager") {
                        viewStore.send(.startUsingTapped)
                    }
                    .disabled(viewStore.isOpeningWindow)

                    if viewStore.isOpeningWindow {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let error = viewStore.openWindowError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    Button("Retry") {
                        viewStore.send(.retryTapped)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
