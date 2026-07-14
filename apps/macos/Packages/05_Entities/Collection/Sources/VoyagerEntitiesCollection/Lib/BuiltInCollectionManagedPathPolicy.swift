import Foundation
import VoyagerShared

enum BuiltInCollectionManagedPathPolicy {
    enum ValidationError: Error {
        case unsafeManagedPath
    }

    static func validateManagedRoot(
        _ rootURL: URL,
        applicationSupportURL: URL,
        fileManagerClient: FileManagerClient,
    ) throws -> URL {
        let standardizedApplicationSupportURL = applicationSupportURL.standardizedFileURL
        let standardizedRootURL = rootURL.standardizedFileURL
        guard standardizedRootURL.path.hasPrefix(standardizedApplicationSupportURL.path + "/") else {
            throw ValidationError.unsafeManagedPath
        }

        let relativePath = String(
            standardizedRootURL.path.dropFirst(standardizedApplicationSupportURL.path.count + 1),
        )
        let resolvedApplicationSupportURL = try resolveFinalURL(
            standardizedApplicationSupportURL,
            fileManagerClient: fileManagerClient,
        )
        let expectedRootURL = resolvedApplicationSupportURL
            .appendingPathComponent(relativePath, isDirectory: true)
            .standardizedFileURL
        let resolvedRootURL = try resolveFinalURL(
            standardizedRootURL,
            fileManagerClient: fileManagerClient,
        )
        guard resolvedRootURL.path == expectedRootURL.path else {
            throw ValidationError.unsafeManagedPath
        }
        return resolvedRootURL
    }

    static func validateManagedPackage(
        _ packageURL: URL,
        managedRootURL: URL,
        fileManagerClient: FileManagerClient,
    ) throws {
        let expectedPackageURL = managedRootURL
            .appendingPathComponent(packageURL.lastPathComponent, isDirectory: true)
            .standardizedFileURL
        let resolvedPackageURL = try resolveFinalURL(
            packageURL,
            fileManagerClient: fileManagerClient,
        )
        guard resolvedPackageURL.path == expectedPackageURL.path else {
            throw ValidationError.unsafeManagedPath
        }
    }

    static func isCanonicalDestination(
        _ destinationURL: URL,
        fileManagerClient: FileManagerClient,
    ) -> Bool {
        guard let applicationSupportURL = fileManagerClient.urlsForDirectory(
            .applicationSupportDirectory,
            .userDomainMask,
        ).first else {
            return false
        }

        let lexicalIdentity = BuiltInCollectionIdentity.classify(
            packageURL: destinationURL,
            applicationSupportURL: applicationSupportURL,
        )
        do {
            let resolvedDestinationURL = try resolveFinalURL(
                destinationURL,
                fileManagerClient: fileManagerClient,
            )
            let resolvedApplicationSupportURL = try resolveFinalURL(
                applicationSupportURL,
                fileManagerClient: fileManagerClient,
            )
            return BuiltInCollectionIdentity.classify(
                packageURL: resolvedDestinationURL,
                applicationSupportURL: resolvedApplicationSupportURL,
            ) != nil
        } catch {
            return lexicalIdentity != nil
        }
    }

    private static func resolveFinalURL(
        _ url: URL,
        fileManagerClient: FileManagerClient,
    ) throws -> URL {
        var existingAncestorURL = url.standardizedFileURL
        var trailingComponents: [String] = []

        while !fileManagerClient.fileExists(existingAncestorURL.path) {
            let parentURL = existingAncestorURL.deletingLastPathComponent()
            guard parentURL.path != existingAncestorURL.path else { break }
            trailingComponents.insert(existingAncestorURL.lastPathComponent, at: 0)
            existingAncestorURL = parentURL
        }

        var resolvedURL = existingAncestorURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        if fileManagerClient.fileExists(existingAncestorURL.path),
           try existingAncestorURL.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true
        {
            resolvedURL = try URL(
                resolvingAliasFileAt: existingAncestorURL,
                options: [.withoutUI, .withoutMounting],
            )
            .resolvingSymlinksInPath()
            .standardizedFileURL
        }

        return trailingComponents.reduce(resolvedURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        .standardizedFileURL
    }
}
