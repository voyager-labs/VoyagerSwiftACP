import ComposableArchitecture
import Foundation

struct FileManagerComputerNameClient: Sendable {
    var computerName: @Sendable () -> String
    var displayNameAtPath: @Sendable (String) -> String

    nonisolated init(
        computerName: @escaping @Sendable () -> String,
        displayNameAtPath: @escaping @Sendable (String) -> String,
    ) {
        self.computerName = computerName
        self.displayNameAtPath = displayNameAtPath
    }
}

extension FileManagerComputerNameClient: DependencyKey {
    nonisolated static var liveValue: FileManagerComputerNameClient {
        nonisolated(unsafe) let fileManager = FileManager.default
        return FileManagerComputerNameClient(
            computerName: {
                fileManager.displayName(atPath: "/")
            },
            displayNameAtPath: { path in
                fileManager.displayName(atPath: path)
            },
        )
    }

    nonisolated static var testValue: FileManagerComputerNameClient {
        FileManagerComputerNameClient(
            computerName: { "" },
            displayNameAtPath: { _ in "" },
        )
    }

    nonisolated static var previewValue: FileManagerComputerNameClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var fileManagerComputerNameClient: FileManagerComputerNameClient {
        get { self[FileManagerComputerNameClient.self] }
        set { self[FileManagerComputerNameClient.self] = newValue }
    }
}
