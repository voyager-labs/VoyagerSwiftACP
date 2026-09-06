import Foundation

/// Content Tab의 pinned/unpinned domain 의미.
/// transport와 독립적으로 drag routing이 same/opposite domain 전환을 분류할 때 사용한다.
public enum ContentTabDomain: String, Hashable, Sendable, Codable, CaseIterable {
    case unpinned
    case pinned

    /// pinned 여부로 domain을 결정한다.
    public static func domain(isPinned: Bool) -> ContentTabDomain {
        isPinned ? .pinned : .unpinned
    }
}

/// Content Tab drag drop의 semantic placement.
/// anchor는 항상 target domain의 Content Tab이며 Location은 anchor가 될 수 없다.
/// `.empty`는 target domain이 비어 있을 때의 빈 slot 표면이며 row anchor가 없어도 유효하다.
public enum ContentTabPlacement: Hashable, Sendable, Codable {
    case before(ContentTabID)
    case after(ContentTabID)
    case empty

    /// row anchor placement가 참조하는 tab ID. `.empty`는 nil이다.
    public var anchorTabID: ContentTabID? {
        switch self {
        case let .before(id): id
        case let .after(id): id
        case .empty: nil
        }
    }
}

/// 동일 창에서 frozen Content Tab batch를 반대 domain으로 전환하는 요청.
public struct ContentTabDomainTransitionRequest: Equatable, Sendable {
    public let operationID: UUID
    public let sourceWindowID: UUID
    public let sourceDomain: ContentTabDomain
    public let targetDomain: ContentTabDomain
    public let initiatingTabID: ContentTabID
    public let orderedTabIDs: [ContentTabID]
    public let placement: ContentTabPlacement
    public let source: ContentTabActionSource

    public init(
        operationID: UUID,
        sourceWindowID: UUID,
        sourceDomain: ContentTabDomain,
        targetDomain: ContentTabDomain,
        initiatingTabID: ContentTabID,
        orderedTabIDs: [ContentTabID],
        placement: ContentTabPlacement,
        source: ContentTabActionSource,
    ) {
        self.operationID = operationID
        self.sourceWindowID = sourceWindowID
        self.sourceDomain = sourceDomain
        self.targetDomain = targetDomain
        self.initiatingTabID = initiatingTabID
        self.orderedTabIDs = orderedTabIDs
        self.placement = placement
        self.source = source
    }
}

/// drag drop이 향하는 target 표면의 종류.
/// `.empty` placement와 Location/Entry/File URL을 구분하기 위해 surface로 표현한다.
public enum ContentTabDragTargetSurface: Hashable, Sendable {
    /// Content Tab domain 표면. row anchor(`.before`/`.after`)와 빈 domain slot(`.empty`) 모두 허용.
    case contentTabDomain
    /// Location/Entry/File URL 등 Content Tab이 아닌 표면. 기존 owner가 처리하거나 reject.
    case nonContentTab
}

/// Content Tab drag의 semantic routing 결과.
/// Task 1은 routing 의도만 노출하고 durable effect는 later task가 담당한다.
public enum ContentTabDragRoute: Hashable, Sendable {
    /// 동일 창 동일 domain reorder (VOY-458 batch reorder).
    case sameWindowSameDomainReorder
    /// 동일 창 반대 domain Pin/Unpin 전환 의도 (VOY-639 coordinator). placement를 함께 가져 Task 3가 before/after/empty를 적용한다.
    case sameWindowOppositeDomainTransition(placement: ContentTabPlacement)
    /// 외부 창 domain 미지정 preserve-domain batch transfer (VOY-458).
    case foreignPreserveDomainTransfer
    /// 외부 창 explicit 동일 domain placement transfer.
    case foreignExplicitSameDomainTransfer(placement: ContentTabPlacement)
    /// 외부 창 explicit 반대 domain transfer + Pin/Unpin 전환 의도.
    case foreignExplicitOppositeDomainTransfer(placement: ContentTabPlacement)
    /// Location/Entry/File URL/미지원/잘못된 anchor — semantic dispatch 0회.
    case rejected
}

