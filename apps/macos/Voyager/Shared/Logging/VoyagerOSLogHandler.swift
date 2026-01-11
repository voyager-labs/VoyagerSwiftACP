import Foundation
import Logging
import os

struct VoyagerOSLogHandler: LogHandler {
    var logLevel: Logging.Logger.Level = .info
    var metadata: Logging.Logger.Metadata = [:]

    let label: String
    private let osLogger: os.Logger

    init(label: String, subsystem: String = Bundle.main.bundleIdentifier ?? "Voyager") {
        self.label = label
        osLogger = os.Logger(subsystem: subsystem, category: label)
    }

    subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }

    func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source _: String,
        file _: String,
        function _: String,
        line _: UInt,
    ) {
        var combinedMetadata = self.metadata
        if let metadata, !metadata.isEmpty {
            combinedMetadata.merge(metadata) { _, new in new }
        }

        var composedMessage = message.description
        if !combinedMetadata.isEmpty {
            composedMessage += " -- " + combinedMetadata.map { "\($0)=\($1)" }.joined(separator: " ")
        }

        let osLevel: OSLogType = switch level {
        case .trace, .debug:
            .debug
        case .info, .notice:
            .info
        case .warning:
            .default
        case .error:
            .error
        case .critical:
            .fault
        }

        osLogger.log(level: osLevel, "\(composedMessage, privacy: .public)")
    }
}
