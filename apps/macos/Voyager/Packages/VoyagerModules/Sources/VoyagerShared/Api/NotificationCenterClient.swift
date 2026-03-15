import Combine
import ComposableArchitecture
@preconcurrency import Foundation

public struct NotificationCenterClient: Sendable {
    public var notifications: @Sendable (Notification.Name, NSObject?) -> AsyncStream<Notification>
    public var addObserver: @Sendable (Notification.Name, NSObject?, @escaping @Sendable (Notification) -> Void)
        -> NSObjectProtocol
    public var removeObserver: @Sendable (NSObjectProtocol) -> Void
    public var publisher: @Sendable (Notification.Name) -> NotificationCenter.Publisher
    public var post: @Sendable (Notification.Name, NSObject?, [AnyHashable: Any]?) -> Void

    public nonisolated init(
        notifications: @escaping @Sendable (Notification.Name, NSObject?) -> AsyncStream<Notification>,
        addObserver: @escaping @Sendable (Notification.Name, NSObject?, @escaping @Sendable (Notification) -> Void)
            -> NSObjectProtocol,
        removeObserver: @escaping @Sendable (NSObjectProtocol) -> Void,
        publisher: @escaping @Sendable (Notification.Name) -> NotificationCenter.Publisher,
        post: @escaping @Sendable (Notification.Name, NSObject?, [AnyHashable: Any]?) -> Void,
    ) {
        self.notifications = notifications
        self.addObserver = addObserver
        self.removeObserver = removeObserver
        self.publisher = publisher
        self.post = post
    }
}

extension NotificationCenterClient: DependencyKey {
    public nonisolated static var liveValue: NotificationCenterClient {
        let center = NotificationCenter.default
        return NotificationCenterClient(
            notifications: { name, object in
                AsyncStream { continuation in
                    final class ObserverBox: @unchecked Sendable {
                        var observer: NSObjectProtocol?
                        let center: NotificationCenter

                        init(center: NotificationCenter) {
                            self.center = center
                        }
                    }

                    let box = ObserverBox(center: center)
                    box.observer = box.center.addObserver(
                        forName: name,
                        object: object,
                        queue: .main,
                        using: { notification in
                            continuation.yield(notification)
                        },
                    )

                    continuation.onTermination = { @Sendable _ in
                        if let observer = box.observer {
                            box.center.removeObserver(observer)
                        }
                    }
                }
            },
            addObserver: { name, object, handler in
                center.addObserver(
                    forName: name,
                    object: object,
                    queue: .main,
                    using: { notification in
                        handler(notification)
                    },
                )
            },
            removeObserver: { token in
                center.removeObserver(token)
            },
            publisher: { name in
                center.publisher(for: name)
            },
            post: { name, object, userInfo in
                center.post(name: name, object: object, userInfo: userInfo)
            },
        )
    }

    public nonisolated static var testValue: NotificationCenterClient {
        NotificationCenterClient(
            notifications: { _, _ in AsyncStream { _ in } },
            addObserver: { _, _, _ in NSObject() },
            removeObserver: { _ in },
            publisher: { _ in NotificationCenter.default.publisher(for: .init("")) },
            post: { _, _, _ in },
        )
    }

    public nonisolated static var previewValue: NotificationCenterClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var notificationCenterClient: NotificationCenterClient {
        get { self[NotificationCenterClient.self] }
        set { self[NotificationCenterClient.self] = newValue }
    }
}
