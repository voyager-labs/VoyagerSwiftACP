import AppKit
import ComposableArchitecture
import SwiftUI

struct WelcomeStepView: View {
    let store: StoreOf<WelcomeFeature>
    var isCentered: Bool = false

    var body: some View {
        WithViewStore(store, observe: { $0 }) { _ in
            VStack(alignment: isCentered ? .center : .leading, spacing: 12) {
                Text("Voyager runs a four-step setup. You can move forward only after each step is complete.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)
                Text("Your files stay on your Mac; nothing is uploaded during onboarding.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)
                Text("If you quit and reopen Voyager, it resumes at the last saved step.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)
            }
            .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
        }
    }
}

struct BetaAccessStepView: View {
    let store: StoreOf<BetaAccessFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "email@example.com",
                            text: viewStore.binding(
                                get: \.email,
                                send: { .emailChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Token")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        SecureField(
                            "Paste your token here",
                            text: viewStore.binding(
                                get: \.token,
                                send: { .tokenChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enter the email and token from your invite.")
                        Text("Click Check to verify with the server. Until verification succeeds, Next stays disabled.")
                        Text("Verification can fail due to input errors, expired tokens, or network/server issues.")
                        Text("If it fails, correct the input and Retry/Check.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewStore.statusTitle)
                        .font(.system(size: 14, weight: .semibold))
                    if let message = viewStore.statusMessage {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewStore.isVerifying {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
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

struct CompleteStepView: View {
    let store: StoreOf<CompleteFeature>
    var isCentered: Bool = false

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: isCentered ? .center : .leading, spacing: 12) {
                Text("Setup is finished and Voyager is ready to use.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)
                Text("Click Start using Voyager to open your first file manager window.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)

                if viewStore.isOpeningWindow {
                    ProgressView()
                        .controlSize(.small)
                }

                if let error = viewStore.openWindowError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                    Button("Retry") {
                        viewStore.send(.retryTapped)
                    }
                } else {
                    Text("If it fails, you'll see Retry to try again.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(isCentered ? .center : .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
        }
    }
}
