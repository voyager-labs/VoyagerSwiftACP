import VoyagerEntitiesAppPreferences

public enum OnboardingPermissionDebugScenario: String, CaseIterable, Identifiable, Sendable {
    case allGranted
    case fullDiskAccessDenied
    case fullDiskAccessNeedsAction
    case helperFoldersDenied
    case helperFoldersPartial
    case allDenied

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .allGranted:
            "All Granted"
        case .fullDiskAccessDenied:
            "Full Disk Access Denied"
        case .fullDiskAccessNeedsAction:
            "Full Disk Access Needs Action"
        case .helperFoldersDenied:
            "Helper Folders Denied"
        case .helperFoldersPartial:
            "Helper Folders Partial"
        case .allDenied:
            "All Denied"
        }
    }

    public var summary: String {
        switch self {
        case .allGranted:
            "FDA and helper folders are granted."
        case .fullDiskAccessDenied:
            "FDA is denied while helper folders are granted."
        case .fullDiskAccessNeedsAction:
            "FDA still needs user action."
        case .helperFoldersDenied:
            "FDA is granted but helper folders are denied."
        case .helperFoldersPartial:
            "FDA is granted and one helper folder is missing."
        case .allDenied:
            "FDA and helper folders are denied."
        }
    }
}

extension OnboardingPermissionDebugScenario {
    var fullDiskAccessStatus: FullDiskAccessStatus {
        switch self {
        case .allGranted, .helperFoldersDenied, .helperFoldersPartial:
            .granted
        case .fullDiskAccessDenied, .allDenied:
            .denied
        case .fullDiskAccessNeedsAction:
            .needsAction
        }
    }

    var helperFolderAccess: FolderAccessResult {
        switch self {
        case .allGranted, .fullDiskAccessDenied, .fullDiskAccessNeedsAction:
            FolderAccessResult(desktop: .granted, documents: .granted, downloads: .granted)
        case .helperFoldersDenied, .allDenied:
            FolderAccessResult(desktop: .notGranted, documents: .notGranted, downloads: .notGranted)
        case .helperFoldersPartial:
            FolderAccessResult(desktop: .granted, documents: .granted, downloads: .notGranted)
        }
    }

    var launchAtLoginEnabled: Bool {
        false
    }
}
