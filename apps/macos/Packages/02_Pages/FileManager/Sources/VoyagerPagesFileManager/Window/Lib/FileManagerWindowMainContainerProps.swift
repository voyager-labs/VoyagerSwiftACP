import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

func makeContentChromeProps(
    from state: FileManagerWindowState,
    contentTabState: ContentTabState,
    fileManagerClient: FileManagerClient,
) -> FileManagerContentChromeProps {
    let computerName = fileManagerClient.displayName("/")
    let trashPath = fileManagerClient.urlsForDirectory(.trashDirectory, .userDomainMask).first?.path
    let breadcrumbRoots = FileManagerBreadcrumbRoots(
        homePath: NSHomeDirectory(),
        trashPath: trashPath,
    )
    let specialDirectoryIconNames = makeSpecialDirectoryIconNames(fileManagerClient: fileManagerClient)
    let activePageAnchor = ContentTabProjection.activePageAnchor(from: contentTabState) ?? .homeDefault

    return FileManagerContentChromeProps(
        computerName: computerName,
        breadcrumbRoots: breadcrumbRoots,
        pathDisplayNames: makePathDisplayNames(
            contentState: state.content,
            fileManagerClient: fileManagerClient,
            computerName: computerName,
            roots: breadcrumbRoots,
        ),
        specialDirectoryIconNames: specialDirectoryIconNames,
        isContextualAiChatPresented: state.inspector.inspectorVisible
            && state.inspector.activeMode == .chat,
        activeTabID: contentTabState.activeTabID,
        activePageAnchor: activePageAnchor,
    )
}

func makeContentOverlayProps(
    from state: FileManagerWindowState,
    fileManagerClient: FileManagerClient,
) -> FileManagerContentOverlayProps {
    FileManagerContentOverlayProps(
        isComposerPresented: state.content.composer.isPresented,
        favorites: makeScopeFavorites(fileManagerClient: fileManagerClient),
        historyPaths: state.content.navigation.backHistory.compactMap { entry in
            if case let .folder(path) = entry.navigationState {
                return path
            }
            return nil
        },
        isDiscardEnabled: state.content.isCollectionMode
            && state.content.collection.collectionSession.metadata.baseline != nil
            && state.content.isOpenedCollectionDirty,
        canSaveCollection: state.content.canSaveCollection,
        isTemporaryCollection: !state.content.openedCollectionURLExists,
    )
}

func makeScopeFavorites(fileManagerClient: FileManagerClient) -> [ScopeFavoriteItem] {
    let favoriteMappings: [(
        name: String,
        directory: FileManager.SearchPathDirectory,
        domain: FileManager.SearchPathDomainMask,
        iconName: String,
    )] = [
        ("Applications", .applicationDirectory, .localDomainMask, "folder.badge.gearshape"),
        ("Desktop", .desktopDirectory, .userDomainMask, "menubar.dock.rectangle"),
        ("Documents", .documentDirectory, .userDomainMask, "doc"),
        ("Downloads", .downloadsDirectory, .userDomainMask, "arrow.down.circle"),
    ]

    return favoriteMappings.compactMap { mapping in
        guard let url = fileManagerClient.urlsForDirectory(mapping.directory, mapping.domain).first else {
            return nil
        }
        return ScopeFavoriteItem(
            name: mapping.name,
            url: url,
            iconName: mapping.iconName,
        )
    }
}

func makeSpecialDirectoryIconNames(fileManagerClient: FileManagerClient) -> [String: String] {
    var result: [String: String] = [:]
    for mapping in FileManagerSpecialDirectoryIconConfig.specialDirectoryIconMappings {
        if let path = fileManagerClient.urlsForDirectory(mapping.directory, mapping.domain).first?.path {
            result[path] = mapping.iconSystemName
        }
    }
    return result
}

func makePathDisplayNames(
    contentState: FileManagerContentState,
    fileManagerClient: FileManagerClient,
    computerName: String,
    roots: FileManagerBreadcrumbRoots,
) -> [String: String] {
    var paths = Set<String>()

    paths.formUnion(
        BreadcrumbBuilder.breadcrumbPaths(
            navigationState: contentState.navigation.navigationState,
            roots: roots,
        ),
    )

    if contentState.navigation.titlePath.hasPrefix("/") {
        paths.insert(contentState.navigation.titlePath)
    }

    for history in contentState.navigation.backHistory + contentState.navigation.forwardHistory {
        switch history.navigationState {
        case let .folder(path):
            paths.insert(path)
        case .computer:
            paths.insert("/")
        case .home, .recents, .tags, .collection, .aiChat, .aiChatSessions:
            break
        }
    }

    if !computerName.isEmpty {
        paths.insert("/")
    }

    var result: [String: String] = [:]
    for path in paths {
        result[path] = fileManagerClient.displayName(path)
    }
    return result
}
