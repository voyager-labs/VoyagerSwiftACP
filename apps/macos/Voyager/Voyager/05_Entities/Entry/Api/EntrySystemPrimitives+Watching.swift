import Foundation

extension EntrySystemPrimitives {
    nonisolated static var livePostFileSystemChanged: @Sendable ([String]) -> Void {
        { paths in
            let notificationName = NSNotification.Name("VoyagerFileSystemChanged")
            NotificationCenter.default.post(
                name: notificationName,
                object: nil,
                userInfo: ["paths": paths],
            )
        }
    }
}
