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

        if isCanonicalPath(
            destinationURL,
            applicationSupportURL: applicationSupportURL,
        ) {
            return true
        }

        do {
            let resolvedDestinationURL = try resolveFinalURL(
                destinationURL,
                fileManagerClient: fileManagerClient,
            )
            let resolvedApplicationSupportURL = try resolveFinalURL(
                applicationSupportURL,
                fileManagerClient: fileManagerClient,
            )
            return isCanonicalPath(
                resolvedDestinationURL,
                applicationSupportURL: resolvedApplicationSupportURL,
            )
        } catch {
            return false
        }
    }

    private static func isCanonicalPath(
        _ packageURL: URL,
        applicationSupportURL: URL,
    ) -> Bool {
        let packagePath = packageURL.standardizedFileURL.path
        return BuiltInCollectionIdentity.allCases.contains { identity in
            let canonicalPath = identity.canonicalPackageURL(
                applicationSupportURL: applicationSupportURL,
            )
            .standardizedFileURL.path
            return packagePath.caseInsensitiveCompare(canonicalPath) == .orderedSame
        }
    }

    private static func resolveFinalURL(
        _ url: URL,
        fileManagerClient: FileManagerClient,
    ) throws -> URL {
        var existingAncestorURL = url.standardizedFileURL
        var trailingComponents: [String] = []

        while !fileManagerClient.fileExists(existingAncestorURL.path) {
            guard existingAncestorURL.path != "/" else { break }
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