/// drag drop 입력을 semantic route 분류에 전달하는 구조.
public struct ContentTabDragRouteInput: Hashable, Sendable {
    public let sourceWindowID: UUID
    public let targetWindowID: UUID
    /// source domain. v1 payload 등 알 수 없는 경우 nil이며 explicit domain 분류에서만 필요하다.
    public let sourceDomain: ContentTabDomain?
    /// nil이면 외부 창에서 preserve-domain transfer, 동일 창에서는 same-domain reorder로 해석한다.
    public let targetDomain: ContentTabDomain?
    /// explicit placement. explicit domain 분류(동일 창 반대 domain, 외부 창 explicit)에 필요하다.
    public let placement: ContentTabPlacement?
    /// drop이 향하는 target 표면. `.nonContentTab`이면 즉시 reject한다.
    public let targetSurface: ContentTabDragTargetSurface

    public init(
        sourceWindowID: UUID,
        targetWindowID: UUID,
        sourceDomain: ContentTabDomain?,
        targetDomain: ContentTabDomain?,
        placement: ContentTabPlacement?,
        targetSurface: ContentTabDragTargetSurface,
    ) {
        self.sourceWindowID = sourceWindowID
        self.targetWindowID = targetWindowID
        self.sourceDomain = sourceDomain
        self.targetDomain = targetDomain
        self.placement = placement
        self.targetSurface = targetSurface
    }
}

/// drag 입력을 semantic route로 분류하는 순수 함수 소유자.
/// drop destination은 pasteboard validation 이후 이 분류 결과로 reducer action을 정확히 한 번 보낸다.
public enum ContentTabDragRouter {
    /// routing matrix를 분류한다.
    /// Content Tab 표면이 아니면 즉시 reject하고, explicit domain 분류는 source domain과 placement를 모두 요구한다.
    public static func classify(_ input: ContentTabDragRouteInput) -> ContentTabDragRoute {
        guard input.targetSurface == .contentTabDomain else { return .rejected }
        let isForeign = input.sourceWindowID != input.targetWindowID
        if isForeign {
            guard let targetDomain = input.targetDomain else {
                return .foreignPreserveDomainTransfer
            }
            // explicit domain 분류는 source domain과 placement를 모두 가져야 한다.
            guard let sourceDomain = input.sourceDomain,
                  let placement = input.placement
            else { return .rejected }
            if targetDomain == sourceDomain {
                return .foreignExplicitSameDomainTransfer(placement: placement)
            }
            return .foreignExplicitOppositeDomainTransfer(placement: placement)
        }
        // 동일 창에서 target domain이 없으면 기존 same-domain reorder로 해석한다.
        guard let targetDomain = input.targetDomain else {
            return .sameWindowSameDomainReorder
        }
        guard let sourceDomain = input.sourceDomain else {
            return .sameWindowSameDomainReorder
        }
        if targetDomain == sourceDomain {
            return .sameWindowSameDomainReorder
        }
        // 반대 domain 전환 의도는 explicit placement를 가져야 한다.
        guard let placement = input.placement else { return .rejected }
        return .sameWindowOppositeDomainTransition(placement: placement)
    }
}

/// Content Tab drop 입력을 typed route로 바꾸는 production adapter.
/// `ContentTabDropDelegate`→SidebarView 외부 창 drop 경로가 이 projection을 호출해 정확히 하나의 route를 얻는다.
/// Task 1은 preserve-domain transfer만 dispatch하고 나머지 route의 durable effect는 later task가 담당한다.
public enum ContentTabDropRouteProjection {
    /// drop 맥락을 받아 정확히 하나의 `ContentTabDragRoute`를 반환한다.
    public static func route(
        payload: ContentTabDragPayload,
        targetWindowID: UUID,
        targetDomain: ContentTabDomain?,
        placement: ContentTabPlacement?,
        targetSurface: ContentTabDragTargetSurface,
    ) -> ContentTabDragRoute {
        ContentTabDragRouter.classify(.init(
            sourceWindowID: payload.sourceWindowID,
            targetWindowID: targetWindowID,
            sourceDomain: payload.sourceDomain,
            targetDomain: targetDomain,
            placement: placement,
            targetSurface: targetSurface,
        ))
    }
}
