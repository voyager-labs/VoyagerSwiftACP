import Foundation

/// Feature-local collection file heuristic.
/// Absorbs only the `voycoll` extension判別 logic needed by EntryOperations.
/// Does NOT pull in full Collection domain – keeps scope tight.
enum EntryOperationsCollectionFileHeuristic {
    /// File extension used for collection folders.
    private static let collectionFileExtension = "voycoll"

    /// Check if a file URL points to a collection folder.
    static func isCollectionFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == collectionFileExtension
    }

    /// Check if a file extension string indicates a collection folder.
    static func isCollectionFileExtension(_ ext: String) -> Bool {
        ext.lowercased() == collectionFileExtension
    }
}
