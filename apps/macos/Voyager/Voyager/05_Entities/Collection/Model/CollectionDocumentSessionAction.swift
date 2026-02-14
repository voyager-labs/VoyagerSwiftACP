import Foundation

enum CollectionDocumentSessionAction: Equatable, Sendable {
    case openRequested(URL)
    case openLoaded(url: URL, file: VoyagerCollectionFile)
    case openCancelled

    case delegate(CollectionDocumentSessionDelegate)
}

enum CollectionDocumentSessionDelegate: Equatable, Sendable {
    // Page/Feature 계층이 실제 IO를 수행하도록 요청한다.
    case loadFile(URL)
}
