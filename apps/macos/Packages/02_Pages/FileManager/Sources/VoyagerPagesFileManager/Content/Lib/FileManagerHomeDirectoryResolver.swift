import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

public enum FileManagerHomeDirectoryResolver {
    public static func resolve(
        _ directory: FileManagerHomeDirectory,
        using fileManagerClient: FileManagerClient,
    ) -> ContentTabPageAnchor {
        .directory(path: url(for: directory, using: fileManagerClient)?.path ?? "/")
    }

    public static func url(
        for directory: FileManagerHomeDirectory,
        using fileManagerClient: FileManagerClient,
    ) -> URL? {
        fileManagerClient.urlsForDirectory(searchPathDirectory(for: directory), searchPathDomainMask(for: directory))
            .first
    }

    private static func searchPathDomainMask(for directory: FileManagerHomeDirectory) -> FileManager
        .SearchPathDomainMask
    {
        switch directory {
        case .applications:
            .localDomainMask
        case .desktop, .documents, .downloads:
            .userDomainMask
        }
    }

    private static func searchPathDirectory(for directory: FileManagerHomeDirectory) -> FileManager
        .SearchPathDirectory
    {
        switch directory {
        case .desktop:
            .desktopDirectory
        case .documents:
            .documentDirectory
        case .downloads:
            .downloadsDirectory
        case .applications:
            .applicationDirectory
        }
    }
}
