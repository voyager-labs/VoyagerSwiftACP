@preconcurrency import AppKit
import VoyagerEntitiesEntry

enum EntryViewLayoutDropValidationAdapter {
    @MainActor
    static func resolve(
        draggingInfo: any NSDraggingInfo,
        destinationPath: String,
    ) -> EntryDropValidationResult {
        resolve(
            sourcePaths: sourcePaths(from: draggingInfo.draggingPasteboard),
            destinationPath: destinationPath,
            allowedOperations: draggingInfo.draggingSourceOperationMask,
            prefersCopy: NSEvent.modifierFlags.contains(.option),
        )
    }

    static func resolve(
        sourcePaths: [String],
        destinationPath: String,
        allowedOperations: NSDragOperation,
        prefersCopy: Bool,
    ) -> EntryDropValidationResult {
        EntryDropValidationResolver.resolve(.init(
            sourcePaths: sourcePaths,
            destinationPath: destinationPath,
            allowedOperationsRawValue: allowedOperations.rawValue,
            prefersCopy: prefersCopy,
        ))
    }

    static func dragOperation(from operation: EntryDropResolvedOperation) -> NSDragOperation {
        switch operation {
        case .none:
            []
        case .copy:
            .copy
        case .move:
            .move
        }
    }

    @MainActor
    static func sourcePaths(from pasteboard: NSPasteboard) -> [String] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.map(\.path) ?? []
    }
}
