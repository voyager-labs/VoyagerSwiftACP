import AppKit
import Foundation

enum EntryFinderReveal {
    static func reveal(_ urls: [URL]) throws {
        var error: NSDictionary?
        let script = NSAppleScript(source: scriptSource(for: urls))
        guard script?.executeAndReturnError(&error) != nil else {
            if let errorNumber = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue,
               errorNumber == -1743
            {
                throw FileOpError.system(
                    message: "Voyager could not control Finder.",
                    suggestion: "Allow Voyager to control Finder in System Settings > Privacy & Security > Automation.",
                )
            }
            throw FileOpError.system(message: "Failed to reveal item in Finder.")
        }
    }

    static func scriptSource(for urls: [URL]) -> String {
        let commands = urls.map { url in
            "    reveal POSIX file \(appleScriptString(url.path))"
        }
        let revealCommands = commands.joined(separator: "\n")

        return """
        tell application id "com.apple.finder"
            activate
        \(revealCommands)
        end tell
        """
    }

    private static func appleScriptString(_ value: String) -> String {
        let escapedBackslashes = value.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedQuotes = escapedBackslashes.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapedQuotes)\""
    }
}
