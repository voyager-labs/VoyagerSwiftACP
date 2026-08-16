import Foundation
import os

/// Mail scripting 원문(`source`) export 시스템 경계. `ExternalDropAcquisitionClient.loadMailSource`가
/// 이 실행자를 호출하며, 테스트는 클라이언트의 클로저를 교체해 경계를 대체한다.
enum MailMessageSourceExport {
    private static let logger = Logger(subsystem: "fm.voyager.external-drop", category: "mail-export")

    static func load(_ lookup: MailMessageSourceLookup) -> Data? {
        let match: String
        let value: String
        if let numericID = lookup.numericID {
            match = "id"
            value = String(numericID)
        } else if let messageID = lookup.messageID {
            match = "message id"
            value = appleScriptString(messageID)
        } else {
            return nil
        }
        let scriptSource = """
        on sourceForMessage(targetMailbox, targetValue)
            tell application id "com.apple.mail"
                try
                    set matchedMessages to (messages of targetMailbox whose \(match) is targetValue)
                    if (count of matchedMessages) is greater than 0 then return source of item 1 of matchedMessages
                end try
                repeat with childMailbox in mailboxes of targetMailbox
                    set childSource to my sourceForMessage(childMailbox, targetValue)
                    if childSource is not missing value then return childSource
                end repeat
            end tell
            return missing value
        end sourceForMessage

        tell application id "com.apple.mail"
            repeat with targetAccount in accounts
                repeat with targetMailbox in mailboxes of targetAccount
                    set messageSource to my sourceForMessage(targetMailbox, \(value))
                    if messageSource is not missing value then return messageSource
                end repeat
            end repeat
            error number -1728
        end tell
        """
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: scriptSource)?.executeAndReturnError(&error),
              let source = descriptor.stringValue
        else {
            let errorNumber = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            logger.info("mail source export failed error=\(errorNumber, privacy: .public)")
            return nil
        }
        return Data(source.utf8)
    }

    private static func appleScriptString(_ value: String) -> String {
        let escapedBackslashes = value.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedQuotes = escapedBackslashes.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapedQuotes)\""
    }
}
