import Foundation

public struct FileManagerBreadcrumbRoots: Equatable {
    let homePath: String
    let trashPath: String?
    let iCloudDrivePath: String
    let cloudStoragePath: String

    init(homePath: String, trashPath: String?) {
        self.homePath = homePath
        self.trashPath = trashPath
        iCloudDrivePath = (homePath as NSString)
            .appendingPathComponent(FileManagerSpecialRootRelativePathConfig.iCloudDrive)
        cloudStoragePath = (homePath as NSString)
            .appendingPathComponent(FileManagerSpecialRootRelativePathConfig.cloudStorage)
    }

    func specialRootPath(for path: String) -> String? {
        if let trashPath,
           path == trashPath || path.hasPrefix(trashPath + "/")
        {
            return trashPath
        }

        if path.hasPrefix(iCloudDrivePath) {
            return iCloudDrivePath
        }

        let cloudStoragePrefix = cloudStoragePath + "/"
        if path.hasPrefix(cloudStoragePrefix) {
            let relativePath = path.replacingOccurrences(of: cloudStoragePrefix, with: "")
            if let firstSlashIndex = relativePath.firstIndex(of: "/") {
                return (cloudStoragePath as NSString)
                    .appendingPathComponent(String(relativePath[..<firstSlashIndex]))
            }
            return path
        }

        return nil
    }
}
