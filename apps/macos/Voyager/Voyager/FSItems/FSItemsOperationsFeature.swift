import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

/// FSItems의 파일 시스템 작업 관리
@Reducer
struct FSItemsOperationsFeature {
    @ObservableState
    struct State: Equatable {
        var isOperationBusy: Bool = false
        var lastOperationError: FileOpError?
    }

    enum Action: Sendable {
        case openFiles(files: [FSItem])
        case quickLookFile(file: FSItem)
        case openFileWithApp(file: FSItem)
        case clearOperationError
        case operationStarted(OperationKind)
        case operationFinished(OperationKind, Result<Void, FileOpError>)
    }

    @Dependency(\.fileSystemClient)
    var fileSystemClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .clearOperationError:
                state.lastOperationError = nil
                return .none

            case .operationStarted:
                state.isOperationBusy = true
                state.lastOperationError = nil
                return .none

            case let .operationFinished(_, result):
                state.isOperationBusy = false
                switch result {
                case .success:
                    return .none
                case let .failure(error):
                    state.lastOperationError = error
                    return .none
                }

            case let .openFiles(files):
                guard !files.isEmpty else {
                    return .none
                }

                let filesToOpen = files
                return run(kind: .openDefault) {
                    for file in filesToOpen {
                        let url = URL(fileURLWithPath: file.fullPath)
                        try await fileSystemClient.open(url, .defaultApp)
                    }
                }

            case let .quickLookFile(file):
                let url = URL(fileURLWithPath: file.fullPath)
                return run(kind: .quickLook) {
                    try await fileSystemClient.quickLook(url)
                }

            case let .openFileWithApp(file):
                let url = URL(fileURLWithPath: file.fullPath)
                return run(kind: .openWithApp) {
                    if let bundleID = await selectApplication(for: url)?.bundleID {
                        try await fileSystemClient.open(url, .bundleID(bundleID))
                    }
                }
            }
        }
    }

    private func run(
        kind: OperationKind,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Effect<Action> {
        .run { send in
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

enum OperationKind: Equatable, Hashable, Sendable {
    case openDefault
    case openWithApp
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
