import ACPModel
import Foundation

/// One new/load may open at a time because early updates carry no request ID.
/// Quarantine the opening session's updates until the response confirms its ID.
struct SessionOpening {
    var sessionId: SessionId?
    var notifications: [JSONRPCNotification] = []
    var byteCount = 0
    var requestId: RequestId?
    var completed = false

    mutating func stage(
        _ notification: JSONRPCNotification,
        sessionId incomingID: SessionId,
        registered: Bool,
        byteBudget: Int,
        encoder: JSONEncoder,
    ) throws -> Bool {
        guard !completed, sessionId == incomingID || !registered else { return false }
        if let expected = sessionId, expected != incomingID {
            throw ClientError.protocolViolation("session/update for unrelated opening session")
        }
        let bytes = try encoder.encode(notification).count
        guard bytes <= byteBudget - byteCount else {
            throw ClientError.protocolViolation("session opening notification byte budget exceeded")
        }
        sessionId = incomingID
        byteCount += bytes
        notifications.append(notification)
        return true
    }

    static func validateUpdate(_ notification: JSONRPCNotification, decoder: JSONDecoder) throws {
        guard let params = notification.params?.value as? [String: Any] else {
            throw ClientError.protocolViolation("session/update params must be an object")
        }
        guard params["sessionId"] is String else {
            throw ClientError.protocolViolation("session/update is missing sessionId")
        }
        guard let updateObject = params["update"] as? [String: Any] else {
            throw ClientError.protocolViolation("session/update is missing the update object")
        }

        guard let variant = updateObject["sessionUpdate"] as? String else {
            throw ClientError.protocolViolation("session/update is missing discriminator")
        }
        let knownVariants: Set = [
            "user_message_chunk", "agent_message_chunk", "agent_thought_chunk",
            "tool_call", "tool_call_update", "plan", "plan_update", "plan_removed",
            "available_commands_update", "current_mode_update", "config_option_update",
            "session_info_update", "usage_update",
        ]
        guard knownVariants.contains(variant) else { return }
        let updateData = try JSONSerialization.data(withJSONObject: updateObject)
        _ = try decoder.decode(SessionUpdate.self, from: updateData)
    }
}
