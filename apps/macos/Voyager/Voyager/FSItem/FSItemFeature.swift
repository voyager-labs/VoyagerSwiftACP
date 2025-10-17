import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@Reducer
public struct FSItemFeature {
    @ObservableState
    public struct State: Equatable, Identifiable, Sendable {
        public var id: UUID
        public var url: URL
        public var displayName: String
        public var isDirectory: Bool
        public var isBusy: Bool
        public var lastError: FileOpError?

        public init(
            id: UUID,
            url: URL,
            displayName: String,
            isDirectory: Bool,
            isBusy: Bool = false,
            lastError: FileOpError? = nil
        ) {
            self.id = id
            self.url = url
            self.displayName = displayName
            self.isDirectory = isDirectory
            self.isBusy = isBusy
            self.lastError = lastError
        }
    }

    public enum Action: Sendable {
        case openWithDefault
        case openWithApp(bundleID: String)
        case openWithOther
        case setDefaultApp(type: UTType?, bundleID: String)
        case setDefaultAppWithOther
        case quickLookPreview
        case operationStarted(OperationKind)
        case operationFinished(OperationKind, Result<Void, FileOpError>)
        case clearError
    }

    @Dependency(\.fileSystemCapabilities) var capabilities
    @Dependency(\.fileSystemClient) var fileSystem

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .clearError:
                state.lastError = nil
                return .none

            case .operationStarted:
                state.isBusy = true
                state.lastError = nil
                return .none

            case let .operationFinished(_, result):
                state.isBusy = false
                switch result {
                case .success:
                    return .none
                case let .failure(error):
                    state.lastError = error
                    return .none
                }

            case .openWithDefault:
                guard !state.isDirectory else {
                    state.lastError = .unsupportedType
                    return .none
                }
                let url = state.url
                return run(state: &state, kind: .openDefault) {
                    try await fileSystem.open(url, .defaultApp)
                }

            case let .openWithApp(bundleID):
                guard !state.isDirectory else {
                    state.lastError = .unsupportedType
                    return .none
                }
                let url = state.url
                return run(state: &state, kind: .openWithApp(bundleID)) {
                    try await fileSystem.open(url, .bundleID(bundleID))
                }

            case .openWithOther:
                let url = state.url
                return .run { send in
                    guard let bundleID = await MainActor.run({ selectApplication(for: url)?.bundleID }) else { return }
                    await send(.openWithApp(bundleID: bundleID))
                }

            case let .setDefaultApp(type, bundleID):
                guard !state.isDirectory else {
                    state.lastError = .unsupportedType
                    return .none
                }
                guard capabilities.supportsDefaultAppManagement else {
                    state.lastError = .system(
                        message: "Setting default apps is not supported yet.",
                        suggestion: "Enable default-app capability before using this action."
                    )
                    return .none
                }
                guard let resolvedType = type ?? UTType(filenameExtension: state.url.pathExtension) else {
                    state.lastError = .unsupportedType
                    return .none
                }
                return run(state: &state, kind: .setDefaultApp(bundleID)) {
                    try await fileSystem.setDefaultApp(resolvedType, bundleID)
                }

            case .setDefaultAppWithOther:
                guard capabilities.supportsDefaultAppManagement else {
                    state.lastError = .system(
                        message: "Setting default apps is not supported yet.",
                        suggestion: "Enable default-app capability before using this action."
                    )
                    return .none
                }
                let url = state.url
                return .run { send in
                    guard let selection = await MainActor.run({ selectApplication(for: url) }) else { return }
                    await send(.setDefaultApp(type: selection.type, bundleID: selection.bundleID))
                }

            case .quickLookPreview:
                let url = state.url
                return run(state: &state, kind: .quickLook) {
                    try await fileSystem.quickLook(url)
                }
            }
        }
    }

    private func run(
        state: inout State,
        kind: OperationKind,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Effect<Action> {
        state.isBusy = true
        return .run { send in
            await send(.operationStarted(kind))
            do {
                try await operation()
                await send(.operationFinished(kind, .success(())))
            } catch {
                await send(.operationFinished(kind, .failure(error.fileOpError)))
            }
        }
    }
}

private struct ApplicationSelection {
    let bundleID: String
    let type: UTType?
}

@MainActor
private func selectApplication(for itemURL: URL) -> ApplicationSelection? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    if #available(macOS 13.0, *) {
        panel.allowedContentTypes = [.application]
    } else {
        panel.allowedFileTypes = ["app"]
    }
    panel.prompt = "Choose"
    panel.message = "Select an application for \(itemURL.lastPathComponent)."

    guard panel.runModal() == .OK, let appURL = panel.url, let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
        return nil
    }

    let type = UTType(filenameExtension: itemURL.pathExtension)
    return ApplicationSelection(bundleID: bundleID, type: type)
}

public enum OperationKind: Equatable, Hashable, Sendable {
    case openDefault
    case openWithApp(String)
    case setDefaultApp(String)
    case quickLook
}

extension Error {
    var fileOpError: FileOpError {
        if let error = self as? FileOpError { return error }
        if let nsError = self as NSError?, nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return .notFound
            case NSUserCancelledError:
                return .cancelled
            default:
                return .system(message: nsError.localizedDescription)
            }
        }
        return .system(message: localizedDescription)
    }
}
