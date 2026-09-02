import Foundation

struct CodexExecJSONLDecoder {
    static let maximumRawLineBytes = 1024 * 1024
    static let maximumFinalAssistantTextBytes = 128 * 1024
    static let maximumFinalAssistantItems = 128

    private var buffer = Data()
    private(set) var diagnostics = CodexExecDiagnostics(stderr: "", unknown: .init(types: [], totalCount: 0))
    private(set) var finalAssistantText = CodexExecFinalAssistantText(value: "")
    private struct ItemText {
        var delta = ""
        var completed: String?

        var resolved: String {
            completed ?? delta
        }
    }

    private enum FinalTextSlot {
        case keyed(String)
        case unkeyed(Int)
    }

    private var finalTextByItemID: [String: ItemText] = [:]
    private var finalTextSlots: [FinalTextSlot] = []
    private var unkeyedFinalText: [String] = []
    private var retainedFinalTextBytes = 0
    private(set) var lastOutcomeEncodedBytes: [Int] = []

    var retainedFinalTextByteCount: Int {
        retainedFinalTextBytes
    }

    mutating func append(_ chunk: Data) throws -> [CodexExecDecodeOutcome] {
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)
        var outcomes: [CodexExecDecodeOutcome] = []
        lastOutcomeEncodedBytes.removeAll(keepingCapacity: true)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard line.count <= Self.maximumRawLineBytes else { reset()
                throw CodexExecDecodeError.rawLineTooLarge
            }
            try outcomes.append(decode(line))
            lastOutcomeEncodedBytes.append(line.count + 1)
        }
        guard buffer.count <= Self.maximumRawLineBytes else { reset()
            throw CodexExecDecodeError.rawLineTooLarge
        }
        return outcomes
    }

    mutating func finish() throws -> [CodexExecDecodeOutcome] {
        guard !buffer.isEmpty else { return [] }
        let line = buffer
        buffer.removeAll(keepingCapacity: false)
        lastOutcomeEncodedBytes.removeAll(keepingCapacity: true)
        guard line.count <= Self.maximumRawLineBytes else { reset()
            throw CodexExecDecodeError.rawLineTooLarge
        }
        do {
            let outcome = try decode(line)
            lastOutcomeEncodedBytes = [line.count]
            return [outcome]
        } catch CodexExecDecodeError.malformedFrame {
            guard (try? JSONSerialization.jsonObject(with: line)) == nil else {
                throw CodexExecDecodeError.malformedFrame
            }
            throw CodexExecDecodeError.incompleteFrame
        }
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
        diagnostics = CodexExecDiagnostics(stderr: "", unknown: .init(types: [], totalCount: 0))
        finalAssistantText = CodexExecFinalAssistantText(value: "")
        finalTextByItemID.removeAll(keepingCapacity: false)
        finalTextSlots.removeAll(keepingCapacity: false)
        unkeyedFinalText.removeAll(keepingCapacity: false)
        retainedFinalTextBytes = 0
        lastOutcomeEncodedBytes.removeAll(keepingCapacity: false)
    }

    mutating func retainStderr(_ input: String) {
        diagnostics = CodexExecDiagnostics(
            stderr: CodexExecDiagnosticsBuilder.redactAndBoundStderr(diagnostics.stderr + input),
            unknown: diagnostics.unknown,
        )
    }

    private mutating func decode(_ line: Data) throws -> CodexExecDecodeOutcome {
        var bytes = line
        if bytes.last == 0x0D { bytes.removeLast() }
        guard !bytes.isEmpty, let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let rawType = object["type"] as? String
        else { throw CodexExecDecodeError.malformedFrame }
        let type = CodexExecRawEventType(rawValue: rawType)
        if case .unknown = type {
            let current = diagnostics.unknown
            let types = current.types.contains(rawType) || current.types.count >= CodexExecDiagnosticsBuilder
                .maximumUnknownTypes
                ? current.types
                : current.types + [rawType]
            diagnostics = CodexExecDiagnostics(
                stderr: diagnostics.stderr,
                unknown: CodexExecUnknownEvidence(
                    types: types,
                    totalCount: min(current.totalCount + 1, CodexExecDiagnosticsBuilder.maximumUnknownCount),
                ),
            )
            return .unknown(type: rawType)
        }
        guard validPayloadShape(in: object) else { throw CodexExecDecodeError.malformedFrame }
        let commandExecutionEvidence = try commandExecutionEvidence(from: object)
        let event = CodexExecDecodedEvent(type: type, payload: payload(
            from: object,
            commandExecutionEvidence: commandExecutionEvidence,
        ))
        try retainFinalText(for: event, type: type)
        return .event(event)
    }

    private mutating func retainFinalText(
        for event: CodexExecDecodedEvent,
        type: CodexExecRawEventType,
    ) throws {
        guard type == .itemCompleted || type == .itemUpdated,
              CodexExecItemType.isAgentMessage(event.payload.itemType),
              let text = event.payload.text
        else { return }
        guard let itemID = event.payload.itemID else {
            guard unkeyedFinalText.count < Self.maximumFinalAssistantItems else {
                throw CodexExecDecodeError.finalAssistantItemLimit
            }
            let bounded = Self.prefixUTF8(
                text,
                maximumBytes: Self.maximumFinalAssistantTextBytes - retainedFinalTextBytes,
            )
            let index = unkeyedFinalText.count
            unkeyedFinalText.append(bounded)
            finalTextSlots.append(.unkeyed(index))
            retainedFinalTextBytes += bounded.utf8.count
            rebuildFinalAssistantText()
            return
        }
        if finalTextByItemID[itemID] == nil, finalTextByItemID.count >= Self.maximumFinalAssistantItems {
            throw CodexExecDecodeError.finalAssistantItemLimit
        }
        var item = finalTextByItemID[itemID, default: ItemText()]
        if type == .itemUpdated {
            guard item.completed == nil else { return }
            let boundedDelta = Self.prefixUTF8(
                text,
                maximumBytes: Self.maximumFinalAssistantTextBytes - retainedFinalTextBytes,
            )
            item.delta.append(boundedDelta)
            retainedFinalTextBytes += boundedDelta.utf8.count
        } else {
            retainedFinalTextBytes -= item.resolved.utf8.count
            let boundedCompleted = Self.prefixUTF8(
                text,
                maximumBytes: Self.maximumFinalAssistantTextBytes - retainedFinalTextBytes,
            )
            item.delta = ""
            item.completed = boundedCompleted
            retainedFinalTextBytes += boundedCompleted.utf8.count
        }
        finalTextByItemID[itemID] = item
        if !hasKeyedSlot(for: itemID) {
            finalTextSlots.append(.keyed(itemID))
        }
        rebuildFinalAssistantText()
    }

    private func hasKeyedSlot(for itemID: String) -> Bool {
        for slot in finalTextSlots {
            if case let .keyed(existingID) = slot, existingID == itemID {
                return true
            }
        }
        return false
    }

    private mutating func rebuildFinalAssistantText() {
        var value = ""
        for slot in finalTextSlots {
            switch slot {
            case let .keyed(itemID): value += finalTextByItemID[itemID]?.resolved ?? ""
            case let .unkeyed(index): value += unkeyedFinalText[index]
            }
        }
        finalAssistantText = CodexExecFinalAssistantText(value: value)
    }

    private static func prefixUTF8(_ text: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0 else { return "" }
        var bytes = Data(text.utf8.prefix(maximumBytes))
        for _ in 0 ... 3 {
            if let value = String(data: bytes, encoding: .utf8) { return value }
            guard !bytes.isEmpty else { return "" }
            bytes.removeLast()
        }
        return ""
    }

    private func payload(
        from object: [String: Any],
        commandExecutionEvidence: CodexExecCommandExecutionEvidence?,
    ) -> CodexExecEventPayload {
        let item = object["item"] as? [String: Any]
        let turn = object["turn"] as? [String: Any]
        return CodexExecEventPayload(
            threadID: object["thread_id"] as? String,
            turnID: (object["turn_id"] as? String) ?? (turn?["id"] as? String),
            itemID: (object["item_id"] as? String) ?? (item?["id"] as? String),
            itemType: (object["item_type"] as? String) ?? (item?["type"] as? String),
            status: (object["status"] as? String) ?? (turn?["status"] as? String),
            text: (object["text"] as? String) ?? (item?["text"] as? String) ?? (object["delta"] as? String),
            message: object["message"] as? String,
            commandExecutionEvidence: commandExecutionEvidence,
        )
    }

    private func commandExecutionEvidence(
        from object: [String: Any],
    ) throws -> CodexExecCommandExecutionEvidence? {
        let item = object["item"] as? [String: Any]
        let itemType = (object["item_type"] as? String) ?? (item?["type"] as? String)
        guard itemType == "command_execution" || itemType == "commandExecution" else { return nil }
        let rawStatus = item?["status"]
        let rawExitCode = item?["exit_code"]
        guard rawStatus == nil || rawStatus is String else { throw CodexExecDecodeError.malformedFrame }
        if let rawExitCode, !(rawExitCode is NSNull) {
            guard validExitCode(rawExitCode) else { throw CodexExecDecodeError.malformedFrame }
        }
        let status: CodexExecCommandExecutionStatus?
        if let rawStatus = rawStatus as? String {
            guard let parsed = CodexExecCommandExecutionStatus(rawValue: rawStatus) else {
                throw CodexExecDecodeError.malformedFrame
            }
            status = parsed
        } else {
            status = nil
        }
        let exitCode = (rawExitCode as? NSNumber).map { Int32($0.int64Value) }
        guard status != nil || exitCode != nil else { return nil }
        return CodexExecCommandExecutionEvidence(status: status, exitCode: exitCode)
    }

    private func validExitCode(_ value: Any?) -> Bool {
        if let integer = value as? Int {
            return integer >= Int(Int32.min) && integer <= Int(Int32.max)
        }
        guard let number = value as? NSNumber, !(value is Bool) else {
            return false
        }
        let integer = number.int64Value
        return number.doubleValue == Double(integer) && integer >= Int64(Int32.min) && integer <= Int64(Int32.max)
    }

    private func validPayloadShape(in object: [String: Any]) -> Bool {
        let stringKeys = ["thread_id", "turn_id", "item_id", "item_type", "status", "text", "delta", "message"]
        guard stringKeys.allSatisfy({ key in object[key] == nil || object[key] is String }) else { return false }
        guard object["item"] == nil || object["item"] is [String: Any] else { return false }
        guard object["turn"] == nil || object["turn"] is [String: Any] else { return false }
        if let item = object["item"] as? [String: Any], !validNestedStringFields(
            in: item,
            keys: ["id", "type", "text", "status"],
        ) {
            return false
        }
        if let item = object["item"] as? [String: Any],
           let itemType = object["item_type"] as? String,
           let nestedItemType = item["type"] as? String,
           itemType != nestedItemType
        {
            return false
        }
        if let turn = object["turn"] as? [String: Any], !validNestedStringFields(
            in: turn,
            keys: ["id", "status"],
        ) {
            return false
        }
        return true
    }

    private func validNestedStringFields(in object: [String: Any], keys: [String]) -> Bool {
        keys.allSatisfy { key in object[key] == nil || object[key] is String }
    }
}
