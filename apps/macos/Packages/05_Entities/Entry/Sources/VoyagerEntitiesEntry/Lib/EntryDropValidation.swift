@preconcurrency import AppKit
import Foundation

public struct EntryDropValidationContext: Equatable, Sendable {
    public let sourcePaths: [String]
    public let destinationPath: String
    public let allowedOperationsRawValue: UInt
    public let prefersCopy: Bool

    public init(
        sourcePaths: [String],
        destinationPath: String,
        allowedOperationsRawValue: UInt,
        prefersCopy: Bool,
    ) {
        self.sourcePaths = sourcePaths
        self.destinationPath = destinationPath
        self.allowedOperationsRawValue = allowedOperationsRawValue
        self.prefersCopy = prefersCopy
    }
}

public enum EntryDropResolvedOperation: Equatable, Sendable {
    case none
    case copy
    case move
}

public struct EntryDropValidationResult: Equatable, Sendable {
    public var destinationPath: String
    public var resolvedOperation: EntryDropResolvedOperation
    public var isOptionDrag: Bool

    public init(
        destinationPath: String,
        resolvedOperation: EntryDropResolvedOperation,
        isOptionDrag: Bool,
    ) {
        self.destinationPath = destinationPath
        self.resolvedOperation = resolvedOperation
        self.isOptionDrag = isOptionDrag
    }

    public static let empty = EntryDropValidationResult(
        destinationPath: "",
        resolvedOperation: .none,
        isOptionDrag: false,
    )
}

public enum EntryDropValidationResolver {
    public static func resolve(_ context: EntryDropValidationContext) -> EntryDropValidationResult {
        let destinationPath = context.destinationPath
        let sourcePaths = context.sourcePaths
        let hasSourcePaths = !sourcePaths.isEmpty

        if hasSourcePaths, !context.prefersCopy,
           let rejection = moveRejection(destinationPath: destinationPath, sourcePaths: sourcePaths)
        {
            return rejection
        }

        if hasSourcePaths, context.prefersCopy,
           rejectsCopyDescendantSelf(destinationPath: destinationPath, sourcePaths: sourcePaths)
        {
            return .init(
                destinationPath: destinationPath,
                resolvedOperation: .none,
                isOptionDrag: true,
            )
        }

        let allowedOperations = NSDragOperation(rawValue: context.allowedOperationsRawValue)
        let preferredOperation: EntryDropResolvedOperation = context.prefersCopy ? .copy : .move
        if contains(allowedOperations, preferredOperation) {
            return .init(
                destinationPath: destinationPath,
                resolvedOperation: preferredOperation,
                isOptionDrag: preferredOperation == .copy,
            )
        }

        if contains(allowedOperations, .copy) {
            return .init(
                destinationPath: destinationPath,
                resolvedOperation: .copy,
                isOptionDrag: true,
            )
        }

        return .init(
            destinationPath: destinationPath,
            resolvedOperation: .none,
            isOptionDrag: false,
        )
    }

    private static func moveRejection(
        destinationPath: String,
        sourcePaths: [String],
    ) -> EntryDropValidationResult? {
        guard let sourcePath = sourcePaths.first else {
            return .init(destinationPath: destinationPath, resolvedOperation: .none, isOptionDrag: false)
        }
        let sourceParent = URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path
        if sourceParent == destinationPath {
            return .init(destinationPath: destinationPath, resolvedOperation: .none, isOptionDrag: false)
        }
        for sourcePath in sourcePaths {
            if destinationPath == sourcePath || isDescendantPath(destinationPath, of: sourcePath) {
                return .init(destinationPath: destinationPath, resolvedOperation: .none, isOptionDrag: false)
            }
        }
        return nil
    }

    private static func contains(
        _ allowed: NSDragOperation,
        _ operation: EntryDropResolvedOperation,
    ) -> Bool {
        switch operation {
        case .none:
            false
        case .copy:
            allowed.contains(.copy)
        case .move:
            allowed.contains(.move)
        }
    }

    private static func rejectsCopyDescendantSelf(
        destinationPath: String,
        sourcePaths: [String],
    ) -> Bool {
        sourcePaths.contains { sourcePath in
            destinationPath == sourcePath || isDescendantPath(destinationPath, of: sourcePath)
        }
    }

    private static func isDescendantPath(_ destinationPath: String, of sourcePath: String) -> Bool {
        let destinationComponents = URL(fileURLWithPath: destinationPath)
            .standardizedFileURL.pathComponents
        let sourceComponents = URL(fileURLWithPath: sourcePath)
            .standardizedFileURL.pathComponents

        guard destinationComponents.count > sourceComponents.count else {
            return false
        }

        return Array(destinationComponents.prefix(sourceComponents.count)) == sourceComponents
    }
}
