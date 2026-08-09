import AppKit
import SwiftUI
import VoyagerEntitiesAi

struct AiChatTranscriptScrollRestoreRequest: Equatable {
    let sessionID: AiChatSessionID
    let offsetY: CGFloat
    let sequence: Int
}

struct AiChatTranscriptScrollObserver: NSViewRepresentable {
    let sessionID: AiChatSessionID?
    let restoreRequest: AiChatTranscriptScrollRestoreRequest?
    let onScrollOffsetChanged: (CGFloat, AiChatSessionID?) -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.restoreRequest = restoreRequest
        let probe = AiChatTranscriptScrollProbeView()
        context.coordinator.configureProbe(probe)
        return probe
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.sessionID = sessionID
        context.coordinator.onScrollOffsetChanged = onScrollOffsetChanged
        context.coordinator.restoreRequest = restoreRequest
        context.coordinator.attachScrollView(from: view)
        context.coordinator.applyPendingRestoreIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator _: Coordinator) {
        (nsView as? AiChatTranscriptScrollProbeView)?.onHierarchyChanged = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject {
        var sessionID: AiChatSessionID?
        var onScrollOffsetChanged: ((CGFloat, AiChatSessionID?) -> Void)?
        var restoreRequest: AiChatTranscriptScrollRestoreRequest?

        private weak var scrollView: NSScrollView?
        private weak var observedClipView: NSClipView?
        private var appliedRestoreSessionID: AiChatSessionID?
        private var appliedRestoreSequence: Int?
        private var isApplyingRestore = false

        deinit {
            guard let observedClipView else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: observedClipView,
            )
        }

        func configureProbe(_ probe: AiChatTranscriptScrollProbeView) {
            probe.onHierarchyChanged = { [weak self, weak probe] in
                guard let self, let probe else { return }
                attachScrollView(from: probe)
                applyPendingRestoreIfNeeded()
            }
            attachScrollView(from: probe)
            applyPendingRestoreIfNeeded()
        }

        private func isRestorePending(for currentSession: AiChatSessionID?) -> Bool {
            guard let request = restoreRequest, request.sessionID == currentSession else { return false }
            return !(appliedRestoreSessionID == request.sessionID && appliedRestoreSequence == request.sequence)
        }

        func attachScrollView(from view: NSView) {
            guard scrollView == nil else { return }
            guard let scrollView = view.enclosingScrollView ?? view.firstEnclosingScrollViewInSuperviewChain()
            else { return }

            self.scrollView = scrollView
            let clipView = scrollView.contentView
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView,
            )

            guard !isRestorePending(for: sessionID) else { return }
            onScrollOffsetChanged?(clipView.bounds.origin.y, sessionID)
        }

        func applyPendingRestoreIfNeeded() {
            guard let request = restoreRequest, request.sessionID == sessionID,
                  isRestorePending(for: sessionID), scrollView != nil else { return }
            appliedRestoreSessionID = request.sessionID
            appliedRestoreSequence = request.sequence
            isApplyingRestore = true
            DispatchQueue.main.async { [weak self] in
                self?.restore(request: request)
                DispatchQueue.main.async { [weak self] in
                    self?.restore(request: request)
                    DispatchQueue.main.async { [weak self] in
                        if self?.appliedRestoreSessionID == request.sessionID,
                           self?.appliedRestoreSequence == request.sequence
                        { self?.isApplyingRestore = false }
                    }
                }
            }
        }

        private func restore(request: AiChatTranscriptScrollRestoreRequest) {
            guard appliedRestoreSessionID == request.sessionID,
                  appliedRestoreSequence == request.sequence, let scrollView else { return }
            let clipView = scrollView.contentView
            let offsetY = min(
                max(0, request.offsetY),
                max(0, (scrollView.documentView?.bounds.height ?? 0) - clipView.bounds.height),
            )
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: offsetY))
            scrollView.reflectScrolledClipView(clipView)
            onScrollOffsetChanged?(offsetY, request.sessionID)
        }

        @objc
        private func boundsDidChange(_ notification: Notification) {
            guard !isApplyingRestore, let clipView = notification.object as? NSClipView else { return }
            onScrollOffsetChanged?(clipView.bounds.origin.y, sessionID)
        }
    }
}

private extension NSView {
    func firstEnclosingScrollViewInSuperviewChain() -> NSScrollView? {
        var view = superview
        while view != nil, !(view is NSScrollView) {
            view = view?.superview
        }
        return view as? NSScrollView
    }
}
