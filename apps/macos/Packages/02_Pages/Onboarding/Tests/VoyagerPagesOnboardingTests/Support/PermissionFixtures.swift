import VoyagerEntitiesAppPreferences

let kGrantedHelperAccess = FolderAccessResult(
    desktop: .granted,
    documents: .granted,
    downloads: .granted,
)

let kDeniedHelperAccess = FolderAccessResult(
    desktop: .notGranted,
    documents: .notGranted,
    downloads: .notGranted,
)

let kPartialHelperAccess = FolderAccessResult(
    desktop: .granted,
    documents: .granted,
    downloads: .notGranted,
)
