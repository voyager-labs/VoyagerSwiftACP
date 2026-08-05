import AppKit
import SwiftUI
import VoyagerEntitiesAi

enum AiChatLifecycleAnnouncementPhase: Hashable { case processing, activity, final, failure, cancel }

enum AiChatLifecycleAnnouncementPriority: Equatable {
    case medium, high

    var appKitValue: Int {
        switch self {
        case .medium: NSAccessibilityPriorityLevel.medium.rawValue
        case .high: NSAccessibilityPriorityLevel.high.rawValue
        }
    }
}

struct AiChatLifecycleAnnouncementKey: Hashable {
    let sessionID: AiChatSessionID
    let requestID: AiChatRequestID
    let phase: AiChatLifecycleAnnouncementPhase
    var activityID: AiChatExecutionActivityID?
    var activityKind: AiChatExecutionActivityKind?
    var activityPhase: AiChatExecutionActivityPhase?
}

struct AiChatLifecycleAnnouncement: Equatable {
    private struct Presentation {
        let phase: AiChatLifecycleAnnouncementPhase
        let message: String
        let priority: AiChatLifecycleAnnouncementPriority
    }

    let key: AiChatLifecycleAnnouncementKey
    let message: String
    let priority: AiChatLifecycleAnnouncementPriority

    init?(state: AiChatState) {
        guard let lock = state.executionPhase.lock,
              let sessionID = lock.context.sessionID,
              state.sessionID == sessionID
        else { return nil }
        let presentation: Presentation
        switch state.executionPhase {
        case let .processing(lock):
            if let signal = lock.activityState.latestTransition {
                key = AiChatLifecycleAnnouncementKey(
                    sessionID: sessionID,
                    requestID: lock.requestID,
                    phase: .activity,
                    activityID: signal.activityID,
                    activityKind: signal.kind,
                    activityPhase: signal.phase,
                )
                message = Self.activityAnnouncementMessage(signal)
                priority = .medium
                return
            }
            presentation = Presentation(phase: .processing, message: "Assistant response started.", priority: .medium)
        case .completed:
            presentation = Presentation(phase: .final, message: "Assistant response completed.", priority: .medium)
        case .failed:
            presentation = Presentation(phase: .failure, message: "Assistant response failed.", priority: .high)
        case .cancelled:
            presentation = Presentation(phase: .cancel, message: "Assistant response cancelled.", priority: .medium)
        case .idle, .persistenceRecovery:
            return nil
        }
        key = AiChatLifecycleAnnouncementKey(
            sessionID: sessionID,
            requestID: lock.requestID,
            phase: presentation.phase,
            activityID: nil,
            activityKind: nil,
            activityPhase: nil,
        )
        message = presentation.message
        priority = presentation.priority
    }

    private static func activityAnnouncementMessage(_ signal: AiChatExecutionActivitySignal) -> String {
        let activity = switch signal.kind {
        case .thinking: "Thinking"
        case .searching: "Searching"
        case .toolExecution: "Running a tool"
        case .retrying: "Retrying"
        case .answerGeneration: "Generating answer"
        }
        switch signal.phase {
        case .began: return "\(activity) started."
        case .ended: return "\(activity) finished."
        }
    }
}

struct AiChatAccessibilityAnnouncementDeduper {
    private var announcedKeys: Set<AiChatLifecycleAnnouncementKey> = []

    mutating func shouldAnnounce(_ key: AiChatLifecycleAnnouncementKey) -> Bool {
        announcedKeys.insert(key).inserted
    }
}

struct AiChatAccessibilityAnnouncementSink {
    let post: @MainActor (AiChatLifecycleAnnouncement) -> Void

    static let live = Self { announcement in
        AiChatAccessibilityAnnouncer.post(announcement)
    }
}

extension EnvironmentValues {
    @Entry var aiChatAccessibilityAnnouncementSink = AiChatAccessibilityAnnouncementSink.live
}

@MainActor
enum AiChatAccessibilityAnnouncer {
    private static var deduper = AiChatAccessibilityAnnouncementDeduper()

    static func post(_ announcement: AiChatLifecycleAnnouncement) {
        guard deduper.shouldAnnounce(announcement.key) else { return }
        if #available(macOS 14.0, *) {
            AccessibilityNotification.Announcement(announcement.message).post()
        } else {
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: announcement.message,
                    .priority: announcement.priority.appKitValue,
                ],
            )
        }
    }
}
