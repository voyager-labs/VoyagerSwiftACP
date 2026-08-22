import ComposableArchitecture
import Foundation
import VoyagerShared

func makeCollectionFile(
    name: String,
    snapshot: CollectionSaveSnapshot,
    appVersion: String?,
) -> VoyagerCollectionFile {
    let timestamp = Date()
    return VoyagerCollectionFile(
        id: UUID().uuidString,
        name: name,
        createdAt: timestamp,
        updatedAt: timestamp,
        query: snapshot.query,
        scopes: snapshot.scopes,
        excludedScopes: snapshot.excludedScopes,
        includeSubfolders: snapshot.includeSubfolders,
        includeDirectories: snapshot.includeDirectories,
        conditions: snapshot.conditions,
        snapshot: snapshot.snapshotItems.map(CollectionPersistedSnapshot.init(items:)),
        snapshotMeta: snapshot.snapshotItems.map { snapshotItems in
            .init(
                definitionFingerprint: snapshot.definitionFingerprint,
                capturedAt: snapshot.capturedAt,
                itemCount: snapshotItems.count,
                relevanceRoots: snapshot.relevanceRoots,
            )
        },
        appVersion: appVersion,
    )
}

func currentAppVersion() -> String? {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String
    let build = info?["CFBundleVersion"] as? String

    switch (version, build) {
    case let (.some(version), .some(build)):
        return "\(version) (\(build))"
    case let (.some(version), .none):
        return version
    case let (.none, .some(build)):
        return build
    default:
        return nil
    }
}

struct CollectionSaveRequest {
    let url: URL
    let file: VoyagerCollectionFile
}

func buildSaveRequest(
    snapshot: CollectionSaveSnapshot,
    destinationURL: URL,
) -> CollectionSaveRequest {
    let finalURL: URL = if destinationURL.pathExtension.lowercased() == CollectionConstants.fileExtension {
        destinationURL
    } else {
        destinationURL
            .deletingPathExtension()
            .appendingPathExtension(CollectionConstants.fileExtension)
    }
    let file = makeCollectionFile(
        name: finalURL.deletingPathExtension().lastPathComponent,
        snapshot: snapshot,
        appVersion: currentAppVersion(),
    )
    return .init(url: finalURL, file: file)
}

func executeSave(
    request: CollectionSaveRequest,
    savedContext: CollectionContext,
    fileClient: CollectionFileClient,
) -> Effect<CollectionAction> {
    .run { send in
        do {
            try await fileClient.save(request.file, request.url)
            await send(.saveCompleted(.success(.init(
                url: request.url,
                file: request.file,
                savedContext: savedContext,
            ))))
        } catch {
            await send(.saveCompleted(.failure(error)))
        }
    }
}
