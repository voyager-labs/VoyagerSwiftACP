import Foundation

enum TabUtils {
    static func getDisplayName(for path: String) -> String {
        let pathURL = URL(fileURLWithPath: path)
        let lastComponent = pathURL.lastPathComponent

        if lastComponent.isEmpty || lastComponent == "/" {
            return "Root"
        } else {
            return lastComponent
        }
    }
}
