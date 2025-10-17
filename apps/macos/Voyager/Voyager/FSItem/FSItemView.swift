import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

public struct FSItemView: View {
    public let store: StoreOf<FSItemFeature>

    public init(store: StoreOf<FSItemFeature>) {
        self.store = store
    }

    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            HStack(spacing: 12) {
                Image(nsImage: icon(for: viewStore.url, isDirectory: viewStore.isDirectory))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewStore.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(viewStore.url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if viewStore.isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contextMenu { menu(for: viewStore) }
            .onTapGesture(count: 2) {
                viewStore.send(.openWithDefault)
            }
            .alert(
                "Operation failed",
                isPresented: viewStore.binding(get: { $0.lastError != nil }, send: .clearError)
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                if let message = viewStore.lastError?.message {
                    Text(message)
                }
            }
        }
    }

    private func menu(for viewStore: ViewStore<FSItemFeature.State, FSItemFeature.Action>) -> some View {
        Group {
            Button("Open") { viewStore.send(.openWithDefault) }
                .keyboardShortcut(.downArrow, modifiers: [.command])

            Button("Quick Look") { viewStore.send(.quickLookPreview) }
                .keyboardShortcut(.space, modifiers: [])

            let apps = openWithApplications(for: viewStore.url)
            if !apps.isEmpty {
                Menu("Open With") {
                    ForEach(apps) { app in
                        Button(app.name) {
                            if let bundleID = app.bundleID {
                                viewStore.send(.openWithApp(bundleID: bundleID))
                            } else {
                                viewStore.send(.openWithOther)
                            }
                        }
                    }
                }
            } else {
                Button("Open With…") { viewStore.send(.openWithOther) }
            }

            if !viewStore.isDirectory {
                Menu("Set Default App") {
                    let fileType = UTType(filenameExtension: viewStore.url.pathExtension)
                    ForEach(apps.compactMap(\OpenWithApplication.bundleEntry), id: \ .bundleID) { entry in
                        Button(entry.name) {
                            viewStore.send(.setDefaultApp(type: fileType, bundleID: entry.bundleID))
                        }
                    }
                    Button("Other…") { viewStore.send(.setDefaultAppWithOther) }
                }
            }
        }
    }

    private func icon(for url: URL, isDirectory: Bool) -> NSImage {
        if isDirectory {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct OpenWithApplication: Identifiable {
    let id: String
    let name: String
    let bundleID: String?

    var bundleEntry: (bundleID: String, name: String)? {
        bundleID.map { ($0, name) }
    }
}

private func openWithApplications(for url: URL) -> [OpenWithApplication] {
    guard let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: url) else {
        return [OpenWithApplication(id: "other", name: "Other…", bundleID: nil)]
    }

    var seen = Set<String>()
    var apps: [OpenWithApplication] = []
    for appURL in appURLs {
        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier,
              seen.insert(bundleID).inserted
        else { continue }
        let name = FileManager.default.displayName(atPath: appURL.path)
        apps.append(OpenWithApplication(id: bundleID, name: name, bundleID: bundleID))
    }
    apps.append(OpenWithApplication(id: "other", name: "Other…", bundleID: nil))
    return apps
}
