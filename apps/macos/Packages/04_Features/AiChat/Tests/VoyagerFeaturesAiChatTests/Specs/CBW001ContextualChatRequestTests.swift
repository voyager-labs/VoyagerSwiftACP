import AppKit
import ComposableArchitecture
import Foundation
import Perception
import SwiftUI
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import VoyagerShared
import XCTest

private typealias IndexedSyntaxHighlightingContinuation = CheckedContinuation<
    [AiChatSyntaxHighlightingClient.Run],
    Never,
>

@MainActor
final class CBW001ContextualChatRequestTests: XCTestCase {
    // MARK: - CBW-001-open_contextual_chat

    /// CBW-001-open_contextual_chat: context 기반 채팅 진입 표면을 구성한다.
    /// 현재 context와 provider 연결 상태를 기반으로 chat shell, composer, model field가 사용자에게 보이는 초기 상태로 정렬되는지 검증합니다.
    /// - 검증 내용: setup/onAppear 이후 context summary, unconnected CTA, composer placeholder, model selector label을 확인합니다.
    /// - 사전 조건: provider 선택은 없고 current context는 reference/item/attachment를 각각 하나씩 포함합니다.
    /// - 기대 결과: 채팅 표면은 Open Settings CTA와 비활성 composer를 노출하고 submit은 불가능합니다.
    func testOpenContextualChatBuildsEntrySurfaceAndComposerContract() async {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }
        applyObservationFocusedExhaustivity(to: store)
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()

        await store.send(.setup(makeOpenSetupState(catalogRows: catalogRows, summary: summary))) { state in
            self.applyOpenSetupState(&state, catalogRows: catalogRows, summary: summary)
        }
        await store.send(.onAppear)

        assertOpenContextualChatSurface(store.state)
    }

    /// CBW-001-open_contextual_chat: 같은 composer identity의 remount는 focus를 보존한다.
    /// centered-empty와 transcript 전환에서 representable lease가 교체되어도 동일 session composer의 focus가 이어지는지 검증합니다.
    /// - 검증 내용: 새 coordinator 활성화 뒤 이전 coordinator의 end-editing과 dismantle을 처리하고 focus owner를 확인합니다.
    /// - 사전 조건: 두 입력은 같은 AiChatView scope와 displayed session identity를 사용하고 이전 입력이 focused입니다.
    /// - 기대 결과: 이전 lease의 늦은 callback은 무시되고 새 입력이 focused first responder로 유지됩니다.
    func testOpenContextualChatPreservesFocusAcrossSameComposerRemount() async {
        let focusOwner = AiChatInputFocusOwner()
        let identity = makeComposerIdentity(sessionUUID: "11111111-1111-1111-1111-111111111001")
        let oldCoordinator = makeInputCoordinator(focusOwner: focusOwner, identity: identity)
        let replacementCoordinator = makeInputCoordinator(focusOwner: focusOwner, identity: identity)
        let window = NSWindow()
        let container = NSView()
        let oldTextView = AiChatInputTextView.AttachmentDroppingTextView()
        let replacementTextView = AiChatInputTextView.AttachmentDroppingTextView()
        let oldScrollView = NSScrollView()
        let replacementScrollView = NSScrollView()
        oldScrollView.documentView = oldTextView
        replacementScrollView.documentView = replacementTextView
        container.addSubview(oldScrollView)
        container.addSubview(replacementScrollView)
        window.contentView = container
        oldCoordinator.activate(textView: oldTextView, scrollView: oldScrollView, identity: identity)
        XCTAssertEqual(oldTextView.composerIdentity, identity)
        focusOwner.requestFocus(for: identity)
        XCTAssertTrue(window.makeFirstResponder(oldTextView))

        oldCoordinator.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: oldTextView))
        replacementCoordinator.activate(
            textView: replacementTextView,
            scrollView: replacementScrollView,
            identity: identity,
        )
        XCTAssertEqual(replacementTextView.composerIdentity, identity)
        AiChatInputTextView.dismantleNSView(oldScrollView, coordinator: oldCoordinator)
        XCTAssertTrue(window.makeFirstResponder(replacementTextView))
        await drainMainQueue()

        XCTAssertIdentical(window.firstResponder, replacementTextView)
        XCTAssertTrue(focusOwner.isFocused(for: identity))
    }

    /// CBW-001-open_contextual_chat: 독립 AiChatView A의 rerender는 B composer focus를 침범하지 않는다.
    /// Content와 Inspector가 각자 focus owner를 가져도 window의 responder identity로 cross-view acquisition을 차단하는지 검증합니다.
    /// - 검증 내용: 서로 다른 owner/scope의 A→B 전환 뒤 A를 다시 activate·schedule하고 end-editing을 처리합니다.
    /// - 사전 조건: 두 composer는 같은 session을 표시하지만 독립 AiChatView scope와 focus owner를 사용합니다.
    /// - 기대 결과: A rerender는 B를 탈취하지 않고 A owner만 clear되며 B owner와 first responder는 유지됩니다.
    func testOpenContextualChatPreventsIndependentComposerFromStealingFocusAfterRerender() async {
        let focusOwnerA = AiChatInputFocusOwner()
        let focusOwnerB = AiChatInputFocusOwner()
        let sessionUUID = "11111111-1111-1111-1111-111111111002"
        let identityA = makeComposerIdentity(
            sessionUUID: sessionUUID,
            scopeID: makeUUID("22222222-2222-2222-2222-222222222001"),
        )
        let identityB = makeComposerIdentity(
            sessionUUID: sessionUUID,
            scopeID: makeUUID("22222222-2222-2222-2222-222222222002"),
        )
        let coordinatorA = makeInputCoordinator(focusOwner: focusOwnerA, identity: identityA)
        let coordinatorB = makeInputCoordinator(focusOwner: focusOwnerB, identity: identityB)
        let window = NSWindow()
        let container = NSView()
        let textViewA = AiChatInputTextView.AttachmentDroppingTextView()
        let textViewB = AiChatInputTextView.AttachmentDroppingTextView()
        let scrollViewA = NSScrollView()
        let scrollViewB = NSScrollView()
        scrollViewA.documentView = textViewA
        scrollViewB.documentView = textViewB
        container.addSubview(scrollViewA)
        container.addSubview(scrollViewB)
        window.contentView = container
        coordinatorA.activate(textView: textViewA, scrollView: scrollViewA, identity: identityA)
        focusOwnerA.requestFocus(for: identityA)
        XCTAssertTrue(window.makeFirstResponder(textViewA))

        coordinatorB.activate(textView: textViewB, scrollView: scrollViewB, identity: identityB)
        focusOwnerB.requestFocus(for: identityB)
        XCTAssertTrue(window.makeFirstResponder(textViewB))
        XCTAssertEqual(textViewA.composerIdentity, identityA)
        XCTAssertEqual(textViewB.composerIdentity, identityB)
        XCTAssertNotEqual(identityA, identityB)

        coordinatorA.activate(textView: textViewA, scrollView: scrollViewA, identity: identityA)
        coordinatorA.scheduleFocusAcquisition(for: textViewA)
        await drainMainQueue()

        XCTAssertIdentical(window.firstResponder, textViewB)
        XCTAssertTrue(focusOwnerA.isFocused(for: identityA))
        XCTAssertTrue(focusOwnerB.isFocused(for: identityB))

        coordinatorA.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: textViewA))
        await drainMainQueue()
        coordinatorA.scheduleFocusAcquisition(for: textViewA)
        await drainMainQueue()

        XCTAssertIdentical(window.firstResponder, textViewB)
        XCTAssertFalse(focusOwnerA.isFocused(for: identityA))
        XCTAssertTrue(focusOwnerB.isFocused(for: identityB))
    }

    /// CBW-001-open_contextual_chat: dismantle된 입력의 예약 focus 획득은 교체 responder를 침범하지 않는다.
    /// representable 수명이 끝난 뒤 실행되는 main queue 작업이 obsolete NSTextView를 다시 first responder로 만들지 않는지 검증합니다.
    /// - 검증 내용: focus 예약, dismantle, 교체 responder 지정, main queue drain 뒤 실제 first responder를 확인합니다.
    /// - 사전 조건: 현재 identity가 focus를 소유하고 이전 입력과 교체 responder가 같은 window에 연결되어 있습니다.
    /// - 기대 결과: 이전 입력의 예약 작업은 무효화되고 focus owner는 inactive이며 교체 responder가 유지됩니다.
    func testOpenContextualChatRejectsScheduledFocusAfterInputDismantle() async {
        let focusOwner = AiChatInputFocusOwner()
        let identity = makeComposerIdentity(sessionUUID: "11111111-1111-1111-1111-111111111004")
        let coordinator = makeInputCoordinator(focusOwner: focusOwner, identity: identity)
        let window = NSWindow()
        let container = NSView()
        let staleTextView = AiChatInputTextView.AttachmentDroppingTextView()
        let replacementTextView = AiChatInputTextView.AttachmentDroppingTextView()
        let scrollView = NSScrollView()
        scrollView.documentView = staleTextView
        container.addSubview(scrollView)
        container.addSubview(replacementTextView)
        window.contentView = container
        coordinator.activate(textView: staleTextView, scrollView: scrollView, identity: identity)
        focusOwner.requestFocus(for: identity)

        coordinator.scheduleFocusAcquisition(for: staleTextView)
        AiChatInputTextView.dismantleNSView(scrollView, coordinator: coordinator)
        XCTAssertTrue(window.makeFirstResponder(replacementTextView))
        await drainMainQueue()

        XCTAssertIdentical(window.firstResponder, replacementTextView)
        XCTAssertNil(coordinator.textView)
        XCTAssertNil(coordinator.scrollView)
        XCTAssertFalse(focusOwner.isFocused(for: identity))
    }

    /// CBW-001-open_contextual_chat: active composer의 실제 resign은 해당 identity focus를 해제한다.
    /// stale callback 방어가 현재 lease에서 발생한 정상적인 focus 이탈 동작을 보존하는지 검증합니다.
    /// - 검증 내용: active 입력에서 일반 responder로 전환한 뒤 end-editing callback과 main queue를 처리합니다.
    /// - 사전 조건: 현재 identity와 coordinator lease가 focused 입력을 소유합니다.
    /// - 기대 결과: 일반 responder가 유지되고 active identity의 focus는 false가 됩니다.
    func testOpenContextualChatClearsFocusAfterGenuineInputResign() async {
        let focusOwner = AiChatInputFocusOwner()
        let identity = makeComposerIdentity(sessionUUID: "11111111-1111-1111-1111-111111111005")
        let coordinator = makeInputCoordinator(focusOwner: focusOwner, identity: identity)
        let window = NSWindow()
        let container = NSView()
        let textView = AiChatInputTextView.AttachmentDroppingTextView()
        let scrollView = NSScrollView()
        let nextResponder = CBW001FocusableView()
        scrollView.documentView = textView
        container.addSubview(scrollView)
        container.addSubview(nextResponder)
        window.contentView = container
        coordinator.activate(textView: textView, scrollView: scrollView, identity: identity)
        XCTAssertEqual(textView.composerIdentity, identity)
        focusOwner.requestFocus(for: identity)
        XCTAssertTrue(window.makeFirstResponder(textView))

        XCTAssertTrue(window.makeFirstResponder(nextResponder))
        coordinator.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: textView))
        await drainMainQueue()

        XCTAssertIdentical(window.firstResponder, nextResponder)
        XCTAssertFalse(focusOwner.isFocused(for: identity))
    }

    /// CBW-001-open_contextual_chat: 이미 열린 transcript 검색을 다시 열면 새로운 focus 요청만 만든다.
    /// 반복 Cmd+F가 기존 검색·session·scroll 문맥과 최초 close 시 입력 focus 복원 의도를 보존하는지 검증합니다.
    /// - 검증 내용: focus revision의 wrapping 증가와 나머지 전체 state의 불변을 확인합니다.
    /// - 사전 조건: 검색창이 표시되고 query, match, navigation, session, scroll 상태가 채워져 있습니다.
    /// - 기대 결과: presentation edge는 유지되고 focus revision만 UInt64.max에서 0, 다시 1로 증가합니다.
    func testOpenContextualChatRepeatedTranscriptSearchOpenRequestsFreshFocusOnly() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        var initialState = AiChatFeature.State(
            mode: .chat,
            sessionList: .init(query: "session query"),
            sessionID: sessionID,
            transcriptScrollOffsets: [sessionID: 42],
        )
        initialState.transcriptSearch = .init(
            isPresented: true,
            query: "needle",
            matchCount: 3,
            currentMatchOrdinal: 2,
            status: .matches,
            navigationRevision: 7,
            focusRevision: .max,
        )
        let store = makeTranscriptSearchStore(initialState)

        XCTAssertEqual(AiChatTranscriptSearchState().focusRevision, 0)
        var expectedState = initialState
        expectedState.transcriptSearch.focusRevision = 0

        await store.send(.transcriptSearchOpened) { state in
            state = expectedState
        }

        expectedState.transcriptSearch.focusRevision = 1
        await store.send(.transcriptSearchOpened) { state in
            state = expectedState
        }
    }

    /// CBW-001-open_contextual_chat: transcript 검색 icon control은 활성 hover에서만 compact 배경을 표시한다.
    /// 이전·다음·닫기 control이 동일한 크기와 symbol 의도를 유지하면서 disabled 탐색 control에는 hover 배경을 노출하지 않는지 검증합니다.
    /// - 검증 내용: 26pt hit area, 11pt semibold symbol, compact control radius, light/dark control hover fill과 enabled
    /// gating을 확인합니다.
    /// - 사전 조건: package-internal transcript search button style에 hover·enabled·color scheme 조합을 전달합니다.
    /// - 기대 결과: 활성 hover는 정확한 Voyager control hover token을 반환하고 rest 또는 disabled hover는 배경을 반환하지 않습니다.
    func testOpenContextualChatTranscriptSearchControlsUseEnabledCompactHoverPolicy() {
        let style = AiChatTranscriptSearchButtonStyle()

        XCTAssertEqual(style.size, 26)
        XCTAssertEqual(style.symbolSize, 11)
        XCTAssertEqual(style.symbolWeight, Font.Weight.semibold)
        XCTAssertEqual(style.cornerRadius, VoyagerDS.Radius.control)
        XCTAssertEqual(
            style.hoverFill(isHovered: true, isEnabled: true, colorScheme: .light),
            VoyagerDS.Interaction.controlHoverFill(for: .light),
        )
        XCTAssertEqual(
            style.hoverFill(isHovered: true, isEnabled: true, colorScheme: .dark),
            VoyagerDS.Interaction.controlHoverFill(for: .dark),
        )
        XCTAssertNil(style.hoverFill(isHovered: false, isEnabled: true, colorScheme: .light))
        XCTAssertNil(style.hoverFill(isHovered: true, isEnabled: false, colorScheme: .light))
        XCTAssertNil(style.hoverFill(isHovered: true, isEnabled: false, colorScheme: .dark))
    }

    /// CBW-001-open_contextual_chat: plain message match는 안정적인 Character offset descriptor를 반환한다.
    /// 현재 transcript의 일반 텍스트 검색 기반이 UI 객체 수명과 무관한 값으로 표현되는지 검증합니다.
    /// - 검증 내용: message row discriminator, block index, Character offset range를 확인합니다.
    /// - 사전 조건: 세 번째 transcript message의 단일 rendered block에 plain text가 있습니다.
    /// - 기대 결과: match는 message index 2, block index 0, Character offset 6..<11을 반환합니다.
    func testOpenContextualChatMatchesPlainRenderedTextWithStableDescriptorValues() {
        let matches = AiChatRenderedTextMatcher.matches(
            query: "world",
            transcriptRow: .message(index: 2),
            renderedBlocks: ["Hello world"],
        )

        XCTAssertEqual(matches, [
            AiChatRenderedTextMatchDescriptor(
                transcriptRow: .message(index: 2),
                blockIndex: 0,
                characterOffsets: 6 ..< 11,
            ),
        ])
    }

    /// CBW-001-open_contextual_chat: assistant Markdown은 marker가 제거된 표시 block 텍스트에서 match한다.
    /// 사용자가 보는 heading, inline style, list, code 문자열만 검색 대상이 되는지 검증합니다.
    /// - 검증 내용: Markdown projection별 block index와 marker query의 match 부재를 확인합니다.
    /// - 사전 조건: heading, bold paragraph, bullet, numbered item, fenced code를 포함한 assistant 응답이 있습니다.
    /// - 기대 결과: 표시 문자열은 각 block에서 match하고 raw Markdown marker는 match하지 않습니다.
    func testOpenContextualChatMatchesRenderedMarkdownBlocksWithoutRawMarkers() {
        let markdown = """
        # Heading

        Use **bold** text

        - First bullet
        1. Numbered item

        ```swift
        let value = 1
        ```
        """
        let renderedBlocks = AiChatMarkdownParser.parse(markdown).renderedBlocks
        let row = AiChatTranscriptRowDiscriminator.streamingAssistant

        XCTAssertEqual(renderedBlocks, [
            "Heading",
            "Use bold text",
            "First bullet",
            "Numbered item",
            "let value = 1\n",
        ])
        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "Heading", transcriptRow: row, renderedBlocks: renderedBlocks),
            [.init(transcriptRow: row, blockIndex: 0, characterOffsets: 0 ..< 7)],
        )
        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "bold", transcriptRow: row, renderedBlocks: renderedBlocks),
            [.init(transcriptRow: row, blockIndex: 1, characterOffsets: 4 ..< 8)],
        )
        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "First", transcriptRow: row, renderedBlocks: renderedBlocks),
            [.init(transcriptRow: row, blockIndex: 2, characterOffsets: 0 ..< 5)],
        )
        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "Numbered", transcriptRow: row, renderedBlocks: renderedBlocks),
            [.init(transcriptRow: row, blockIndex: 3, characterOffsets: 0 ..< 8)],
        )
        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "value", transcriptRow: row, renderedBlocks: renderedBlocks),
            [.init(transcriptRow: row, blockIndex: 4, characterOffsets: 4 ..< 9)],
        )

        for marker in ["#", "**", "- ", "1.", "```"] {
            XCTAssertTrue(
                AiChatRenderedTextMatcher.matches(query: marker, transcriptRow: row, renderedBlocks: renderedBlocks)
                    .isEmpty,
                "Raw Markdown marker \(marker) must not be searchable",
            )
        }
    }

    /// CBW-001-open_contextual_chat: Unicode canonical equivalent와 대소문자 차이를 동일한 rendered match로 취급한다.
    /// 한글, 일본어, emoji, 결합문자와 반복 문자열에서 Character offset mapping이 유지되는지 검증합니다.
    /// - 검증 내용: case-insensitive 반복 match 순서와 NFC query 대 NFD text의 offset을 확인합니다.
    /// - 사전 조건: 같은 block에 대소문자가 다른 Echo 세 개가 있고 다음 block에 한글·일본어·emoji·NFD café가 있습니다.
    /// - 기대 결과: 모든 match는 표시 순서와 원본 rendered text의 Character offset을 보존합니다.
    func testOpenContextualChatMatchesUnicodeCanonicallyAndCaseInsensitivelyInOrder() {
        let row = AiChatTranscriptRowDiscriminator.message(index: 4)
        let renderedBlocks = ["Echo echo ECHO", "한글 日本語 👩‍💻 cafe\u{301}"]

        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "echo", transcriptRow: row, renderedBlocks: renderedBlocks),
            [
                .init(transcriptRow: row, blockIndex: 0, characterOffsets: 0 ..< 4),
                .init(transcriptRow: row, blockIndex: 0, characterOffsets: 5 ..< 9),
                .init(transcriptRow: row, blockIndex: 0, characterOffsets: 10 ..< 14),
            ],
        )
        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "CAFÉ", transcriptRow: row, renderedBlocks: renderedBlocks),
            [.init(transcriptRow: row, blockIndex: 1, characterOffsets: 9 ..< 13)],
        )
        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "한글", transcriptRow: row, renderedBlocks: renderedBlocks),
            [.init(transcriptRow: row, blockIndex: 1, characterOffsets: 0 ..< 2)],
        )
        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "日本語", transcriptRow: row, renderedBlocks: renderedBlocks),
            [.init(transcriptRow: row, blockIndex: 1, characterOffsets: 3 ..< 6)],
        )
        XCTAssertEqual(
            AiChatRenderedTextMatcher.matches(query: "👩‍💻", transcriptRow: row, renderedBlocks: renderedBlocks),
            [.init(transcriptRow: row, blockIndex: 1, characterOffsets: 7 ..< 8)],
        )
    }

    /// CBW-001-open_contextual_chat: query는 rendered Markdown block 경계를 넘어 match하지 않는다.
    /// block 단위 renderer를 유지하면서 인접 block의 끝과 시작을 하나의 결과로 합치지 않는지 검증합니다.
    /// - 검증 내용: cross-block query와 빈 query가 descriptor를 만들지 않는지 확인합니다.
    /// - 사전 조건: 첫 block은 boundary로 끝나고 다음 block은 crossing으로 시작합니다.
    /// - 기대 결과: 두 block을 잇는 query와 빈 query 모두 match가 없습니다.
    func testOpenContextualChatDoesNotMatchAcrossRenderedBlockBoundariesOrEmptyQuery() {
        let row = AiChatTranscriptRowDiscriminator.message(index: 0)
        let renderedBlocks = ["boundary", "crossing"]

        XCTAssertTrue(
            AiChatRenderedTextMatcher.matches(
                query: "arycro",
                transcriptRow: row,
                renderedBlocks: renderedBlocks,
            ).isEmpty,
        )
        XCTAssertTrue(
            AiChatRenderedTextMatcher.matches(
                query: "",
                transcriptRow: row,
                renderedBlocks: renderedBlocks,
            ).isEmpty,
        )
    }

    // MARK: - CBW-001-render_assistant_markdown

    /// CBW-001-render_assistant_markdown: output block은 편집 불가 selectable intrinsic AppKit text surface를 구성한다.
    /// assistant block 하나가 child scroll이나 중복 accessibility owner 없이 폭에 맞춰 읽기 전용 텍스트를 노출하는지 검증합니다.
    /// - 검증 내용: editable/selectable/background/scroller/width tracking/intrinsic height와 accessibility owner를 확인합니다.
    /// - 사전 조건: 여러 줄 attributed plain output을 240pt 폭의 hosted NSWindow에 설치합니다.
    /// - 기대 결과: text view만 static-text accessibility element이고 scroll view는 intrinsic document height를 반환합니다.
    func testRenderAssistantMarkdownConfiguresReadOnlySelectableIntrinsicOutput() {
        let harness = makeSelectableOutputHarness(text: "첫 줄\n두 번째 줄 👩‍💻")
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let scrollView = harness.coordinator.scrollView

        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.drawsBackground)
        XCTAssertFalse(scrollView.drawsBackground)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, false)
        XCTAssertEqual(textView.frame.width, scrollView.contentSize.width, accuracy: 0.5)
        let wideHeight = scrollView.intrinsicContentSize.height
        XCTAssertGreaterThan(wideHeight, 0)
        scrollView.frame.size.width = 100
        harness.coordinator.update(
            blockID: .init(rawValue: "hosted-block"),
            attributedText: NSAttributedString(string: textView.string),
        )
        XCTAssertEqual(textView.frame.width, scrollView.contentSize.width, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(scrollView.intrinsicContentSize.height, wideHeight)
        XCTAssertFalse(scrollView.isAccessibilityElement())
        XCTAssertTrue(textView.isAccessibilityElement())
        XCTAssertEqual(textView.accessibilityRole(), NSAccessibility.Role.staticText)
        XCTAssertEqual(textView.accessibilityValue(), textView.string)
    }

    /// CBW-001-render_assistant_markdown: mouse와 keyboard selection은 같은 typed UTF-16 substring을 복사한다.
    /// NFD와 emoji를 포함한 plain projection에서 포인터 범위와 keyboard 확장 범위가 동일한 사용자 문자를 가리키는지 검증합니다.
    /// - 검증 내용: Task 1 Character→UTF-16 변환, keyboard selection, native copy:, block-local selectAll:을 확인합니다.
    /// - 사전 조건: hosted output block이 first responder이고 `café 👩‍💻`의 typed SearchRange가 준비되어 있습니다.
    /// - 기대 결과: 두 selection substring이 같고 copy pasteboard에는 exact substring, selectAll에는 현재 block만 들어갑니다.
    func testRenderAssistantMarkdownUsesIdenticalMouseAndKeyboardSelectionForNativeCopy() throws {
        let text = "앞 cafe\u{301} 👩‍💻 뒤"
        let selectedText = "cafe\u{301} 👩‍💻"
        let harness = makeSelectableOutputHarness(text: text)
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let stringRange = try XCTUnwrap(text.range(of: selectedText))
        let searchRange = AiChatMarkdownDocument.SearchRange(stringRange, in: text)
        let selection = try XCTUnwrap(searchRange.plainSelectionRange(in: text))

        textView.setSelectedRange(selection.nsRange)
        let mouseSubstring = try selectedSubstring(in: textView)
        textView.setSelectedRange(NSRange(location: selection.utf16Location, length: 0))
        for _ in searchRange.characterOffsets {
            textView.moveRightAndModifySelection(nil as Any?)
        }
        let keyboardSubstring = try selectedSubstring(in: textView)

        XCTAssertEqual(mouseSubstring, selectedText)
        XCTAssertEqual(keyboardSubstring, mouseSubstring)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        textView.copy(nil as Any?)
        XCTAssertEqual(pasteboard.string(forType: .string), selectedText)
        textView.selectAll(nil as Any?)
        XCTAssertEqual(try selectedSubstring(in: textView), text)
    }

    /// CBW-001-render_assistant_markdown: output responder는 Copy/Select All만 소유하고 편집·history action은 fallback한다.
    /// read-only assistant block이 FileManager 명령이나 Undo/Redo를 text editing action으로 가로채지 않는지 검증합니다.
    /// - 검증 내용: selector routing, Cut/Paste no-op, empty-state fallback과 default Services requestor를 확인합니다.
    /// - 사전 조건: 선택된 output text 뒤에 Copy/Select All/Undo selector를 처리하는 probe responder가 연결되어 있습니다.
    /// - 기대 결과: 유효한 Copy/Select All만 output target이고 empty/편집/history action은 fallback responder가 받습니다.
    func testRenderAssistantMarkdownRoutesOnlyReadOnlyTextResponderCommands() {
        let harness = makeSelectableOutputHarness(text: "선택 가능한 output")
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let original = textView.string
        let fallback = SelectableOutputFallbackResponder()
        let originalNextResponder = textView.nextResponder
        defer { textView.nextResponder = originalNextResponder }
        textView.nextResponder = fallback
        textView.selectAll(nil as Any?)

        XCTAssertTrue(textView.responds(to: #selector(NSText.copy(_:))))
        XCTAssertTrue(textView.responds(to: #selector(NSText.selectAll(_:))))
        for selector in [
            #selector(NSText.cut(_:)), #selector(NSText.paste(_:)), NSSelectorFromString("undo:"),
            NSSelectorFromString("redo:"),
        ] {
            XCTAssertFalse(textView.responds(to: selector))
        }
        textView.cut(nil as Any?)
        textView.paste(nil as Any?)
        XCTAssertEqual(textView.string, original)
        let defaultMenu = textView.menu
        XCTAssertEqual(defaultMenu?.items.contains { $0.action == #selector(NSText.copy(_:)) }, true)
        XCTAssertEqual(defaultMenu?.items.contains { $0.submenu != nil }, true)
        let servicesRequestor = textView.validRequestor(
            forSendType: NSPasteboard.PasteboardType.string,
            returnType: nil,
        ) as AnyObject?
        XCTAssertNotNil(servicesRequestor)
        XCTAssertTrue(textView.tryToPerform(NSSelectorFromString("undo:"), with: nil as Any?))
        XCTAssertTrue(fallback.didReceiveUndo)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertFalse(textView.responds(to: #selector(NSText.copy(_:))))
        XCTAssertTrue(textView.tryToPerform(#selector(NSText.copy(_:)), with: nil as Any?))
        XCTAssertTrue(fallback.didReceiveCopy)
        XCTAssertTrue(textView.responds(to: #selector(NSText.selectAll(_:))))

        harness.coordinator.update(
            blockID: .init(rawValue: "hosted-block"),
            attributedText: NSAttributedString(string: ""),
        )
        XCTAssertFalse(textView.responds(to: #selector(NSText.selectAll(_:))))
        XCTAssertTrue(textView.tryToPerform(#selector(NSText.selectAll(_:)), with: nil as Any?))
        XCTAssertTrue(fallback.didReceiveSelectAll)
    }

    /// CBW-001-render_assistant_markdown: stable block update는 selection과 first responder를 보존한다.
    /// streaming attributed update가 같은 logical block의 선택 문맥을 잃거나 responder를 다른 surface로 이동시키지 않는지 검증합니다.
    /// - 검증 내용: stable BlockID snapshot, typed selection 복원과 first-responder 상태를 확인합니다.
    /// - 사전 조건: NFD+emoji substring이 선택된 block에 같은 identity의 suffix attributed update가 도착합니다.
    /// - 기대 결과: update 뒤에도 exact selected plain substring과 first responder가 유지됩니다.
    func testRenderAssistantMarkdownPreservesSelectionAndFirstResponderForStableBlockUpdate() throws {
        let initial = "앞 cafe\u{301} 👩‍💻 뒤"
        let selected = "cafe\u{301} 👩‍💻"
        let blockID = AiChatMarkdownDocument.BlockID(rawValue: "stable-block")
        let harness = makeSelectableOutputHarness(text: initial, blockID: blockID)
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let range = try XCTUnwrap(initial.range(of: selected))
        let typedRange = try XCTUnwrap(
            AiChatMarkdownDocument.SearchRange(range, in: initial).plainSelectionRange(in: initial),
        )
        textView.setSelectedRange(typedRange.nsRange)
        XCTAssertTrue(harness.window.makeFirstResponder(textView))

        harness.coordinator.update(
            blockID: blockID,
            attributedText: NSAttributedString(string: initial + " 추가"),
        )

        XCTAssertEqual(try selectedSubstring(in: textView), selected)
        XCTAssertIdentical(harness.window.firstResponder, textView)
    }

    /// CBW-001-render_assistant_markdown: shortened content는 stale selection을 grapheme boundary로 clamp한다.
    /// streaming 교체가 이전 UTF-16 range를 emoji 내부에 놓아도 crash하거나 잘못된 scalar 일부를 선택하지 않는지 검증합니다.
    /// - 검증 내용: Task 1 clamp conversion, valid restored NSRange와 identity-change discard를 확인합니다.
    /// - 사전 조건: ASCII `2345` selection의 UTF-16 위치에 짧아진 `A👩‍💻B` block과 새 identity update가 순서대로 도착합니다.
    /// - 기대 결과: stable identity는 emoji 전체로 clamp하고 새 identity는 빈 selection으로 deterministic discard합니다.
    func testRenderAssistantMarkdownClampsShortenedSelectionAndDiscardsChangedIdentity() throws {
        let blockID = AiChatMarkdownDocument.BlockID(rawValue: "shortened-block")
        let harness = makeSelectableOutputHarness(text: "A123456789", blockID: blockID)
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let oldRange = try XCTUnwrap(textView.string.range(of: "2345"))
        let oldSelection = try XCTUnwrap(
            AiChatMarkdownDocument.SearchRange(oldRange, in: textView.string)
                .plainSelectionRange(in: textView.string),
        )
        textView.setSelectedRange(oldSelection.nsRange)

        harness.coordinator.update(blockID: blockID, attributedText: NSAttributedString(string: "A👩‍💻B"))

        XCTAssertEqual(try selectedSubstring(in: textView), "👩‍💻")
        XCTAssertNotNil(
            AiChatMarkdownDocument.PlainSelectionRange(textView.selectedRange())?
                .searchRange(in: textView.string, invalidRangePolicy: .discard),
        )
        harness.coordinator.update(
            blockID: AiChatMarkdownDocument.BlockID(rawValue: "replacement-block"),
            attributedText: NSAttributedString(string: "교체"),
        )
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    /// CBW-001-render_assistant_markdown: Markdown 원문 UTF-8과 source range를 lossless하게 보존한다.
    /// assistant 응답의 CRLF와 Unicode bytes가 block raw slice 재조합 과정에서 바뀌지 않는지 검증합니다.
    /// - 검증 내용: document raw UTF-8, block raw slice/source range와 raw reconstruction을 확인합니다.
    /// - 사전 조건: blockquote, Unicode table, explicit Swift fence가 CRLF로 연결된 mixed Markdown 원문이 있습니다.
    /// - 기대 결과: 원문 bytes와 block 재조합 및 각 source range slice가 입력과 정확히 같습니다.
    func testRenderAssistantMarkdownPreservesRawSourceAndTypedSourceRanges() throws {
        let rawSlices = [
            "> 인용 `code`\r\n\r\n",
            "| 이름 | 값 |\r\n| --- | --- |\r\n| 검색 | 👩‍💻 |\r\n\r\n",
            "```Swift\r\nlet café = \"e\u{301}\"\r\n```\r\n",
        ]
        let source = rawSlices.joined()
        var utf8Cursor = 0
        let blocks = try rawSlices.enumerated().map { index, rawSlice in
            defer { utf8Cursor += rawSlice.utf8.count }
            return try XCTUnwrap(AiChatMarkdownDocument.Block(
                id: .init(rawValue: "raw-\(index)"),
                kind: .paragraph,
                sourceRange: .init(utf8Offsets: utf8Cursor ..< utf8Cursor + rawSlice.utf8.count),
                rawSlice: rawSlice,
                projections: .init(rendered: rawSlice, search: rawSlice, plain: rawSlice),
            ))
        }
        let document = AiChatMarkdownDocument(rawSource: source, blocks: blocks)

        XCTAssertEqual(document.rawUTF8, Array(source.utf8))
        XCTAssertEqual(document.reconstructedRawSource, source)
        XCTAssertEqual(document.blocks.map(\.rawSlice), rawSlices)
        XCTAssertEqual(document.blocks.compactMap { $0.sourceRange.rawSlice(in: source) }, rawSlices)
    }

    /// CBW-001-render_assistant_markdown: block intent와 목적별 projection을 서로 독립적으로 보존한다.
    /// blockquote marker, table delimiter, inline-code marker가 표시·검색·plain-copy 문자열로 섞이지 않는지 검증합니다.
    /// - 검증 내용: block kind, inline-code intent, rendered/search/plain projection을 확인합니다.
    /// - 사전 조건: inline code가 있는 blockquote와 2행 Unicode table block 값이 준비되어 있습니다.
    /// - 기대 결과: table plain은 tab/newline이고 blockquote plain은 `>` marker 없이 유지됩니다.
    func testRenderAssistantMarkdownKeepsBlockIntentsAndIndependentProjections() throws {
        let blockquoteRaw = "> 인용 `code`"
        let tableRaw = "| 이름 | 값 |\n| --- | --- |\n| 검색 | 👩‍💻 |"
        let blockquote = try XCTUnwrap(AiChatMarkdownDocument.Block(
            id: .init(rawValue: "blockquote"),
            kind: .blockquote,
            sourceRange: .init(utf8Offsets: 0 ..< blockquoteRaw.utf8.count),
            rawSlice: blockquoteRaw,
            projections: .init(rendered: "인용 code", search: "인용 code", plain: "인용 code"),
            inlineIntents: [.code(.init(characterOffsets: 3 ..< 7))],
        ))
        let table = try XCTUnwrap(AiChatMarkdownDocument.Block(
            id: .init(rawValue: "table"),
            kind: .table,
            sourceRange: .init(utf8Offsets: 0 ..< tableRaw.utf8.count),
            rawSlice: tableRaw,
            projections: .init(
                rendered: "이름 값 검색 👩‍💻",
                search: "이름 값 검색 👩‍💻",
                plain: "이름\t값\n검색\t👩‍💻",
            ),
        ))
        let document = AiChatMarkdownDocument(rawSource: blockquoteRaw + tableRaw, blocks: [blockquote, table])

        XCTAssertEqual(blockquote.kind, .blockquote)
        XCTAssertEqual(table.kind, .table)
        XCTAssertEqual(blockquote.inlineIntents, [.code(.init(characterOffsets: 3 ..< 7))])
        XCTAssertEqual(document.renderedBlocks, ["인용 code", "이름 값 검색 👩‍💻"])
        XCTAssertEqual(document.searchBlocks, ["인용 code", "이름 값 검색 👩‍💻"])
        XCTAssertEqual(document.plainText, "인용 code\n이름\t값\n검색\t👩‍💻")
    }

    /// CBW-001-render_assistant_markdown: code payload와 언어 metadata를 fence 표시 문자열에서 분리한다.
    /// code-only copy와 향후 highlighting이 원본 label이나 fence를 payload로 오인하지 않는지 검증합니다.
    /// - 검증 내용: code payload, original language, normalized language, search/plain projection의 label 제외를 확인합니다.
    /// - 사전 조건: 대소문자가 보존된 `Swift` label과 CRLF code body를 가진 code block이 있습니다.
    /// - 기대 결과: payload에는 fence와 label이 없고 원본·정규화 언어는 별도 필드에 유지됩니다.
    func testRenderAssistantMarkdownSeparatesCodePayloadAndLanguageMetadata() throws {
        let raw = "```Swift\r\nprint(\"한글 👩‍💻\")\r\n```"
        let payload = "print(\"한글 👩‍💻\")\r\n"
        let block = try XCTUnwrap(AiChatMarkdownDocument.Block(
            id: .init(rawValue: "code-language"),
            kind: .code,
            sourceRange: .init(utf8Offsets: 0 ..< raw.utf8.count),
            rawSlice: raw,
            projections: .init(rendered: payload, search: payload, plain: payload),
            code: .init(payload: payload, originalLanguage: "Swift", normalizedLanguage: "swift"),
        ))

        XCTAssertEqual(block.code?.payload, payload)
        XCTAssertEqual(block.code?.originalLanguage, "Swift")
        XCTAssertEqual(block.code?.normalizedLanguage, "swift")
        XCTAssertFalse(block.projections.search.contains("Swift"))
        XCTAssertFalse(block.projections.plain.contains("```"))
    }

    /// CBW-001-render_assistant_markdown: Character 검색 범위를 UTF-16 selection 범위로 lossless 변환한다.
    /// AppKit과 Swift 문자열이 NFC, NFD, 한글, emoji/ZWJ에서 같은 사용자 문자를 가리키는지 검증합니다.
    /// - 검증 내용: String.Index 기반 생성, Character→UTF-16→Character round trip과 exact substring을 확인합니다.
    /// - 사전 조건: NFC `é`, NFD `e\u{301}`, 한글, `👩‍💻` ZWJ가 각각 포함된 문자열이 있습니다.
    /// - 기대 결과: 모든 유효 범위가 원래 substring과 동일한 typed range로 돌아옵니다.
    func testRenderAssistantMarkdownRoundTripsUnicodeSearchAndSelectionRanges() throws {
        let samples = ["é", "e\u{301}", "한글", "👩‍💻", "앞👩‍💻한글e\u{301}뒤"]

        for text in samples {
            let stringRange = text.startIndex ..< text.endIndex
            let searchRange = AiChatMarkdownDocument.SearchRange(stringRange, in: text)
            let selectionRange = try XCTUnwrap(searchRange.plainSelectionRange(in: text))
            let roundTrip = try XCTUnwrap(selectionRange.searchRange(in: text, invalidRangePolicy: .discard))

            XCTAssertEqual(searchRange.substring(in: text), text)
            XCTAssertEqual(roundTrip, searchRange)
            XCTAssertEqual(roundTrip.substring(in: text), text)
            XCTAssertEqual(selectionRange.utf16Length, text.utf16.count)
        }
    }

    /// CBW-001-render_assistant_markdown: stale UTF-16 selection은 grapheme boundary로 clamp하거나 폐기한다.
    /// streaming update로 selection이 surrogate/ZWJ 중간 또는 새 문자열 밖을 가리켜도 crash하지 않는지 검증합니다.
    /// - 검증 내용: midpoint discard, nearest-boundary clamp, out-of-bounds clamp/discard 결과를 확인합니다.
    /// - 사전 조건: `A👩‍💻B`의 emoji UTF-16 내부와 문자열 끝을 넘는 stale range가 있습니다.
    /// - 기대 결과: discard는 nil이고 clamp는 emoji 전체 또는 빈 end selection을 deterministic하게 반환합니다.
    func testRenderAssistantMarkdownClampsOrDiscardsStaleUTF16SelectionRanges() throws {
        let text = "A👩‍💻B"
        let midpoint = AiChatMarkdownDocument.PlainSelectionRange(utf16Location: 2, utf16Length: 1)
        let beyondEnd = AiChatMarkdownDocument.PlainSelectionRange(utf16Location: 99, utf16Length: 10)

        XCTAssertNil(midpoint.searchRange(in: text, invalidRangePolicy: .discard))
        let clampedEmoji = try XCTUnwrap(midpoint.searchRange(in: text, invalidRangePolicy: .clamp))
        XCTAssertEqual(clampedEmoji.substring(in: text), "👩‍💻")

        XCTAssertNil(beyondEnd.searchRange(in: text, invalidRangePolicy: .discard))
        let clampedEnd = try XCTUnwrap(beyondEnd.searchRange(in: text, invalidRangePolicy: .clamp))
        XCTAssertEqual(clampedEnd.characterOffsets, text.count ..< text.count)
        XCTAssertEqual(clampedEnd.substring(in: text), "")
    }

    /// CBW-001-render_assistant_markdown: content-width sizing은 짧은 메시지를 자연 폭으로 줄이고 긴 메시지를 제안 폭으로 제한한다.
    /// user/request bubble이 `.fitsContent`에서 짧은 텍스트는 자연 폭을, 긴 텍스트는 transcript 제안 폭에서 줄바꿈하는지 검증합니다.
    /// - 검증 내용: 짧은 텍스트 intrinsic width < 최대, 긴 텍스트 intrinsic width == 최대(상한), 긴 텍스트 높이 > 짧은 텍스트 높이
    /// - 사전 조건: 240pt 폭의 hosted output을 `.fitsContent`로 구성하고 짧은/긴 텍스트를 각각 렌더한다.
    /// - 기대 결과: 짧은 bubble은 240pt 미만으로 수축하고 긴 bubble은 240pt에서 줄바꿈되어 더 높이가 커진다.
    func testRenderUserMessageContentWidthSizesShortTextToNaturalWidthAndCapsLongText() {
        let maxWidth: CGFloat = 240
        let shortHarness = makeSelectableOutputHarness(
            text: "Hello",
            width: maxWidth,
            sizingMode: .fitsContent,
        )
        defer { shortHarness.window.close() }
        let shortIntrinsic = shortHarness.coordinator.scrollView.intrinsicContentSize

        let longText = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 6)
        let longHarness = makeSelectableOutputHarness(
            text: longText,
            width: maxWidth,
            sizingMode: .fitsContent,
        )
        defer { longHarness.window.close() }
        let longIntrinsic = longHarness.coordinator.scrollView.intrinsicContentSize

        XCTAssertGreaterThan(shortIntrinsic.width, 0)
        XCTAssertLessThan(shortIntrinsic.width, maxWidth)
        XCTAssertEqual(longIntrinsic.width, maxWidth, accuracy: 0.5)
        XCTAssertGreaterThan(longIntrinsic.height, shortIntrinsic.height)
    }

    /// CBW-001-render_assistant_markdown: content-width sizing은 기본 expandsToFillWidth 동작을 변경하지 않는다.
    /// assistant 블록이 기본 모드에서 여전히 제안 폭을 채우는 noIntrinsicMetric 가로 치수를 보고하는지 검증합니다.
    /// - 검증 내용: 기본 모드 intrinsic width == noIntrinsicMetric, `.fitsContent`는 실수 width 보고
    /// - 사전 조건: 같은 텍스트를 expandsToFillWidth와 fitsContent로 각각 렌더한다.
    /// - 기대 결과: 기본 모드는 무한 폭 제안을 유지하고 fitsContent만 자연 폭으로 수축한다.
    func testRenderUserMessageContentWidthDoesNotAffectAssistantExpandsToFillWidth() {
        let text = "Hello"
        let assistantHarness = makeSelectableOutputHarness(
            text: text,
            width: 240,
            sizingMode: .expandsToFillWidth,
        )
        defer { assistantHarness.window.close() }
        let userHarness = makeSelectableOutputHarness(
            text: text,
            width: 240,
            sizingMode: .fitsContent,
        )
        defer { userHarness.window.close() }

        XCTAssertEqual(assistantHarness.coordinator.scrollView.intrinsicContentSize.width, NSView.noIntrinsicMetric)
        XCTAssertNotEqual(userHarness.coordinator.scrollView.intrinsicContentSize.width, NSView.noIntrinsicMetric)
        XCTAssertGreaterThan(userHarness.coordinator.scrollView.intrinsicContentSize.width, 0)
    }

    /// CBW-001-render_assistant_markdown: content-width bubble에서도 native block-local selection과 copy가 유지된다.
    /// `.fitsContent`로 sizing된 user bubble에서 마우스/컨텍스트 메뉴 copy가 여전히 정확한 substring을 내보내는지 검증합니다.
    /// - 검증 내용: selectAll은 block-local, copy pasteboard는 선택 substring, select-all copy는 전체 텍스트
    /// - 사전 조건: NFD+emoji 텍스트를 포함한 `.fitsContent` output이 first responder이다.
    /// - 기대 결과: copy는 선택된 substring을, selectAll 후 copy는 전체 텍스트를 pasteboard에 기록한다.
    func testRenderUserMessageContentWidthRetainsNativeSelectionAndCopy() throws {
        let text = "앞 cafe\u{301} 👩‍💻 뒤"
        let selectedText = "cafe\u{301} 👩‍💻"
        let harness = makeSelectableOutputHarness(
            text: text,
            width: 240,
            sizingMode: .fitsContent,
        )
        defer { harness.window.close() }
        let textView = harness.coordinator.textView

        let stringRange = try XCTUnwrap(text.range(of: selectedText))
        let searchRange = AiChatMarkdownDocument.SearchRange(stringRange, in: text)
        let selection = try XCTUnwrap(searchRange.plainSelectionRange(in: text))

        textView.setSelectedRange(selection.nsRange)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        textView.copy(nil as Any?)
        XCTAssertEqual(pasteboard.string(forType: .string), selectedText)

        textView.selectAll(nil as Any?)
        XCTAssertEqual(try selectedSubstring(in: textView), text)
        pasteboard.clearContents()
        textView.copy(nil as Any?)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    /// CBW-001-render_assistant_markdown: fitsContent 한국어 짧은 문장은 한 줄로 표시된다.
    /// 자연 폭 측정-제안 container 경계의 sub-pixel mismatch로 마지막 음절이 줄바꿈되는 회귀를 검증합니다.
    /// - 검증 내용: line fragment 개수, 자연 폭 < viewport, NFD+emoji copy 정확성을 확인합니다.
    /// - 사전 조건: 사용자가 입력한 한국어 완결문이 240pt viewport의 `.fitsContent` bubble에 렌더됩니다.
    /// - 기대 결과: 문장이 정확히 한 줄에 표시되고 copy는 선택 substring을 정확히 내보냅니다.
    func testRenderUserMessageContentWidthFitsKoreanSentenceOnOneLineAtSufficientViewport() throws {
        let text = "오늘 날씨 자세하게 알려줘."
        let harness = makeSelectableOutputHarness(
            text: text,
            width: 240,
            sizingMode: .fitsContent,
        )
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let scrollView = harness.coordinator.scrollView
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)

        XCTAssertLessThan(scrollView.intrinsicContentSize.width, 240)

        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        var lineCount = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
            lineCount += 1
        }
        XCTAssertEqual(lineCount, 1, "한국어 짧은 문장은 한 줄로 표시되어야 한다")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        textView.selectAll(nil as Any?)
        textView.copy(nil as Any?)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    /// CBW-001-render_assistant_markdown: fitsContent 긴 한국어 문장은 viewport 상한에서 정상 줄바꿈된다.
    /// 자연 폭이 viewport를 초과할 때 tolerance가 줄바꿈을 숨기지 않고 정상적으로 wrap하는지 검증합니다.
    /// - 검증 내용: 자연 폭 > viewport, intrinsic width == viewport 상한, line fragment 개수 > 1을 확인합니다.
    /// - 사전 조건: 한국어 완결문을 5회 반복한 긴 텍스트가 240pt viewport의 `.fitsContent` bubble에 렌더됩니다.
    /// - 기대 결과: bubble 폭은 viewport에 상한되고 텍스트가 여러 줄로 줄바꿈됩니다.
    func testRenderUserMessageContentWidthWrapsLongKoreanSentenceAtViewportCap() throws {
        let text = String(repeating: "오늘 날씨 자세하게 알려줘. ", count: 5)
        let harness = makeSelectableOutputHarness(
            text: text,
            width: 240,
            sizingMode: .fitsContent,
        )
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let scrollView = harness.coordinator.scrollView
        let layoutManager = try XCTUnwrap(textView.layoutManager)

        XCTAssertGreaterThan(
            scrollView.intrinsicContentSize.width, 0,
        )
        XCTAssertEqual(scrollView.intrinsicContentSize.width, 240, accuracy: 0.5)

        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        var lineCount = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
            lineCount += 1
        }
        XCTAssertGreaterThan(lineCount, 1, "긴 문장은 viewport 상한에서 줄바꿈되어야 한다")
    }

    /// CBW-001-render_assistant_markdown: capped 폭 한국어 prompt의 마지막 단어가 고아로 줄바꿈되지 않는다.
    /// Hangul word-priority 줄바꿈 전략이 user/request bubble에서 `응답해` / `줘.` 분리를 방지하는지 검증합니다.
    /// - 검증 내용: line fragment에 `줘.` 단독 줄 부재, `응답해줘.` 전체가 한 줄에 포함, copy 정확성을 확인합니다.
    /// - 사전 조건: 스크린샷 정확한 prompt가 hangulWordPriority 적용 상태로 480pt capped 폭에 렌더됩니다.
    /// - 기대 결과: 어떤 줄도 `줘.`만 단독이 아니며 `응답해줘.` 전체가 한 줄에 있고 copy는 원문을 정확히 반환합니다.
    func testRenderUserMessageContentWidthHangulWordPriorityKeepsFinalWordOnCappedWidth() throws {
        let text = "swift 코드 블록으로 hello world 한 줄만 보여줘. 설명 없이 fenced code block만 응답해줘."
        let attributed = AiChatAssistantMarkdownAttributedText.make(
            text: text,
            inlineIntents: [],
            matchOffsets: [],
            currentMatchOffsets: nil,
            appliesHangulWordPriorityLineBreak: true,
        )
        let harness = makeSelectableOutputHarness(
            text: text,
            width: 480,
            sizingMode: .fitsContent,
            attributedText: attributed,
        )
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let layoutManager = try XCTUnwrap(textView.layoutManager)

        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        var lineTexts: [String] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, glyphLineRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: glyphLineRange, actualGlyphRange: nil)
            lineTexts.append((textView.string as NSString).substring(with: charRange))
        }

        XCTAssertGreaterThan(lineTexts.count, 1, "capped 폭에서 텍스트는 줄바꿈되어야 한다")
        for lineText in lineTexts {
            XCTAssertNotEqual(
                lineText.trimmingCharacters(in: .whitespacesAndNewlines),
                "줘.",
                "어떤 줄도 `줘.`만 단독으로 가지면 안 된다",
            )
        }
        XCTAssertTrue(
            lineTexts.contains { $0.contains("응답해줘.") },
            "전체 `응답해줘.` 단어가 한 줄에 포함되어야 한다",
        )

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        textView.selectAll(nil as Any?)
        textView.copy(nil as Any?)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    /// CBW-001-render_assistant_markdown: 짧은 user/request bubble은 실제 SwiftUI HStack에서 자연 폭을 hug한다.
    /// production HStack { Spacer; AiChatUserMessageBubble } 레이아웃을 600pt에 호스팅하고
    /// 단문 메시지의 selectable text surface가 가용 폭의 절반 미만으로 좁아지는지 검증합니다.
    /// - 검증 내용: hosted IntrinsicTextScrollView frame width < 300pt를 확인합니다.
    /// - 사전 조건: "오늘 날씨 자세하게 알려줘."를 600pt HStack의 AiChatUserMessageBubble에 렌더합니다.
    /// - 기대 결과: selectable surface 폭이 300pt 미만으로 자연 텍스트 폭을 hug합니다.
    func testRenderUserMessageBubbleHugsNaturalWidthForShortText() throws {
        let hostWidth: CGFloat = 600
        let text = "오늘 날씨 자세하게 알려줘."
        let harness = makeUserMessageBubbleHarness(text: text, hostWidth: hostWidth)
        defer { harness.window.close() }

        let scrollView = try XCTUnwrap(
            descendantScrollViews(in: harness.hostingView)
                .compactMap({ $0 as? AiChatSelectableOutputText.IntrinsicTextScrollView })
                .first,
            "hosted user bubble must produce an IntrinsicTextScrollView",
        )

        XCTAssertGreaterThan(scrollView.frame.width, 0, "selectable surface must have positive width")
        XCTAssertLessThan(
            scrollView.frame.width,
            300,
            "short user bubble must hug natural width (expect ~200pt), not fill 600pt transcript",
        )
    }

    /// CBW-001-render_assistant_markdown: 긴 user/request bubble은 가용 폭에 cap하고 wrap한다.
    /// production 레이아웃에서 장문 메시지가 가용 폭을 넘지 않고 multi-line으로 줄바꿈되는지 검증합니다.
    /// - 검증 내용: selectable surface 폭 ≤ 가용 폭(spacer + padding 제외)이고 line fragment가 2개 이상인지 확인합니다.
    /// - 사전 조건: screenshot의 정확한 긴 문장을 좁은 transcript(400pt) HStack에 렌더합니다.
    /// - 기대 결과: 폭이 가용 한계 이하이고 텍스트가 여러 줄로 wrap됩니다.
    func testRenderUserMessageBubbleCapsLongTextToAvailableWidthAndWraps() throws {
        let hostWidth: CGFloat = 400
        let text = "swift 코드 블록으로 hello world 한 줄만 보여줘. 설명 없이 fenced code block만 응답해줘."
        let harness = makeUserMessageBubbleHarness(text: text, hostWidth: hostWidth)
        defer { harness.window.close() }

        let scrollView = try XCTUnwrap(
            descendantScrollViews(in: harness.hostingView)
                .compactMap({ $0 as? AiChatSelectableOutputText.IntrinsicTextScrollView })
                .first,
            "hosted user bubble must produce an IntrinsicTextScrollView",
        )

        let availableTextWidth = hostWidth - 16 - 28 // Spacer minLength + horizontal padding
        XCTAssertLessThanOrEqual(
            scrollView.frame.width,
            availableTextWidth + 1,
            "long user bubble must not escape available width",
        )

        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        var lineCount = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
            lineCount += 1
        }
        XCTAssertGreaterThan(lineCount, 1, "long text must wrap to multiple lines within capped width")
    }

    /// CBW-001-render_assistant_markdown: zero-frame update 후 late nonzero layout가 geometry를 repair한다.
    /// - 검증 내용: zero-frame provisional height가 1줄 범위(0 < h < 100), late layout 후 container/frame width=240, height <
    /// 100, x=0를 확인합니다.
    /// - 사전 조건: coordinator가 0폭에서 한 줄 텍스트 "Hello"로 update된 후 240pt로 resize됩니다.
    /// - 기대 결과: zero-frame height > 0 && < 100, late layout 후 container/frame 240, height < 100, x origin=0.
    func testRenderAssistantMarkdownZeroFrameUpdateThenLateNonzeroLayoutRepairsGeometry() {
        let text = "Hello"
        let coordinator = AiChatSelectableOutputText.Coordinator()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.scrollView
        defer { window.close() }

        coordinator.update(blockID: .init(rawValue: "zero-frame"), attributedText: NSAttributedString(string: text))

        let zeroFrameHeight = coordinator.scrollView.intrinsicContentSize.height
        XCTAssertGreaterThan(zeroFrameHeight, 0, "provisional height must be positive")
        XCTAssertLessThan(zeroFrameHeight, 100, "provisional height must be in one-line range, not pathological")

        coordinator.scrollView.frame.size = NSSize(width: 240, height: 120)
        coordinator.scrollView.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()

        let textView = coordinator.textView
        let containerWidth = textView.textContainer?.containerSize.width ?? -1
        XCTAssertEqual(containerWidth, 240, accuracy: 1, "container width must match viewport after late layout")
        XCTAssertEqual(textView.frame.width, 240, accuracy: 1, "frame width must match viewport")
        let repairedHeight = coordinator.scrollView.intrinsicContentSize.height
        XCTAssertGreaterThan(repairedHeight, 0)
        XCTAssertLessThan(repairedHeight, 100, "repaired height must be in one-line range")
        XCTAssertEqual(coordinator.scrollView.contentView.bounds.origin.x, 0, "x origin must be zero")
    }

    /// CBW-001-render_assistant_markdown: zero-frame fitsContent도 late layout 후 finite height를 보장한다.
    /// - 검증 내용: zero-frame height < 100, late layout 후 height < 100, x=0을 확인합니다.
    /// - 사전 조건: coordinator가 0폭에서 `.fitsContent` "Hi"로 update된 후 240pt로 resize됩니다.
    /// - 기대 결과: zero-frame과 late layout 모두 height < 100, x origin=0.
    func testRenderUserMessageContentWidthZeroFrameThenLateLayoutStaysFiniteForFitsContent() {
        let text = "Hi"
        let coordinator = AiChatSelectableOutputText.Coordinator()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.scrollView
        defer { window.close() }

        coordinator.update(
            blockID: .init(rawValue: "zero-fits"),
            attributedText: NSAttributedString(string: text),
            sizingMode: .fitsContent,
        )

        let zeroHeight = coordinator.scrollView.intrinsicContentSize.height
        XCTAssertGreaterThan(zeroHeight, 0)
        XCTAssertLessThan(zeroHeight, 100)

        coordinator.scrollView.frame.size = NSSize(width: 240, height: 120)
        coordinator.scrollView.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()

        let repairedHeight = coordinator.scrollView.intrinsicContentSize.height
        XCTAssertGreaterThan(repairedHeight, 0)
        XCTAssertLessThan(repairedHeight, 100)
        XCTAssertEqual(coordinator.scrollView.contentView.bounds.origin.x, 0)
    }

    /// CBW-001-render_assistant_markdown: short code card(label+padding+border 포함)가 자연 폭을 hug한다.
    /// - 검증 내용: hosted code card의 NSScrollView frame width < 480을 확인합니다.
    /// - 사전 조건: 짧은 Swift code가 480pt hosted Markdown에 렌더됩니다.
    /// - 기대 결과: code NSScrollView frame width가 480pt 미만입니다.
    func testRenderAssistantMarkdownShortCodeCardHugsNaturalWidthViaHosting() {
        let source = "```swift\nprint(\"Hello\")\n```"
        let harness = makeAssistantMarkdownHarness(source: source, width: 480)
        defer { harness.window.close() }

        let codeScrollViews = descendantScrollViews(in: harness.hostingView).filter(\.hasHorizontalScroller)
        XCTAssertFalse(codeScrollViews.isEmpty, "code block must produce a horizontal-overflow NSScrollView")
        let codeScrollView = codeScrollViews[0]
        XCTAssertLessThan(codeScrollView.frame.width, 480, "short code card must hug natural width, not fill viewport")
    }

    /// CBW-001-render_assistant_markdown: long code card가 viewport에 cap한다.
    /// - 검증 내용: hosted code card의 NSScrollView frame width ≈ 240을 확인합니다.
    /// - 사전 조건: 긴 code가 240pt hosted Markdown에 렌더됩니다.
    /// - 기대 결과: code NSScrollView frame width가 240pt에 cap됩니다.
    func testRenderAssistantMarkdownLongCodeCardCapsAtViewportViaHosting() {
        let longLine = String(repeating: "x", count: 200)
        let source = "```swift\n\(longLine)\n```"
        let harness = makeAssistantMarkdownHarness(source: source, width: 240)
        defer { harness.window.close() }

        let codeScrollViews = descendantScrollViews(in: harness.hostingView).filter(\.hasHorizontalScroller)
        XCTAssertFalse(codeScrollViews.isEmpty, "long code must produce a horizontal-overflow NSScrollView")
        let codeScrollView = codeScrollViews[0]
        XCTAssertLessThanOrEqual(codeScrollView.frame.width, 240, "long code card must not escape viewport (<=240)")
        XCTAssertGreaterThan(codeScrollView.frame.width, 200, "long code card must fill most of viewport")

        let allFramesInBounds = descendantScrollViews(in: harness.hostingView).allSatisfy { $0.frame.minX >= -1 }
        XCTAssertTrue(allFramesInBounds, "no descendant must have negative left clipping")
    }

    /// CBW-001-render_assistant_markdown: narrow table이 자연 폭을 hug한다.
    /// - 검증 내용: narrow 2-column table hosting에서 horizontal overflow NSScrollView가 없거나 card 폭 < 480을 확인합니다.
    /// - 사전 조건: 2-column narrow table이 480pt hosted Markdown에 렌더됩니다.
    /// - 기대 결과: table이 자연 폭을 hug해 480pt 미만으로 표시됩니다.
    func testRenderAssistantMarkdownNarrowTableHugsNaturalWidthViaHosting() {
        let source = "| a | b |\n| --- | --- |\n| 1 | 2 |"
        let harness = makeAssistantMarkdownHarness(source: source, width: 480)
        defer { harness.window.close() }

        let allScrollViews = descendantScrollViews(in: harness.hostingView)
        XCTAssertFalse(allScrollViews.isEmpty, "narrow table must render cell NSScrollViews")

        let cellScrollViews = allScrollViews.filter { !$0.hasHorizontalScroller }
        XCTAssertFalse(cellScrollViews.isEmpty, "table cell content must be present")
        XCTAssertTrue(cellScrollViews.allSatisfy { $0.frame.width > 0 }, "cell content must be visible")

        let overflowing = allScrollViews.filter(\.hasHorizontalScroller)
        XCTAssertTrue(
            overflowing.allSatisfy { $0.frame.width < 480 },
            "no table element must fill the full 480pt viewport",
        )
    }

    /// CBW-001-render_assistant_markdown: wide 12-column table이 horizontal scroll fallback를 사용한다.
    /// - 검증 내용: 12-column table이 narrow viewport에서 horizontal overflow를 trigger하는지 확인합니다.
    /// - 사전 조건: 12-column wide table이 240pt hosted Markdown에 렌더됩니다.
    /// - 기대 결과: ViewThatFits가 ScrollView fallback를 선택해 horizontal scroll이 활성화됩니다.
    func testRenderAssistantMarkdownWideTableProducesHorizontalScrollAtNarrowViewport() {
        let source = makeTwelveColumnTableSource()
        let harness = makeAssistantMarkdownHarness(source: source, width: 240)
        defer { harness.window.close() }

        let horizontalScrollViews = descendantScrollViews(in: harness.hostingView).filter(\.hasHorizontalScroller)
        XCTAssertFalse(horizontalScrollViews.isEmpty, "wide table must produce horizontal scroll at narrow viewport")
        let widestScrollView = horizontalScrollViews.max(by: { $0.frame.width < $1.frame.width })
        XCTAssertNotNil(widestScrollView)
        XCTAssertEqual(
            widestScrollView?.frame.width ?? 0,
            240,
            accuracy: 10,
            "wide table scroll must cap near viewport",
        )
    }

    /// CBW-001-render_assistant_markdown: short code inner text surface도 자연 폭을 hug한다.
    /// - 검증 내용: intrinsic width < viewport, width > 0, hasHorizontalScroller를 확인합니다.
    /// - 사전 조건: 짧은 Swift code가 480pt의 `.fitsContent` + overflow surface에 렌더됩니다.
    /// - 기대 결과: intrinsic width가 480pt 미만이고 horizontal scroller가 활성화됩니다.
    func testRenderAssistantMarkdownShortCodeHugsNaturalWidthWithFitsContentOverflow() {
        let code = #"print("Hello, world!")"#
        let harness = makeSelectableOutputHarness(
            text: code, width: 480, allowsHorizontalOverflow: true, sizingMode: .fitsContent,
        )
        defer { harness.window.close() }
        let scrollView = harness.coordinator.scrollView

        XCTAssertGreaterThan(scrollView.intrinsicContentSize.width, 0)
        XCTAssertLessThan(scrollView.intrinsicContentSize.width, 480, "short code must hug natural width")
        XCTAssertTrue(scrollView.hasHorizontalScroller)
    }

    /// CBW-001-render_assistant_markdown: long code inner text surface도 viewport에 cap한다.
    /// - 검증 내용: intrinsic width ≈ viewport, hasHorizontalScroller, finite height를 확인합니다.
    /// - 사전 조건: 긴 code가 240pt의 `.fitsContent` + overflow surface에 렌더됩니다.
    /// - 기대 결과: intrinsic width가 viewport에 cap되고 scroller가 활성화되며 height는 finite입니다.
    func testRenderAssistantMarkdownLongCodeCapsAtViewportWithFitsContentOverflow() {
        let longCode = String(repeating: "let value = someFunction(withArgument); ", count: 20)
        let harness = makeSelectableOutputHarness(
            text: longCode, width: 240, allowsHorizontalOverflow: true, sizingMode: .fitsContent,
        )
        defer { harness.window.close() }
        let scrollView = harness.coordinator.scrollView

        XCTAssertEqual(scrollView.intrinsicContentSize.width, 240, accuracy: 1, "long code must cap at viewport")
        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertGreaterThan(scrollView.intrinsicContentSize.height, 0)
    }

    /// CBW-001-render_assistant_markdown: document와 모든 nested value가 Swift 6 Sendable을 만족한다.
    /// parser와 highlighting actor 사이를 통과할 pure model이 compiler-checked value semantics인지 검증합니다.
    /// - 검증 내용: document, block, ID, kinds, projections, payload와 typed ranges의 Sendable constraint를 확인합니다.
    /// - 사전 조건: production model 타입이 test target에 internal visibility로 노출되어 있습니다.
    /// - 기대 결과: 모든 타입이 suppression이나 unchecked conformance 없이 generic constraint를 통과합니다.
    func testRenderAssistantMarkdownDocumentValuesAreSendable() {
        func requireSendable(_: (some Sendable).Type) {}

        requireSendable(AiChatMarkdownDocument.self)
        requireSendable(AiChatMarkdownDocument.Block.self)
        requireSendable(AiChatMarkdownDocument.BlockID.self)
        requireSendable(AiChatMarkdownDocument.BlockKind.self)
        requireSendable(AiChatMarkdownDocument.InlineIntent.self)
        requireSendable(AiChatMarkdownDocument.Projections.self)
        requireSendable(AiChatMarkdownDocument.CodePayload.self)
        requireSendable(AiChatMarkdownDocument.TableCell.self)
        requireSendable(AiChatMarkdownDocument.TableMetadata.self)
        requireSendable(AiChatMarkdownDocument.TableAlignment.self)
        requireSendable(AiChatMarkdownDocument.SourceRange.self)
        requireSendable(AiChatMarkdownDocument.SearchRange.self)
        requireSendable(AiChatMarkdownDocument.PlainSelectionRange.self)
    }

    /// CBW-001-render_assistant_markdown: 요청 grammar를 한 번의 lossless parse로 목적별 projection에 투영한다.
    /// CRLF와 Unicode를 포함한 assistant Markdown이 block intent와 raw source를 동시에 보존하는지 검증합니다.
    /// - 검증 내용: heading, paragraph, list, blockquote, table, inline code, image, link, fenced code와 metadata를 확인합니다.
    /// - 사전 조건: alignment table과 들여쓴 Swift fence를 포함한 mixed CRLF Markdown 원문이 있습니다.
    /// - 기대 결과: raw bytes/ranges는 입력과 같고 rendered/search/plain/code/language projection은 marker와 목적에 맞게 분리됩니다.
    func testRenderAssistantMarkdownParsesRequestedGrammarLosslessly() {
        let source = "# 제목\r\n\r\n"
            + "Use **bold** [문서](https://example.com) and ![대체](https://example.com/image.png)\r\n\r\n"
            + "- 항목\r\n"
            + "1. 순서\r\n\r\n"
            + "> 인용 `code`\r\n\r\n"
            + "| 이름 | 값 |\r\n| :--- | ---: |\r\n| 검색 | 👩‍💻 |\r\n\r\n"
            + "  ```Swift linenos\r\nlet café = \"e\u{301}\"\r\n  ```\r\n"

        let document = AiChatMarkdownParser.parse(source)

        XCTAssertEqual(document.rawUTF8, Array(source.utf8))
        XCTAssertEqual(document.reconstructedRawSource, source)
        XCTAssertEqual(
            document.blocks.compactMap { $0.sourceRange.rawSlice(in: source) },
            document.blocks.map(\.rawSlice),
        )
        XCTAssertEqual(document.blocks.map(\.kind), [
            .heading(level: 1), .paragraph, .bullet, .numbered(number: 1), .blockquote, .table, .code,
        ])
        XCTAssertEqual(document.renderedBlocks, [
            "제목", "Use bold 문서 and 대체", "항목", "순서", "인용 code", "이름 값 검색 👩‍💻", "let café = \"e\u{301}\"\r\n",
        ])
        XCTAssertEqual(document.searchBlocks, document.renderedBlocks)
        XCTAssertEqual(document.blocks[4].projections.plain, "인용 code")
        XCTAssertEqual(document.blocks[4].inlineIntents, [.code(.init(characterOffsets: 3 ..< 7))])
        XCTAssertEqual(document.blocks[5].projections.plain, "이름\t값\n검색\t👩‍💻")
        XCTAssertEqual(document.blocks[5].table?.alignments, [.left, .right])
        XCTAssertEqual(document.blocks[6].code?.payload, "let café = \"e\u{301}\"\r\n")
        XCTAssertEqual(document.blocks[6].code?.openingIndentation, "  ")
        XCTAssertEqual(document.blocks[6].code?.fenceDelimiter, "```")
        XCTAssertEqual(document.blocks[6].code?.originalInfoString, "Swift linenos")
        XCTAssertEqual(document.blocks[6].code?.originalLanguage, "Swift")
        XCTAssertEqual(document.blocks[6].code?.trailingMetadata, "linenos")
        XCTAssertEqual(document.blocks[6].code?.normalizedLanguage, "swift")
        XCTAssertTrue(document.rawSource.contains("https://example.com"))
        XCTAssertFalse(document.blocks[1].projections.plain.contains("https://"))
    }

    /// CBW-001-render_assistant_markdown: block projection은 nested display intent와 link destination을 한 번에 보존한다.
    /// marker가 제거된 rendered Character offsets가 heading/list/blockquote의 실제 표시 문자열과 일치하는지 검증합니다.
    /// - 검증 내용: single/strong emphasis, link destination, inline code의 typed range와 malformed literal을 확인합니다.
    /// - 사전 조건: nested strong-link와 Unicode inline code를 포함한 block grammar 및 닫히지 않은 delimiter가 있습니다.
    /// - 기대 결과: 유효 intent는 rendered offsets를 가리키고 malformed delimiter는 literal이며 false intent가 없습니다.
    func testRenderAssistantMarkdownPreservesNestedDisplayIntentsAtRenderedCharacterOffsets() {
        let source = "# *head* [docs](https://heading)\n\n"
            + "- **bold** `code`\n"
            + "1. [num](https://numbered) _em_\n\n"
            + "> **quote [link](https://quote)** and `코드`\n\n"
            + "`open *unmatched [label](missing"

        let document = AiChatMarkdownParser.parse(source)

        XCTAssertEqual(document.blocks.map(\.projections.rendered), [
            "head docs", "bold code", "num em", "quote link and 코드", "`open *unmatched [label](missing",
        ])
        XCTAssertEqual(document.blocks[0].inlineIntents, [
            .emphasis(.init(characterOffsets: 0 ..< 4)),
            .link(range: .init(characterOffsets: 5 ..< 9), destination: "https://heading"),
        ])
        XCTAssertEqual(document.blocks[1].inlineIntents, [
            .strong(.init(characterOffsets: 0 ..< 4)),
            .code(.init(characterOffsets: 5 ..< 9)),
        ])
        XCTAssertEqual(document.blocks[2].inlineIntents, [
            .link(range: .init(characterOffsets: 0 ..< 3), destination: "https://numbered"),
            .emphasis(.init(characterOffsets: 4 ..< 6)),
        ])
        XCTAssertEqual(document.blocks[3].inlineIntents, [
            .strong(.init(characterOffsets: 0 ..< 10)),
            .link(range: .init(characterOffsets: 6 ..< 10), destination: "https://quote"),
            .code(.init(characterOffsets: 15 ..< 17)),
        ])
        XCTAssertTrue(document.blocks[4].inlineIntents.isEmpty)
        XCTAssertEqual(document.blocks[4].projections.plain, "`open *unmatched [label](missing")

        let nested = AiChatMarkdownParser.parse("*outer **strong** end*").blocks[0]
        XCTAssertEqual(nested.projections.rendered, "outer strong end")
        XCTAssertEqual(nested.inlineIntents, [
            .emphasis(.init(characterOffsets: 0 ..< 16)),
            .strong(.init(characterOffsets: 6 ..< 12)),
        ])

        let unmatched = AiChatMarkdownParser.parse("**unclosed *rest*").blocks[0]
        XCTAssertEqual(unmatched.projections.rendered, "**unclosed *rest*")
        XCTAssertTrue(unmatched.inlineIntents.isEmpty)
    }

    /// CBW-001-render_assistant_markdown: table cell은 intent를 소유하고 fenced code는 literal payload만 소유한다.
    /// Task 5가 cell을 재parse하지 않고 표시 의미를 소비하며 code backtick을 inline Markdown으로 오인하지 않는지 검증합니다.
    /// - 검증 내용: cell-local strong/link/code ranges와 fenced-code empty inline intents를 확인합니다.
    /// - 사전 조건: inline grammar가 있는 2열 table과 Markdown-like token을 포함한 Swift fence가 있습니다.
    /// - 기대 결과: table cell metadata에 intent가 남고 code payload/projection은 그대로이며 block intent는 비어 있습니다.
    func testRenderAssistantMarkdownKeepsTableCellIntentsAndTreatsFencedCodeAsLiteral() throws {
        let source = "| **강조** | [링크](https://table) `코드` |\n"
            + "| --- | --- |\n\n"
            + "```swift\nlet raw = `tick` *literal* [link](destination)\n```\n"

        let document = AiChatMarkdownParser.parse(source)
        let table = try XCTUnwrap(document.blocks[0].table)

        XCTAssertEqual(table.rows, [["강조", "링크 코드"]])
        XCTAssertEqual(table.cells[0][0].inlineIntents, [
            .strong(.init(characterOffsets: 0 ..< 2)),
        ])
        XCTAssertEqual(table.cells[0][1].inlineIntents, [
            .link(range: .init(characterOffsets: 0 ..< 2), destination: "https://table"),
            .code(.init(characterOffsets: 3 ..< 5)),
        ])
        XCTAssertEqual(document.blocks[0].projections.plain, "강조\t링크 코드")
        XCTAssertEqual(document.blocks[1].code?.payload, "let raw = `tick` *literal* [link](destination)\n")
        XCTAssertEqual(document.blocks[1].projections.search, "let raw = `tick` *literal* [link](destination)\n")
        XCTAssertTrue(document.blocks[1].inlineIntents.isEmpty)
    }

    /// CBW-001-render_assistant_markdown: 미완성 fence는 plain fallback을 유지하다 closing fence에서 code로 전환한다.
    /// streaming chunk가 fence를 완성하기 전후에도 앞선 block identity와 exact source가 손상되지 않는지 검증합니다.
    /// - 검증 내용: incomplete plain fallback, complete code payload/metadata와 unchanged prefix identity를 확인합니다.
    /// - 사전 조건: 안정된 paragraph 뒤에 들여쓴 Swift fence opening과 CRLF body가 순차 append됩니다.
    /// - 기대 결과: closing 전에는 code가 아니며 closing 후 exact code가 되고 앞선 paragraph ID는 동일합니다.
    func testRenderAssistantMarkdownTransitionsIncompleteFenceWithoutLosingStreamingPrefix() {
        let prefix = "안정된 문단\r\n\r\n"
        let incomplete = prefix + "  ```Swift linenos\r\nlet value = 1\r\n"
        let complete = incomplete + "  ```\r\n"

        let incompleteDocument = AiChatMarkdownParser.parse(incomplete)
        let completeDocument = AiChatMarkdownParser.parse(complete)

        XCTAssertEqual(incompleteDocument.reconstructedRawSource, incomplete)
        XCTAssertEqual(incompleteDocument.blocks.last?.kind, .paragraph)
        XCTAssertNil(incompleteDocument.blocks.last?.code)
        XCTAssertEqual(incompleteDocument.blocks.last?.projections.plain, "  ```Swift linenos\r\nlet value = 1\r\n")
        XCTAssertEqual(completeDocument.reconstructedRawSource, complete)
        XCTAssertEqual(completeDocument.blocks.last?.kind, .code)
        XCTAssertEqual(completeDocument.blocks.last?.code?.payload, "let value = 1\r\n")
        XCTAssertEqual(completeDocument.blocks.last?.code?.originalLanguage, "Swift")
        XCTAssertEqual(incompleteDocument.blocks.first?.id, completeDocument.blocks.first?.id)
        XCTAssertNotEqual(incompleteDocument.blocks.last?.id, completeDocument.blocks.last?.id)
    }

    /// CBW-001-render_assistant_markdown: unsupported·malformed construct는 문자와 순서를 보존한 plain fallback이다.
    /// 제한된 grammar 밖의 task list, raw HTML, malformed table이 해석되거나 삭제되지 않는지 검증합니다.
    /// - 검증 내용: fallback raw/plain source와 별도 image/link의 alt/label projection을 확인합니다.
    /// - 사전 조건: task list, raw HTML, delimiter 없는 table 다음에 image와 link가 있는 paragraph가 있습니다.
    /// - 기대 결과: unsupported source는 exact plain이고 image는 alt, link는 label만 projection에 남습니다.
    func testRenderAssistantMarkdownPreservesUnsupportedSyntaxAndProjectsImageAltOnly() {
        let unsupported = "- [ ] task\n<div>raw</div>\n| broken |\nnot delimiter\n\n"
        let supported = "![대체 텍스트](https://example.com/image.png) [링크](https://example.com)"
        let document = AiChatMarkdownParser.parse(unsupported + supported)

        XCTAssertEqual(document.reconstructedRawSource, unsupported + supported)
        XCTAssertEqual(document.blocks.first?.kind, .paragraph)
        XCTAssertEqual(document.blocks.first?.rawSlice, unsupported)
        XCTAssertEqual(document.blocks.first?.projections.plain, unsupported)
        XCTAssertEqual(document.blocks.last?.projections.rendered, "대체 텍스트 링크")
        XCTAssertEqual(document.blocks.last?.projections.search, "대체 텍스트 링크")
        XCTAssertEqual(document.blocks.last?.projections.plain, "대체 텍스트 링크")
    }

    /// CBW-001-render_assistant_markdown: block identity는 source 위치가 아닌 stable content fingerprint를 사용한다.
    /// streaming append가 앞선 block을 재식별하지 않고 duplicate content도 서로 구분하는지 검증합니다.
    /// - 검증 내용: append 전후 prefix ID 안정성, 위치 이동 안정성과 duplicate occurrence ID 구분을 확인합니다.
    /// - 사전 조건: 동일한 paragraph가 두 번 있고 뒤에 새 heading을 append한 두 source가 있습니다.
    /// - 기대 결과: 기존 두 ID는 append 후 그대로이고 서로 다르며 같은 block이 앞에 삽입되어 이동해도 content ID가 유지됩니다.
    func testRenderAssistantMarkdownKeepsStableDistinctBlockIdentityAcrossStreamingAppend() {
        let initial = AiChatMarkdownParser.parse("same\n\nsame\n\n")
        let appended = AiChatMarkdownParser.parse("same\n\nsame\n\n# next\n")
        let shifted = AiChatMarkdownParser.parse("# before\n\nsame\n\nsame\n\n")

        XCTAssertEqual(Array(appended.blocks.prefix(2).map(\.id)), initial.blocks.map(\.id))
        XCTAssertNotEqual(initial.blocks[0].id, initial.blocks[1].id)
        XCTAssertEqual(Array(shifted.blocks.suffix(2).map(\.id)), initial.blocks.map(\.id))
        XCTAssertFalse(initial.blocks[0].id.rawValue.contains("0-"))
    }

    /// CBW-001-render_assistant_markdown: known language와 alias를 원본 label과 분리해 highlight한다.
    /// Swift와 JavaScript alias가 semantic run을 만들면서 사용자가 입력한 fence label은 그대로 유지되는지 검증합니다.
    /// - 검증 내용: live Highlighter engine의 source 보존, language normalization, theme, semantic attribute run을 확인합니다.
    /// - 사전 조건: bundled default themes를 사용하는 light Swift와 dark `js` 요청이 있습니다.
    /// - 기대 결과: 두 요청 모두 display 가능한 highlighted result이며 original label과 normalized language가 분리됩니다.
    func testRenderAssistantMarkdownHighlightsKnownLanguagesAndPreservesOriginalLabels() async {
        let client = AiChatSyntaxHighlightingClient.live()
        let swiftCode = "let value = 42"
        let javascriptCode = "const value = 42;"

        let swiftResult = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: swiftCode,
            languageLabel: "swift",
            appearance: .light,
            typographyVersion: 1,
            generation: 1,
        ))
        let javascriptResult = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: javascriptCode,
            languageLabel: "js",
            appearance: .dark,
            typographyVersion: 1,
            generation: 2,
        ))

        XCTAssertEqual(swiftResult.source, swiftCode)
        XCTAssertEqual(swiftResult.originalLanguage, "swift")
        XCTAssertEqual(swiftResult.normalizedLanguage, "swift")
        XCTAssertEqual(swiftResult.theme, "default-light")
        XCTAssertEqual(swiftResult.disposition, .highlighted)
        XCTAssertTrue(swiftResult.isEligibleForDisplay)
        XCTAssertTrue(swiftResult.runs.contains { !$0.attributes.isPlain })

        XCTAssertEqual(javascriptResult.source, javascriptCode)
        XCTAssertEqual(javascriptResult.originalLanguage, "js")
        XCTAssertEqual(javascriptResult.normalizedLanguage, "javascript")
        XCTAssertEqual(javascriptResult.theme, "default-dark")
        XCTAssertEqual(javascriptResult.disposition, .highlighted)
        XCTAssertTrue(javascriptResult.isEligibleForDisplay)
        XCTAssertTrue(javascriptResult.runs.contains { !$0.attributes.isPlain })
    }

    /// CBW-001-render_assistant_markdown: highlighting boundary의 모든 값은 Swift 6 Sendable을 만족한다.
    /// actor와 UI 사이에 third-party mutable object 없이 compiler-checked feature value만 전달되는지 검증합니다.
    /// - 검증 내용: client, request/result, source range, run attributes와 disposition의 Sendable constraint를 확인합니다.
    /// - 사전 조건: production adapter 타입이 test target에 internal visibility로 노출되어 있습니다.
    /// - 기대 결과: suppression이나 unchecked conformance 없이 모든 boundary value가 generic constraint를 통과합니다.
    func testRenderAssistantMarkdownHighlightingBoundaryValuesAreSendable() {
        func requireSendable(_: (some Sendable).Type) {}

        requireSendable(AiChatSyntaxHighlightingClient.self)
        requireSendable(AiChatSyntaxHighlightingClient.RequestIdentity.self)
        requireSendable(AiChatSyntaxHighlightingClient.Request.self)
        requireSendable(AiChatSyntaxHighlightingClient.Result.self)
        requireSendable(AiChatSyntaxHighlightingClient.Run.self)
        requireSendable(AiChatSyntaxHighlightingClient.SourceRange.self)
        requireSendable(AiChatSyntaxHighlightingClient.HighlightAttributes.self)
        requireSendable(AiChatSyntaxHighlightingClient.ColorComponents.self)
        requireSendable(AiChatSyntaxHighlightingClient.CacheMetrics.self)
        requireSendable(AiChatSyntaxHighlightingClient.Appearance.self)
        requireSendable(AiChatSyntaxHighlightingClient.Disposition.self)
        requireSendable(AiChatSyntaxHighlightingClient.FallbackReason.self)
    }

    /// CBW-001-render_assistant_markdown: unknown과 language-less fence는 auto-detection 없이 plain fallback한다.
    /// 명시하지 않았거나 지원하지 않는 언어가 JavaScriptCore auto-detection으로 전달되지 않는지 검증합니다.
    /// - 검증 내용: exact source plain run, fallback disposition, engine invocation 0회를 확인합니다.
    /// - 사전 조건: 지원 언어가 swift/javascript인 fake engine에 `madeuplang`과 nil label을 전달합니다.
    /// - 기대 결과: 두 결과 모두 exact plain source이고 highlight engine은 호출되지 않습니다.
    func testRenderAssistantMarkdownFallsBackWithoutAutoDetectionForUnknownOrMissingLanguage() async {
        let recorder = SyntaxHighlightingRecorder()
        let client = makeSyntaxHighlightingClient(recorder: recorder)
        let source = "print(\"그대로\")"

        let unknown = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: source,
            languageLabel: "madeuplang",
            appearance: .light,
            typographyVersion: 1,
            generation: 1,
        ))
        let missing = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: source,
            languageLabel: nil,
            appearance: .light,
            typographyVersion: 1,
            generation: 2,
        ))

        XCTAssertEqual(unknown.disposition, .plain(.unsupportedLanguage))
        XCTAssertEqual(missing.disposition, .plain(.missingLanguage))
        assertExactPlainSyntaxResult(unknown, source: source)
        assertExactPlainSyntaxResult(missing, source: source)
        let fallbackInvocationCount = await recorder.invocationCount()
        XCTAssertEqual(fallbackInvocationCount, 0)
    }

    /// CBW-001-render_assistant_markdown: appearance와 typography config는 독립 cache key를 만든다.
    /// 같은 source/config는 재사용하되 light/dark 또는 typography version 변경은 stale style을 재사용하지 않는지 검증합니다.
    /// - 검증 내용: cache hit/miss별 engine invocation과 theme key를 확인합니다.
    /// - 사전 조건: 동일 Swift code를 light v1 두 번, dark v1, dark v2 순서로 요청합니다.
    /// - 기대 결과: light의 두 번째 요청만 cache hit이고 engine 호출은 총 3회입니다.
    func testRenderAssistantMarkdownKeysCacheByAppearanceThemeAndTypographyVersion() async {
        let recorder = SyntaxHighlightingRecorder()
        let client = makeSyntaxHighlightingClient(recorder: recorder)
        let code = "let cached = true"

        _ = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: code,
            languageLabel: "swift",
            appearance: .light,
            typographyVersion: 1,
            generation: 1,
        ))
        _ = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: code,
            languageLabel: "swift",
            appearance: .light,
            typographyVersion: 1,
            generation: 2,
        ))
        _ = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: code,
            languageLabel: "swift",
            appearance: .dark,
            typographyVersion: 1,
            generation: 3,
        ))
        _ = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: code,
            languageLabel: "swift",
            appearance: .dark,
            typographyVersion: 2,
            generation: 4,
        ))

        let cacheInvocationCount = await recorder.invocationCount()
        XCTAssertEqual(cacheInvocationCount, 3)
        let metrics = await client.cacheMetrics()
        XCTAssertEqual(metrics.entryCount, 3)
        XCTAssertLessThanOrEqual(metrics.estimatedBytes, AiChatSyntaxHighlightingClient.maximumCacheBytes)
    }

    /// CBW-001-render_assistant_markdown: 독립 block은 역순 완료되어도 서로 stale 처리하지 않는다.
    /// shared client와 engine을 사용하는 두 code block의 freshness lane이 identity별로 분리되는지 검증합니다.
    /// - 검증 내용: reverse completion의 eligibility, 두 cache admission, 이후 content cache hit를 확인합니다.
    /// - 사전 조건: 서로 다른 identity의 Swift 요청 두 개가 engine에서 동시에 suspend되어 있습니다.
    /// - 기대 결과: B 다음 A 순서로 완료해도 둘 다 highlighted·eligible이고 engine 호출은 재요청에서 늘지 않습니다.
    func testRenderAssistantMarkdownKeepsIndependentReverseCompletionsEligibleAndCached() async {
        await assertIndependentSyntaxHighlightingReverseCompletion()
    }

    /// CBW-001-render_assistant_markdown: 다른 block의 missing/preflight fallback은 in-flight highlight를 무효화하지 않는다.
    /// 즉시 축퇴하는 한 block이 별도 block의 이미 시작된 JavaScript 결과 freshness에 영향을 주지 않는지 검증합니다.
    /// - 검증 내용: missing-language와 64KiB preflight 이후 in-flight success eligibility/cache hit를 확인합니다.
    /// - 사전 조건: identity A는 engine에서 suspend되고 identity B는 missing generation 1과 oversized generation 2를 요청합니다.
    /// - 기대 결과: B의 두 fallback은 exact plain이고 A는 이후 highlighted·eligible로 완료되어 cache hit됩니다.
    func testRenderAssistantMarkdownFallbackIdentityDoesNotInvalidateInFlightHighlight() async {
        await assertSyntaxHighlightingFallbackIdentityIsolation()
    }

    /// CBW-001-render_assistant_markdown: superseded engine failure는 current failure fallback으로 노출하지 않는다.
    /// 이전 generation이 늦게 throw해도 최신 성공 결과와 cache를 덮어쓰지 않는지 검증합니다.
    /// - 검증 내용: latest success 후 older failure의 stale disposition, eligibility, cache admission을 확인합니다.
    /// - 사전 조건: 같은 identity의 generation 1/2가 engine에서 suspend되고 generation 2가 먼저 성공합니다.
    /// - 기대 결과: generation 1 late throw는 stale·display-ineligible이고 generation 2 cache만 유지됩니다.
    func testRenderAssistantMarkdownTreatsLateSupersededEngineFailureAsStale() async {
        await assertSyntaxHighlightingLateFailureIsStale()
    }

    /// CBW-001-render_assistant_markdown: high-watermark보다 낮은 generation은 current가 될 수 없다.
    /// 늦게 도착한 낮은 revision이 cache hit를 통해 최신 결과처럼 적용되지 않는지 검증합니다.
    /// - 검증 내용: generation 2 success 후 generation 1 stale, generation 3 cache hit와 invocation count를 확인합니다.
    /// - 사전 조건: 같은 identity와 source의 generation 2가 먼저 성공해 semantic cache에 있습니다.
    /// - 기대 결과: generation 1은 engine/cache lookup 전에 stale이고 generation 3만 highlighted·eligible입니다.
    func testRenderAssistantMarkdownRejectsLateLowerGenerationForSameIdentity() async {
        await assertSyntaxHighlightingRejectsLateLowerGeneration()
    }

    /// CBW-001-render_assistant_markdown: current initialization/theme/highlight 실패는 표시 가능한 plain fallback이다.
    /// 최신 요청의 third-party runtime 실패가 source를 숨기지 않으면서 실패 결과를 재사용하지 않는지 검증합니다.
    /// - 검증 내용: failure별 disposition, display eligibility, exact plain run, cache admission과 반복 invocation을 확인합니다.
    /// - 사전 조건: supported-language 조회 실패와 theme/highlight 단계에서 각각 typed failure를 던지는 current request가 있습니다.
    /// - 기대 결과: 모든 current 실패는 exact plain·display-eligible이고 cache entry는 0개입니다.
    func testRenderAssistantMarkdownKeepsCurrentEngineFailuresEligibleButUncached() async {
        let initializationClient = AiChatSyntaxHighlightingClient.testing(
            coalescingDelay: .zero,
            supportedLanguages: { throw AiChatSyntaxHighlightingClient.EngineFailure.initialization },
            highlight: { _, _, _ in XCTFail("Initialization failure must not highlight")
                return []
            },
        )
        let themeRecorder = SyntaxHighlightingRecorder(failure: .theme)
        let themeClient = makeSyntaxHighlightingClient(recorder: themeRecorder)
        let highlightRecorder = SyntaxHighlightingRecorder(failure: .highlight)
        let highlightClient = makeSyntaxHighlightingClient(recorder: highlightRecorder)
        let request = AiChatSyntaxHighlightingClient.Request(
            identity: .init(rawValue: "failure-block"),
            code: "let failure = true",
            languageLabel: "swift",
            appearance: .light,
            typographyVersion: 1,
            generation: 1,
        )

        let initialization = await initializationClient.highlight(request)
        let theme = await themeClient.highlight(request)
        let firstHighlight = await highlightClient.highlight(request)
        let secondHighlight = await highlightClient.highlight(.init(
            identity: request.identity,
            code: request.code,
            languageLabel: request.languageLabel,
            appearance: request.appearance,
            typographyVersion: request.typographyVersion,
            generation: 2,
        ))

        XCTAssertEqual(initialization.disposition, .plain(.initializationFailure))
        XCTAssertEqual(theme.disposition, .plain(.themeFailure))
        XCTAssertEqual(firstHighlight.disposition, .plain(.highlightFailure))
        XCTAssertEqual(secondHighlight.disposition, .plain(.highlightFailure))
        for result in [initialization, theme, firstHighlight, secondHighlight] {
            assertExactPlainSyntaxResult(result, source: request.code)
            XCTAssertTrue(result.isEligibleForDisplay)
        }
        let initializationMetrics = await initializationClient.cacheMetrics()
        let themeMetrics = await themeClient.cacheMetrics()
        let highlightMetrics = await highlightClient.cacheMetrics()
        let highlightInvocationCount = await highlightRecorder.invocationCount()
        XCTAssertEqual(initializationMetrics.entryCount, 0)
        XCTAssertEqual(themeMetrics.entryCount, 0)
        XCTAssertEqual(highlightMetrics.entryCount, 0)
        XCTAssertEqual(highlightInvocationCount, 2)
    }

    /// CBW-001-render_assistant_markdown: supported-language 조회 중 취소는 후발 initialization 오류보다 우선한다.
    /// 취소를 협조하지 않는 dependency가 나중에 일반 오류를 던져도 취소된 결과가 표시되지 않는지 검증합니다.
    /// - 검증 내용: exact plain source, cancelled disposition, display eligibility와 cache admission을 확인합니다.
    /// - 사전 조건: supported-language loader가 시작을 알리고 suspend된 뒤 task를 취소하고 initialization 오류로 재개합니다.
    /// - 기대 결과: 결과는 display-ineligible cancelled exact plain이고 cache entry는 0개입니다.
    func testRenderAssistantMarkdownTreatsCancelledLanguageLoadFailureAsCancellation() async {
        let loader = SuspendedSupportedLanguagesLoader()
        let client = AiChatSyntaxHighlightingClient.testing(
            coalescingDelay: .zero,
            supportedLanguages: { try await loader.load() },
            highlight: { _, _, _ in
                XCTFail("Cancelled language loading must not highlight")
                return []
            },
        )
        let request = syntaxHighlightingRequest(
            identity: "cancelled-language-load",
            code: "let cancelled = true",
            generation: 1,
        )
        let task = Task { await client.highlight(request) }
        await loader.waitUntilStarted()

        task.cancel()
        await loader.fail(with: .initialization)
        let result = await task.value
        let metrics = await client.cacheMetrics()

        XCTAssertEqual(result.disposition, .plain(.cancelled))
        XCTAssertFalse(result.isEligibleForDisplay)
        assertExactPlainSyntaxResult(result, source: request.code)
        XCTAssertEqual(metrics.entryCount, 0)
    }

    /// CBW-001-render_assistant_markdown: engine highlight 중 취소는 후발 highlight 오류보다 우선한다.
    /// 취소를 협조하지 않는 engine이 나중에 일반 오류를 던져도 취소된 결과가 표시되지 않는지 검증합니다.
    /// - 검증 내용: exact plain source, cancelled disposition, display eligibility와 cache admission을 확인합니다.
    /// - 사전 조건: highlight operation이 시작을 알리고 suspend된 뒤 task를 취소하고 highlight 오류로 재개합니다.
    /// - 기대 결과: 결과는 display-ineligible cancelled exact plain이고 cache entry는 0개입니다.
    func testRenderAssistantMarkdownTreatsCancelledHighlightFailureAsCancellation() async {
        let operation = SuspendedHighlightOperation()
        let client = AiChatSyntaxHighlightingClient.testing(
            coalescingDelay: .zero,
            supportedLanguages: { ["swift"] },
            highlight: { _, _, _ in try await operation.highlight() },
        )
        let request = syntaxHighlightingRequest(
            identity: "cancelled-highlight",
            code: "let cancelled = true",
            generation: 1,
        )
        let task = Task { await client.highlight(request) }
        await operation.waitUntilStarted()

        task.cancel()
        await operation.fail(with: .highlight)
        let result = await task.value
        let metrics = await client.cacheMetrics()

        XCTAssertEqual(result.disposition, .plain(.cancelled))
        XCTAssertFalse(result.isEligibleForDisplay)
        assertExactPlainSyntaxResult(result, source: request.code)
        XCTAssertEqual(metrics.entryCount, 0)
    }

    /// CBW-001-render_assistant_markdown: 64KiB와 2,000-line preflight limit을 넘는 source는 engine 전에 축퇴한다.
    /// 과도한 JavaScriptCore 작업이 시작되기 전에 byte/line limit이 각각 독립적으로 적용되는지 검증합니다.
    /// - 검증 내용: 65,537-byte와 2,001-line source의 invocation 0회와 exact plain fallback을 확인합니다.
    /// - 사전 조건: byte limit 초과 단일 행과 line limit 초과 소형 행 fixture가 있습니다.
    /// - 기대 결과: 두 요청 모두 display 가능한 preflight fallback이고 source가 변하지 않습니다.
    func testRenderAssistantMarkdownPreflightsOversizedByteAndLineInputs() async {
        let recorder = SyntaxHighlightingRecorder()
        let client = makeSyntaxHighlightingClient(recorder: recorder)
        let oversizedBytes = String(repeating: "x", count: 65537)
        let oversizedLines = String(repeating: "x\n", count: 2000) + "x"

        let byteResult = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: oversizedBytes,
            languageLabel: "swift",
            appearance: .light,
            typographyVersion: 1,
            generation: 1,
        ))
        let lineResult = await client.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: oversizedLines,
            languageLabel: "swift",
            appearance: .light,
            typographyVersion: 1,
            generation: 2,
        ))

        XCTAssertEqual(byteResult.disposition, .plain(.preflightLimit))
        XCTAssertEqual(lineResult.disposition, .plain(.preflightLimit))
        assertExactPlainSyntaxResult(byteResult, source: oversizedBytes)
        assertExactPlainSyntaxResult(lineResult, source: oversizedLines)
        XCTAssertTrue(byteResult.isEligibleForDisplay)
        XCTAssertTrue(lineResult.isEligibleForDisplay)
        let preflightInvocationCount = await recorder.invocationCount()
        XCTAssertEqual(preflightInvocationCount, 0)
    }

    /// CBW-001-render_assistant_markdown: trailing-edge coalescing과 generation 검사가 stale completion을 적용하지 않는다.
    /// 빠른 streaming update와 이미 시작된 느린 JavaScript 작업이 최신 render 결과를 덮어쓰지 않는지 검증합니다.
    /// - 검증 내용: 80ms window invocation 1회, older generation stale disposition, 최신 결과만 cache admission을 확인합니다.
    /// - 사전 조건: 연속 요청용 immediate recorder와 완료 순서를 제어하는 suspending recorder가 있습니다.
    /// - 기대 결과: coalesced 이전 요청과 늦게 끝난 이전 generation은 UI 적용 불가이고 최신 generation만 적용 가능합니다.
    func testRenderAssistantMarkdownCoalescesAndDiscardsStaleGenerations() async throws {
        try await assertSyntaxHighlightingTrailingEdgeCoalescing()
        await assertSyntaxHighlightingStaleGenerationDiscard()
    }

    /// CBW-001-render_assistant_markdown: code fence 언어 변경은 동일 presentation에서도 highlight task를 갱신한다.
    /// payload와 표시 위치가 같아도 language info가 바뀌면 이전 언어의 syntax run을 재사용하지 않는지 검증합니다.
    /// - 검증 내용: Swift와 JavaScript fence의 presentation ID 일치와 highlight task identity 차이를 확인합니다.
    /// - 사전 조건: 같은 payload를 가진 동일 row의 두 완성 code fence가 언어 label만 다릅니다.
    /// - 기대 결과: selection identity는 유지되지만 highlight task identity는 달라집니다.
    func testRenderAssistantMarkdownRefreshesHighlightTaskWhenFenceLanguageChanges() throws {
        let session = AiChatAssistantMarkdownRenderSession(highlightingClient: .live())
        let transcriptRow = AiChatTranscriptRowDiscriminator.streamingAssistant
        let swiftBlock = try XCTUnwrap(session.render(
            content: "```swift\nlet value = 1\n```\n",
            transcriptRow: transcriptRow,
        ).blocks.first)
        let javascriptBlock = try XCTUnwrap(session.render(
            content: "```javascript\nlet value = 1\n```\n",
            transcriptRow: transcriptRow,
        ).blocks.first)

        XCTAssertEqual(swiftBlock.presentationID, javascriptBlock.presentationID)
        XCTAssertEqual(swiftBlock.block.code?.payload, javascriptBlock.block.code?.payload)
        XCTAssertNotEqual(
            AiChatAssistantMarkdownHighlightTaskIdentity(
                renderedBlock: swiftBlock,
                appearance: .light,
            ),
            AiChatAssistantMarkdownHighlightTaskIdentity(
                renderedBlock: javascriptBlock,
                appearance: .light,
            ),
        )
    }

    /// CBW-001-render_assistant_markdown: 동일 code block의 highlight 요청은 transcript row별로 격리한다.
    /// 서로 다른 assistant message가 같은 presentation ID를 가져도 완료 순서와 무관하게 각 결과를 적용하는지 검증합니다.
    /// - 검증 내용: 두 stored row의 역순 완료와 같은 row의 최신 generation 우선 적용을 확인합니다.
    /// - 사전 조건: 같은 Swift fence를 가진 두 message row와 완료 순서를 제어하는 highlight recorder가 있습니다.
    /// - 기대 결과: 서로 다른 row 결과는 모두 표시 가능하고 같은 row의 이전 generation만 폐기됩니다.
    func testRenderAssistantMarkdownScopesHighlightRequestsToTranscriptRows() async throws {
        let recorder = IndexedSyntaxHighlightingRecorder()
        let client = AiChatSyntaxHighlightingClient.testing(
            coalescingDelay: .zero,
            supportedLanguages: { ["swift"] },
            highlight: { code, _, _ in await recorder.highlight(code: code) },
        )
        let session = AiChatAssistantMarkdownRenderSession(highlightingClient: client)
        let source = "```swift\nlet shared = true\n```\n"
        let firstRow = AiChatTranscriptRowDiscriminator.message(index: 0)
        let secondRow = AiChatTranscriptRowDiscriminator.message(index: 1)
        let firstBlock = try XCTUnwrap(session.render(content: source, transcriptRow: firstRow).blocks.first)
        let secondBlock = try XCTUnwrap(session.render(content: source, transcriptRow: secondRow).blocks.first)
        XCTAssertEqual(firstBlock.presentationID, secondBlock.presentationID)

        let firstTask = Task {
            await session.highlight(
                firstBlock,
                transcriptRow: firstRow,
                appearance: .light,
                typographyVersion: 1,
                generation: 1,
            )
        }
        await waitForIndexedSyntaxHighlightingCalls(1, recorder: recorder)
        let secondTask = Task {
            await session.highlight(
                secondBlock,
                transcriptRow: secondRow,
                appearance: .light,
                typographyVersion: 1,
                generation: 1,
            )
        }
        await waitForIndexedSyntaxHighlightingCalls(2, recorder: recorder)

        await recorder.resume(invocation: 1, source: "let shared = true\n")
        let secondResult = await secondTask.value
        await recorder.resume(invocation: 0, source: "let shared = true\n")
        let firstResult = await firstTask.value

        XCTAssertNotNil(firstResult)
        XCTAssertNotNil(secondResult)

        let olderTask = Task {
            await session.highlight(
                firstBlock,
                transcriptRow: firstRow,
                appearance: .light,
                typographyVersion: 2,
                generation: 2,
            )
        }
        await waitForIndexedSyntaxHighlightingCalls(3, recorder: recorder)
        let latestTask = Task {
            await session.highlight(
                firstBlock,
                transcriptRow: firstRow,
                appearance: .light,
                typographyVersion: 3,
                generation: 3,
            )
        }
        await waitForIndexedSyntaxHighlightingCalls(4, recorder: recorder)

        await recorder.resume(invocation: 3, source: "let shared = true\n")
        let latestResult = await latestTask.value
        await recorder.resume(invocation: 2, source: "let shared = true\n")
        let olderResult = await olderTask.value

        XCTAssertNil(olderResult)
        XCTAssertNotNil(latestResult)
    }

    /// CBW-001-render_assistant_markdown: 세션 전환 전 highlight 완료는 현재 세션 요청을 무효화하지 않는다.
    /// 같은 row와 code를 가진 이전 세션 작업이 늦게 정리되어도 현재 세션 결과의 소유권을 유지하는지 검증합니다.
    /// - 검증 내용: 세션 A 요청 후 세션 B 동일 요청을 시작하고 A를 먼저 완료한 뒤 B 결과의 display eligibility를 확인합니다.
    /// - 사전 조건: 하나의 render session, 서로 다른 session ID, 동일 stored row와 Swift fence가 있습니다.
    /// - 기대 결과: 세션 A 결과는 폐기되고 세션 B 결과만 표시 가능한 상태로 반환됩니다.
    func testRenderAssistantMarkdownScopesHighlightRequestsToSessionLifecycle() async throws {
        let recorder = IndexedSyntaxHighlightingRecorder()
        let client = AiChatSyntaxHighlightingClient.testing(
            coalescingDelay: .zero,
            supportedLanguages: { ["swift"] },
            highlight: { code, _, _ in await recorder.highlight(code: code) },
        )
        let session = AiChatAssistantMarkdownRenderSession(highlightingClient: client)
        let source = "```swift\nlet shared = true\n```\n"
        let row = AiChatTranscriptRowDiscriminator.message(index: 0)

        session.prepareForSession(AiChatSessionID(rawValue: UUID()))
        let firstBlock = try XCTUnwrap(session.render(content: source, transcriptRow: row).blocks.first)
        let firstTask = Task {
            await session.highlight(
                firstBlock,
                transcriptRow: row,
                appearance: .light,
                typographyVersion: 1,
                generation: 1,
            )
        }
        await waitForIndexedSyntaxHighlightingCalls(1, recorder: recorder)

        session.prepareForSession(AiChatSessionID(rawValue: UUID()))
        let secondBlock = try XCTUnwrap(session.render(content: source, transcriptRow: row).blocks.first)
        let secondTask = Task {
            await session.highlight(
                secondBlock,
                transcriptRow: row,
                appearance: .light,
                typographyVersion: 1,
                generation: 1,
            )
        }
        await waitForIndexedSyntaxHighlightingCalls(2, recorder: recorder)

        await recorder.resume(invocation: 0, source: "let shared = true\n")
        let firstResult = await firstTask.value
        await recorder.resume(invocation: 1, source: "let shared = true\n")
        let secondResult = await secondTask.value

        XCTAssertFalse(firstResult?.isEligibleForDisplay ?? false)
        XCTAssertNotNil(secondResult)
        XCTAssertEqual(secondResult?.isEligibleForDisplay, true)
    }

    /// CBW-001-render_assistant_markdown: 같은 세션에서 code row가 교체 후 복원되면 highlight freshness를 갱신한다.
    /// 이전 row의 높은 generation이 coordinator에 남아도 복원된 동일 block 요청을 stale로 오판하지 않는지 검증합니다.
    /// - 검증 내용: 원본 row의 높은 generation 적용, 다른 source 교체, 원본 source 복원 후 낮은 generation 표시를 확인합니다.
    /// - 사전 조건: 하나의 render session과 session ID에서 같은 transcript row의 code source가 교체 후 복원됩니다.
    /// - 기대 결과: 복원된 code block의 새 highlight 결과가 표시 가능하고 engine 결과를 정상 적용합니다.
    func testRenderAssistantMarkdownRefreshesHighlightLifecycleAfterRowReplacement() async throws {
        let recorder = SyntaxHighlightingRecorder()
        let session = AiChatAssistantMarkdownRenderSession(
            highlightingClient: makeSyntaxHighlightingClient(recorder: recorder),
        )
        let sessionID = AiChatSessionID(rawValue: UUID())
        let row = AiChatTranscriptRowDiscriminator.message(index: 0)
        let originalSource = "```swift\nlet restored = true\n```\n"
        let replacementSource = "```swift\nlet replacement = true\n```\n"

        session.prepareForSession(
            sessionID,
            stableTranscriptSources: [row: originalSource],
        )
        let originalBlock = try XCTUnwrap(session.render(content: originalSource, transcriptRow: row).blocks.first)
        let originalResult = await session.highlight(
            originalBlock,
            transcriptRow: row,
            appearance: .light,
            typographyVersion: 1,
            generation: 100,
        )
        XCTAssertEqual(originalResult?.isEligibleForDisplay, true)

        session.prepareForSession(
            sessionID,
            stableTranscriptSources: [row: replacementSource],
        )
        _ = session.render(content: replacementSource, transcriptRow: row)
        session.prepareForSession(
            sessionID,
            stableTranscriptSources: [row: originalSource],
        )
        let restoredBlock = try XCTUnwrap(session.render(content: originalSource, transcriptRow: row).blocks.first)
        XCTAssertEqual(restoredBlock.presentationID, originalBlock.presentationID)

        let restoredResult = await session.highlight(
            restoredBlock,
            transcriptRow: row,
            appearance: .light,
            typographyVersion: 1,
            generation: 1,
        )

        XCTAssertNotNil(restoredResult)
        XCTAssertEqual(restoredResult?.isEligibleForDisplay, true)
        XCTAssertEqual(restoredResult?.disposition, .highlighted)
    }

    /// CBW-001-render_assistant_markdown: cancellation과 LRU bounds는 결과 적용과 memory growth를 제한한다.
    /// pending coalescing 취소와 많은 고유 source가 실패 cache나 무제한 cache로 이어지지 않는지 검증합니다.
    /// - 검증 내용: cancelled result eligibility와 128-entry/8MiB LRU eviction 및 재호출을 확인합니다.
    /// - 사전 조건: 80ms pending request와 130개의 약 65KB 고유 Swift source를 순차 요청합니다.
    /// - 기대 결과: 취소는 engine/cache 0회이고 LRU는 두 상한 이하이며 첫 eviction key 재요청은 cache miss입니다.
    func testRenderAssistantMarkdownDoesNotCacheCancellationAndBoundsLRU() async {
        let cancellationRecorder = SyntaxHighlightingRecorder()
        let cancellationClient = makeSyntaxHighlightingClient(
            recorder: cancellationRecorder,
            coalescingDelay: .milliseconds(80),
        )
        let cancelledTask = Task {
            await cancellationClient.highlight(syntaxHighlightingRequest(
                identity: "test-block", code: "let cancelled = true", generation: 1,
            ))
        }
        cancelledTask.cancel()
        let cancelled = await cancelledTask.value

        XCTAssertEqual(cancelled.disposition, .plain(.cancelled))
        XCTAssertFalse(cancelled.isEligibleForDisplay)
        let cancellationInvocationCount = await cancellationRecorder.invocationCount()
        let cancellationMetrics = await cancellationClient.cacheMetrics()
        XCTAssertEqual(cancellationInvocationCount, 0)
        XCTAssertEqual(cancellationMetrics.entryCount, 0)

        let lruRecorder = SyntaxHighlightingRecorder()
        let lruClient = makeSyntaxHighlightingClient(recorder: lruRecorder)
        let cachePrefixes = Array("abcdefghijklmnopqrstuvwxyz")
        let firstCode = String(repeating: cachePrefixes[0], count: 65000) + "0"
        for index in 0 ..< 130 {
            let code = String(repeating: cachePrefixes[index % cachePrefixes.count], count: 65000) + "\(index)"
            _ = await lruClient.highlight(.init(
                identity: .init(rawValue: "test-block"),
                code: code,
                languageLabel: "swift",
                appearance: .light,
                typographyVersion: 1,
                generation: UInt64(index + 1),
            ))
        }
        let beforeRevisitCount = await lruRecorder.invocationCount()
        _ = await lruClient.highlight(.init(
            identity: .init(rawValue: "test-block"),
            code: firstCode,
            languageLabel: "swift",
            appearance: .light,
            typographyVersion: 1,
            generation: 131,
        ))
        let metrics = await lruClient.cacheMetrics()

        XCTAssertLessThanOrEqual(metrics.entryCount, AiChatSyntaxHighlightingClient.maximumCacheEntries)
        XCTAssertLessThanOrEqual(metrics.estimatedBytes, AiChatSyntaxHighlightingClient.maximumCacheBytes)
        let afterRevisitCount = await lruRecorder.invocationCount()
        XCTAssertEqual(afterRevisitCount, beforeRevisitCount + 1)
    }

    /// CBW-001-render_assistant_markdown: semantic·syntax 속성 위에 search decoration만 합성하며 최종 NSTextView
    /// NSAttributedString 경계까지 AppKit attribute로 보존한다.
    /// code, link, emphasis의 표시 의미가 검색 결과 배경과 현재 결과 underline을 적용한 뒤에도 유지되는지, 그리고
    /// SwiftUI → NSAttributedString 변환에서 foreground/font/background가 누락되지 않는지 검증합니다.
    /// - 검증 내용: paragraph/code의 모든 run이 `.foregroundColor`, `.font`, 의미 속성(link/strong/code bg/syntax fg),
    ///   search background/underline을 AppKit attribute로 보존하는지, 그리고 label foreground가 dark Aqua에서 밝게
    ///   해상화되어 가독성을 유지하는지 확인합니다.
    /// - 사전 조건: strong link와 inline code paragraph, semantic Swift run에 normal/current match가 있습니다.
    /// - 기대 결과: final NSAttributedString의 모든 run이 foreground+font를 가지며, link/strong trait, inline-code
    ///   controlBackground, syntax foreground/monospaced, search yellow/accent background + current underline이 AppKit
    ///   attribute로 존재하고, dark appearance에서 label foreground의 밝기가 0.5를 초과합니다.
    func testRenderAssistantMarkdownComposesSearchWithoutReplacingSemanticOrSyntaxAttributes() throws {
        let paragraph = try XCTUnwrap(
            AiChatMarkdownParser.parse("**[link](https://example.com)** and `inline`").blocks.first,
        )
        let paragraphFinal = AiChatAssistantMarkdownAttributedText.make(
            block: paragraph,
            syntaxRuns: [],
            matchOffsets: [0 ..< 4, 9 ..< 15],
            currentMatchOffsets: 9 ..< 15,
        )
        let code = try XCTUnwrap(AiChatMarkdownParser.parse("```swift\nlet value = 1\n```\n").blocks.first)
        let syntaxColor = AiChatSyntaxHighlightingClient.ColorComponents(
            red: 0.2,
            green: 0.4,
            blue: 0.6,
            alpha: 1,
        )
        let codeFinal = AiChatAssistantMarkdownAttributedText.make(
            block: code,
            syntaxRuns: [
                .init(
                    sourceRange: .init(utf16Offsets: 0 ..< 3),
                    attributes: .init(foreground: syntaxColor, isBold: true),
                ),
            ],
            matchOffsets: [0 ..< 3],
            currentMatchOffsets: nil,
        )

        let paragraphSummary = summarizeParagraphAppKitRuns(paragraphFinal)
        XCTAssertEqual(paragraphFinal.string, "link and inline")
        XCTAssertTrue(
            paragraphSummary.allRunsHaveForegroundAndFont,
            "paragraph final NSAttributedString must retain foreground+font on every run",
        )
        XCTAssertTrue(paragraphSummary.foundLink, "paragraph final must retain semantic .link attribute")
        XCTAssertTrue(
            paragraphSummary.foundBoldTrait,
            "paragraph final must retain strong bold font trait",
        )
        XCTAssertTrue(
            paragraphSummary.foundBackground,
            "paragraph final must retain inline-code/search background",
        )
        XCTAssertTrue(
            paragraphSummary.foundCurrentUnderline,
            "paragraph final must carry current match underline",
        )

        let codeSummary = summarizeCodeAppKitRuns(codeFinal, syntaxColor: syntaxColor)
        XCTAssertEqual(codeFinal.string, "let value = 1\n")
        XCTAssertTrue(
            codeSummary.allRunsHaveForegroundAndFont,
            "code final NSAttributedString must retain foreground+font on every run",
        )
        XCTAssertTrue(codeSummary.foundSyntaxForeground, "code final must retain syntax foreground color")
        XCTAssertTrue(
            codeSummary.foundMonospacedFont,
            "code final must use monospaced font for syntax/code runs",
        )
        XCTAssertTrue(codeSummary.foundBackground, "code final must carry search result background")

        // dark Aqua에서 label foreground는 밝게 해상화되어 dark-mode 가독성을 보장한다.
        let darkBrightness = resolvedDarkAquaBrightness(paragraphSummary.sampleForeground)
        XCTAssertGreaterThan(
            darkBrightness,
            0.5,
            "label foreground must resolve to a light color in dark Aqua for readability",
        )
    }

    private struct AppKitRunSummary {
        var allRunsHaveForegroundAndFont = true
        var foundBoldTrait = false
        var foundMonospacedFont = false
        var foundSyntaxForeground = false
        var foundBackground = false
        var foundLink = false
        var foundCurrentUnderline = false
        var sampleForeground: NSColor?
    }

    private func summarizeParagraphAppKitRuns(
        _ attributed: NSAttributedString,
    ) -> AppKitRunSummary {
        var summary = AppKitRunSummary()
        let linkURL = URL(string: "https://example.com")
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: [],
        ) { attributes, _, _ in
            if attributes[.foregroundColor] == nil || attributes[.font] == nil {
                summary.allRunsHaveForegroundAndFont = false
            }
            if summary.sampleForeground == nil {
                summary.sampleForeground = attributes[.foregroundColor] as? NSColor
            }
            if let link = attributes[.link] as? URL, link == linkURL {
                summary.foundLink = true
            }
            if let font = attributes[.font] as? NSFont,
               font.fontDescriptor.symbolicTraits.contains(.bold)
            {
                summary.foundBoldTrait = true
            }
            if attributes[.backgroundColor] != nil {
                summary.foundBackground = true
            }
            if attributes[.underlineStyle] != nil {
                summary.foundCurrentUnderline = true
            }
        }
        return summary
    }

    private func summarizeCodeAppKitRuns(
        _ attributed: NSAttributedString,
        syntaxColor: AiChatSyntaxHighlightingClient.ColorComponents,
    ) -> AppKitRunSummary {
        var summary = AppKitRunSummary()
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: [],
        ) { attributes, _, _ in
            if attributes[.foregroundColor] == nil || attributes[.font] == nil {
                summary.allRunsHaveForegroundAndFont = false
            }
            if let font = attributes[.font] as? NSFont,
               font.fontDescriptor.symbolicTraits.contains(.monoSpace)
            {
                summary.foundMonospacedFont = true
            }
            if let color = attributes[.foregroundColor] as? NSColor,
               let resolved = color.usingColorSpace(.sRGB),
               abs(resolved.redComponent - CGFloat(syntaxColor.red)) < 0.01,
               abs(resolved.greenComponent - CGFloat(syntaxColor.green)) < 0.01,
               abs(resolved.blueComponent - CGFloat(syntaxColor.blue)) < 0.01
            {
                summary.foundSyntaxForeground = true
            }
            if attributes[.backgroundColor] != nil {
                summary.foundBackground = true
            }
        }
        return summary
    }

    private func resolvedDarkAquaBrightness(_ color: NSColor?) -> CGFloat {
        guard let darkAppearance = NSAppearance(named: .darkAqua) else { return 0 }
        var brightness: CGFloat = 0
        darkAppearance.performAsCurrentDrawingAppearance {
            guard let resolved = color?.usingColorSpace(.sRGB) else { return }
            brightness = resolved.brightnessComponent
        }
        return brightness
    }

    /// CBW-001-render_assistant_markdown: rich block presentation은 parser metadata를 재해석 없이 소비한다.
    /// heading/list/paragraph/blockquote/code/table UI가 wrapping, language, alignment 계약에 필요한 typed metadata를 받는지
    /// 검증합니다.
    /// - 검증 내용: block kind, original language, table cell/alignment, vertical scroll ownership과 design token policy를
    /// 확인합니다.
    /// - 사전 조건: 모든 rich block 종류와 aligned table을 포함한 하나의 assistant document가 있습니다.
    /// - 기대 결과: 한 renderer document가 stable identity와 구조 metadata를 보존하며 child vertical scroll을 요구하지 않습니다.
    func testRenderAssistantMarkdownBuildsRichPresentationsFromOneDocumentPath() {
        let source = "# Heading\n\nParagraph `code`\n\n- Bullet\n1. Numbered\n\n> Quote\n\n"
            + "| Left | Right |\n| :--- | ---: |\n| A | B |\n\n```Swift\nlet value = 1\n```\n"
        let session = AiChatAssistantMarkdownRenderSession(highlightingClient: .testing(
            coalescingDelay: .zero,
            supportedLanguages: { ["swift"] },
            highlight: { _, _, _ in [] },
        ))

        let rendered = session.render(content: source, transcriptRow: .message(index: 2))

        XCTAssertEqual(rendered.document.blocks.map(\.kind), [
            .heading(level: 1), .paragraph, .bullet, .numbered(number: 1), .blockquote, .table, .code,
        ])
        XCTAssertEqual(rendered.blocks.map(\.presentationID).count, rendered.document.blocks.count)
        XCTAssertEqual(rendered.document.blocks.last?.code?.originalLanguage, "Swift")
        XCTAssertEqual(rendered.document.blocks[5].table?.alignments, [.left, .right])
        XCTAssertEqual(rendered.document.blocks[5].table?.rows, [["Left", "Right"], ["A", "B"]])
        XCTAssertFalse(rendered.ownsChildVerticalScroll)
    }

    /// CBW-001-render_assistant_markdown: incomplete fence와 persisted finalization은 view-local handoff state를 보존한다.
    /// streaming block 종류와 transcript row가 바뀌어도 호환 가능한 사용자 선택·responder·scroll·검색 문맥이 이어지는지 검증합니다.
    /// - 검증 내용: presentation identity, typed selection, first responder, outer offset와 current descriptor remap을 확인합니다.
    /// - 사전 조건: 안정된 prefix 뒤 incomplete Swift fence의 body가 선택된 상태에서 closing chunk와 stored row가 순서대로 도착합니다.
    /// - 기대 결과: 두 전환 뒤 같은 표시 block identity와 exact 선택·scroll·current search descriptor가 복원됩니다.
    func testRenderAssistantMarkdownRestoresCompatibleViewStateAcrossFenceClosureAndFinalization() throws {
        let session = AiChatAssistantMarkdownRenderSession(highlightingClient: .live())
        let incomplete = "stable\n\n```Swift\nlet needle = 1\n"
        let complete = incomplete + "```\n"
        let streaming = session.render(content: incomplete, transcriptRow: .streamingAssistant)
        let selectedText = "needle"
        let streamingPlain = try XCTUnwrap(streaming.blocks.last?.block.projections.plain)
        let selectedStringRange = try XCTUnwrap(streamingPlain.range(of: selectedText))
        let selectedSearchRange = AiChatMarkdownDocument.SearchRange(selectedStringRange, in: streamingPlain)
        let selectedRange = try XCTUnwrap(selectedSearchRange.plainSelectionRange(in: streamingPlain))
        let current = AiChatRenderedTextMatchDescriptor(
            transcriptRow: .streamingAssistant,
            blockIndex: 1,
            characterOffsets: 13 ..< 19,
        )
        try session.capture(.init(
            presentationID: XCTUnwrap(streaming.blocks.last?.presentationID),
            selection: selectedRange,
            isFirstResponder: true,
            outerScrollOffset: 42,
            currentSearchDescriptor: current,
            transcriptRow: .streamingAssistant,
        ))

        let closed = session.render(content: complete, transcriptRow: .streamingAssistant)
        let stored = session.render(content: complete, transcriptRow: .message(index: 3))
        let restored = try XCTUnwrap(session.restoration(for: stored))

        XCTAssertEqual(closed.blocks.last?.presentationID, streaming.blocks.last?.presentationID)
        XCTAssertEqual(stored.blocks.last?.presentationID, closed.blocks.last?.presentationID)
        let storedPlain = try XCTUnwrap(stored.blocks.last?.block.projections.plain)
        let restoredSelection = try XCTUnwrap(restored.selection)
        let restoredSearchRange = try XCTUnwrap(
            restoredSelection.searchRange(in: storedPlain, invalidRangePolicy: .discard),
        )
        XCTAssertEqual(restoredSearchRange.substring(in: storedPlain), selectedText)
        XCTAssertTrue(restored.isFirstResponder)
        XCTAssertEqual(restored.outerScrollOffset, 42)
        XCTAssertEqual(restored.currentSearchDescriptor?.transcriptRow, .message(index: 3))
        XCTAssertEqual(
            restored.currentSearchDescriptor.flatMap { descriptor in
                AiChatMarkdownDocument.SearchRange(characterOffsets: descriptor.characterOffsets)
                    .substring(in: storedPlain)
            },
            selectedText,
        )
    }

    /// CBW-001-render_assistant_markdown: 프로그램 update는 snapshot을 만들지 않고 table cell selection만 handoff한다.
    /// sibling block의 empty selection이 실제 table cell selection과 first responder를 덮어쓰지 않는지 검증합니다.
    /// - 검증 내용: update callback 억제, cell projection 등록, stored row restoration을 확인합니다.
    /// - 사전 조건: streaming table cell을 hosted output의 first responder로 선택한 뒤 같은 content를 stored row로 전환합니다.
    /// - 기대 결과: 초기 update는 snapshot이 없고 선택 뒤에는 exact cell substring과 responder가 stored row에 복원됩니다.
    func testRenderAssistantMarkdownPreservesOnlyUserTableCellSelectionAcrossFinalization() throws {
        let session = AiChatAssistantMarkdownRenderSession(highlightingClient: .live())
        let content = "| Name | Value |\n| --- | --- |\n| key | needle |\n"
        let streaming = session.render(content: content, transcriptRow: .streamingAssistant)
        let tableID = try XCTUnwrap(streaming.blocks.first?.presentationID)
        let cellID = AiChatMarkdownDocument.BlockID(rawValue: "\(tableID.rawValue)-cell-1-1")
        session.registerSelectionProjection(
            presentationID: cellID,
            plainText: "needle",
            searchText: "needle",
            transcriptRow: .streamingAssistant,
            blockIndex: 0,
        )
        let harness = makeSelectableOutputHarness(text: "needle", blockID: cellID)
        defer { harness.window.close() }
        harness.coordinator.update(
            blockID: cellID,
            attributedText: NSAttributedString(string: "needle"),
            renderSession: session,
            transcriptRow: .streamingAssistant,
        )
        XCTAssertFalse(session.hasCapturedViewState)
        XCTAssertTrue(harness.window.makeFirstResponder(harness.coordinator.textView))
        harness.coordinator.textView.selectAll(nil as Any?)

        _ = session.render(content: content, transcriptRow: .message(index: 5))
        session.registerSelectionProjection(
            presentationID: cellID,
            plainText: "needle",
            searchText: "needle",
            transcriptRow: .message(index: 5),
            blockIndex: 0,
        )
        let restored = try XCTUnwrap(session.restoration(
            presentationID: cellID,
            transcriptRow: .message(index: 5),
        ))

        XCTAssertEqual(restored.selection?.nsRange, NSRange(location: 0, length: 6))
        XCTAssertTrue(restored.isFirstResponder)
    }

    /// CBW-001-render_assistant_markdown: 호환되지 않는 block 제거는 stale view snapshot을 만료시킨다.
    /// 선택 owner가 사라진 뒤에도 snapshot이 남아 transcript auto-scroll을 영구 차단하지 않는지 검증합니다.
    /// - 검증 내용: 같은 streaming row에서 selected block 제거 후 snapshot과 restoration이 폐기되는지 확인합니다.
    /// - 사전 조건: 두 번째 paragraph에 사용자 선택·responder snapshot이 있고 다음 render에서 해당 block이 제거됩니다.
    /// - 기대 결과: 새 document가 owner identity를 claim하지 못하면 view state가 즉시 clear됩니다.
    func testRenderAssistantMarkdownExpiresSnapshotWhenSelectedBlockDisappears() throws {
        let session = AiChatAssistantMarkdownRenderSession(highlightingClient: .live())
        let initial = session.render(
            content: "stable\n\nselected",
            transcriptRow: .streamingAssistant,
        )
        let selectedBlock = try XCTUnwrap(initial.blocks.last)
        session.capture(.init(
            presentationID: selectedBlock.presentationID,
            selection: .init(utf16Location: 0, utf16Length: 8),
            isFirstResponder: true,
            outerScrollOffset: 21,
            currentSearchDescriptor: nil,
            transcriptRow: .streamingAssistant,
        ))

        let replacement = session.render(content: "stable", transcriptRow: .streamingAssistant)

        XCTAssertFalse(session.hasCapturedViewState)
        XCTAssertNil(session.restoration(for: replacement))
    }

    /// CBW-001-render_assistant_markdown: 같은 source offset의 unrelated replacement는 selection identity를 승계하지 않는다.
    /// source start만 같은 새 block이 이전 snapshot을 claim해 unrelated text로 selection을 clamp하지 않는지 검증합니다.
    /// - 검증 내용: projection continuity 없는 same-row replacement의 새 identity와 snapshot 만료를 확인합니다.
    /// - 사전 조건: 첫 block 전체에 사용자 선택 snapshot이 있고 같은 위치에 전혀 다른 paragraph가 도착합니다.
    /// - 기대 결과: replacement는 이전 presentation ID를 재사용하지 않고 view state와 restoration이 폐기됩니다.
    func testRenderAssistantMarkdownExpiresSnapshotForUnrelatedSameOffsetReplacement() throws {
        let session = AiChatAssistantMarkdownRenderSession(highlightingClient: .live())
        let initial = session.render(content: "selected", transcriptRow: .streamingAssistant)
        let selectedBlock = try XCTUnwrap(initial.blocks.first)
        session.capture(.init(
            presentationID: selectedBlock.presentationID,
            selection: .init(utf16Location: 0, utf16Length: 8),
            isFirstResponder: true,
            outerScrollOffset: 21,
            currentSearchDescriptor: nil,
            transcriptRow: .streamingAssistant,
        ))

        let replacement = session.render(content: "unrelated", transcriptRow: .streamingAssistant)

        XCTAssertNotEqual(replacement.blocks.first?.presentationID, selectedBlock.presentationID)
        XCTAssertFalse(session.hasCapturedViewState)
        XCTAssertNil(session.restoration(for: replacement))
    }

    /// CBW-001-render_assistant_markdown: unchanged prior block은 append와 finalization에서 재준비·재강조하지 않는다.
    /// stored/streaming 공통 renderer가 stable fingerprint cache와 하나의 80ms lifecycle을 공유하는지 검증합니다.
    /// - 검증 내용: parser document build, block preparation, highlighting invocation과 coalescing timer diagnostics를 확인합니다.
    /// - 사전 조건: stable Swift code 뒤 streaming paragraph가 두 번 append되고 마지막 content가 stored row로 확정됩니다.
    /// - 기대 결과: prior code block 준비·강조는 각각 한 번이며 finalization은 parse하지 않고 80ms lifecycle도 하나뿐입니다.
    func testRenderAssistantMarkdownReusesUnchangedBlocksAndOneStreamingCoalescingLifecycle() async throws {
        let recorder = SyntaxHighlightingRecorder()
        let client = makeSyntaxHighlightingClient(recorder: recorder, coalescingDelay: .zero)
        let session = AiChatAssistantMarkdownRenderSession(highlightingClient: client)
        let firstContent = "```swift\nlet stable = true\n```\n\nstream"
        let first = session.render(content: firstContent, transcriptRow: .streamingAssistant)
        let code = try XCTUnwrap(first.blocks.first)

        _ = await session.highlight(
            code,
            transcriptRow: .streamingAssistant,
            appearance: .light,
            typographyVersion: 1,
            generation: 100,
        )
        var latestContent = firstContent
        for _ in 0 ..< 64 {
            latestContent.append("x")
            _ = session.render(content: latestContent, transcriptRow: .streamingAssistant)
        }
        let parseCountBeforeRerender = session.diagnostics.documentParseCount
        _ = session.render(content: latestContent, transcriptRow: .streamingAssistant)
        let latest = session.render(content: latestContent, transcriptRow: .message(index: 4))
        _ = try await session.highlight(
            XCTUnwrap(latest.blocks.first),
            transcriptRow: .message(index: 4),
            appearance: .light,
            typographyVersion: 1,
            generation: 1,
        )
        let diagnostics = session.diagnostics
        let highlightInvocationCount = await recorder.invocationCount()

        XCTAssertEqual(parseCountBeforeRerender, 65)
        XCTAssertEqual(diagnostics.documentParseCount, parseCountBeforeRerender)
        XCTAssertEqual(diagnostics.retainedDocumentCount, 1)
        XCTAssertEqual(diagnostics.blockPreparationCount[code.presentationID], 1)
        XCTAssertEqual(diagnostics.streamingCoalescingLifecycleCount, 1)
        XCTAssertEqual(
            diagnostics.highlightGeneration[.init(
                transcriptRow: .streamingAssistant,
                presentationID: code.presentationID,
            )],
            100,
        )
        XCTAssertEqual(
            diagnostics.highlightGeneration[.init(
                transcriptRow: .message(index: 4),
                presentationID: code.presentationID,
            )],
            1,
        )
        XCTAssertEqual(highlightInvocationCount, 1)
    }

    /// CBW-001-render_assistant_markdown: 세션 전환은 이전 transcript의 Markdown projection cache를 해제한다.
    /// 하나의 AiChatView가 대용량 응답이 있는 여러 세션을 순회해도 현재 transcript 범위만 보존하는지 검증합니다.
    /// - 검증 내용: 전환 직후와 현재 row render 뒤의 projection entry 수와 retained UTF-8 bytes를 확인합니다.
    /// - 사전 조건: 같은 render session으로 서로 다른 세션의 64KiB 이상 assistant paragraph를 순서대로 표시합니다.
    /// - 기대 결과: 전환 직후 cache는 비고 render 뒤 retained entry와 bytes는 현재 document projection과 정확히 같습니다.
    func testRenderAssistantMarkdownReleasesProjectionCacheAcrossSessionTransitions() {
        let renderSession = AiChatAssistantMarkdownRenderSession(highlightingClient: .live())

        for index in 0 ..< 4 {
            let sessionID = AiChatSessionID(rawValue: UUID())
            let content = String(repeating: "session-\(index)-payload ", count: 4096)

            renderSession.prepareForSession(sessionID)
            XCTAssertEqual(renderSession.retainedSelectionProjectionCount, 0)
            XCTAssertEqual(renderSession.retainedSelectionProjectionBytes, 0)

            let rendered = renderSession.render(content: content, transcriptRow: .message(index: 0))
            let expectedBytes = rendered.blocks.reduce(into: 0) { byteCount, block in
                byteCount += block.block.projections.plain.utf8.count
                byteCount += block.block.projections.search.utf8.count
            }

            XCTAssertEqual(renderSession.retainedSelectionProjectionCount, rendered.blocks.count)
            XCTAssertEqual(renderSession.retainedSelectionProjectionBytes, expectedBytes)
        }
    }

    /// CBW-001-render_assistant_markdown: 같은 세션의 transcript reset은 이전 Markdown view state를 해제한다.
    /// sessionID가 유지되는 reset 뒤에도 이전 대용량 projection과 선택 snapshot이 남지 않는지 검증합니다.
    /// - 검증 내용: reset 직전·직후의 retained document, projection entry·bytes와 captured view state를 확인합니다.
    /// - 사전 조건: 하나의 stored row에 대용량 assistant content와 선택 snapshot을 보존한 뒤 같은 sessionID로 transcript를 비웁니다.
    /// - 기대 결과: reset 직후 document·projection cache와 선택 snapshot이 모두 해제됩니다.
    func testRenderAssistantMarkdownReleasesViewStateAcrossSameSessionTranscriptReset() throws {
        let renderSession = AiChatAssistantMarkdownRenderSession(highlightingClient: .live())
        let sessionID = AiChatSessionID(rawValue: UUID())
        let content = String(repeating: "same-session-reset-payload ", count: 4096)

        renderSession.prepareForSession(sessionID, hasTranscriptContent: true)
        let rendered = renderSession.render(content: content, transcriptRow: .message(index: 0))
        let block = try XCTUnwrap(rendered.blocks.first)
        renderSession.capture(.init(
            presentationID: block.presentationID,
            selection: .init(utf16Location: 0, utf16Length: 12),
            isFirstResponder: true,
            outerScrollOffset: 42,
            currentSearchDescriptor: nil,
            transcriptRow: .message(index: 0),
        ))

        XCTAssertEqual(renderSession.diagnostics.retainedDocumentCount, 1)
        XCTAssertGreaterThan(renderSession.retainedSelectionProjectionCount, 0)
        XCTAssertGreaterThan(renderSession.retainedSelectionProjectionBytes, 64 * 1024)
        XCTAssertTrue(renderSession.hasCapturedViewState)

        renderSession.prepareForSession(sessionID, hasTranscriptContent: false)

        XCTAssertEqual(renderSession.diagnostics.retainedDocumentCount, 0)
        XCTAssertEqual(renderSession.retainedSelectionProjectionCount, 0)
        XCTAssertEqual(renderSession.retainedSelectionProjectionBytes, 0)
        XCTAssertFalse(renderSession.hasCapturedViewState)
    }

    /// CBW-001-render_assistant_markdown: 같은 세션의 saved snapshot 교체는 이전 Markdown view state를 해제한다.
    /// 비어 있지 않은 transcript가 같은 session ID의 다른 snapshot으로 교체되어도 이전 row cache와 selection을 폐기하는지 검증합니다.
    /// - 검증 내용: stable·streaming source 교체 전후의 retained document, projection entry·bytes와 captured view state를 확인합니다.
    /// - 사전 조건: 기존 대용량 stored 또는 streaming row와 선택 snapshot이 있고 같은 session ID에 새 snapshot이 적용됩니다.
    /// - 기대 결과: 새 snapshot render 전 호환되지 않는 document·projection cache와 선택 snapshot이 모두 해제됩니다.
    func testRenderAssistantMarkdownReleasesViewStateAcrossSameSessionTranscriptReplacement() throws {
        let renderSession = AiChatAssistantMarkdownRenderSession(highlightingClient: .live())
        let sessionID = AiChatSessionID(rawValue: UUID())
        let content = String(repeating: "same-session-replacement-payload ", count: 4096)

        renderSession.prepareForSession(
            sessionID,
            hasTranscriptContent: true,
            stableTranscriptSources: [.message(index: 3): content],
        )
        let rendered = renderSession.render(content: content, transcriptRow: .message(index: 3))
        let block = try XCTUnwrap(rendered.blocks.first)
        renderSession.capture(.init(
            presentationID: block.presentationID,
            selection: .init(utf16Location: 0, utf16Length: 12),
            isFirstResponder: true,
            outerScrollOffset: 42,
            currentSearchDescriptor: nil,
            transcriptRow: .message(index: 3),
        ))

        XCTAssertEqual(renderSession.diagnostics.retainedDocumentCount, 1)
        XCTAssertGreaterThan(renderSession.retainedSelectionProjectionBytes, 64 * 1024)
        XCTAssertTrue(renderSession.hasCapturedViewState)

        renderSession.prepareForSession(
            sessionID,
            hasTranscriptContent: true,
            stableTranscriptSources: [.message(index: 0): "replacement"],
        )

        XCTAssertEqual(renderSession.diagnostics.retainedDocumentCount, 0)
        XCTAssertEqual(renderSession.retainedSelectionProjectionCount, 0)
        XCTAssertEqual(renderSession.retainedSelectionProjectionBytes, 0)
        XCTAssertFalse(renderSession.hasCapturedViewState)

        renderSession.prepareForSession(
            sessionID,
            hasTranscriptContent: true,
            stableTranscriptSources: [:],
            streamingTranscriptSource: content,
        )
        let streaming = renderSession.render(content: content, transcriptRow: .streamingAssistant)
        let streamingBlock = try XCTUnwrap(streaming.blocks.first)
        renderSession.capture(.init(
            presentationID: streamingBlock.presentationID,
            selection: .init(utf16Location: 0, utf16Length: 12),
            isFirstResponder: true,
            outerScrollOffset: 42,
            currentSearchDescriptor: nil,
            transcriptRow: .streamingAssistant,
        ))

        renderSession.prepareForSession(
            sessionID,
            hasTranscriptContent: true,
            stableTranscriptSources: [.message(index: 0): "unrelated replacement"],
        )

        XCTAssertEqual(renderSession.diagnostics.retainedDocumentCount, 0)
        XCTAssertEqual(renderSession.retainedSelectionProjectionCount, 0)
        XCTAssertEqual(renderSession.retainedSelectionProjectionBytes, 0)
        XCTAssertFalse(renderSession.hasCapturedViewState)
    }

    /// CBW-001-render_assistant_markdown: user row 교체·삭제는 이전 selection projection과 view state를 해제한다.
    /// assistant document cache가 없는 user message도 현재 transcript row source와 대조해 stale selection을 폐기하는지 검증합니다.
    /// - 검증 내용: 동일 index user message의 내용 교체·삭제 전후 projection entry·bytes와 captured view state를 확인합니다.
    /// - 사전 조건: 같은 session ID의 user row에 대용량 plain/search projection과 선택 snapshot이 등록되어 있습니다.
    /// - 기대 결과: user row 내용이 바뀌거나 사라지면 이전 projection과 선택 snapshot이 즉시 해제됩니다.
    func testRenderAssistantMarkdownReleasesUserViewStateAcrossTranscriptReplacement() {
        let renderSession = AiChatAssistantMarkdownRenderSession(highlightingClient: .live())
        let sessionID = AiChatSessionID(rawValue: UUID())
        let stableRow = AiChatTranscriptRowDiscriminator.message(index: 0)
        let transcriptRow = AiChatTranscriptRowDiscriminator.message(index: 1)
        let stableMessage = AiChatMessage(role: .user, content: "stable")
        let original = AiChatMessage(
            role: .user,
            content: String(repeating: "user-selection-payload ", count: 4096),
        )
        let replacement = AiChatMessage(role: .user, content: "replacement")
        let blockID = AiChatMarkdownDocument.BlockID(rawValue: "user-message-1")

        renderSession.prepareForSession(
            sessionID,
            hasTranscriptContent: true,
            stableTranscriptMessages: [stableRow: stableMessage, transcriptRow: original],
        )
        renderSession.registerSelectionProjection(
            presentationID: blockID,
            plainText: original.content,
            searchText: original.content,
            transcriptRow: transcriptRow,
            blockIndex: 0,
        )
        renderSession.capture(.init(
            presentationID: blockID,
            selection: .init(utf16Location: 0, utf16Length: 12),
            isFirstResponder: true,
            outerScrollOffset: 42,
            currentSearchDescriptor: nil,
            transcriptRow: transcriptRow,
        ))

        XCTAssertEqual(renderSession.retainedSelectionProjectionCount, 1)
        XCTAssertGreaterThan(renderSession.retainedSelectionProjectionBytes, 64 * 1024)
        XCTAssertTrue(renderSession.hasCapturedViewState)

        renderSession.prepareForSession(
            sessionID,
            hasTranscriptContent: true,
            stableTranscriptMessages: [stableRow: stableMessage, transcriptRow: replacement],
        )

        XCTAssertEqual(renderSession.retainedSelectionProjectionCount, 0)
        XCTAssertEqual(renderSession.retainedSelectionProjectionBytes, 0)
        XCTAssertFalse(renderSession.hasCapturedViewState)

        renderSession.registerSelectionProjection(
            presentationID: blockID,
            plainText: replacement.content,
            searchText: replacement.content,
            transcriptRow: transcriptRow,
            blockIndex: 0,
        )
        renderSession.capture(.init(
            presentationID: blockID,
            selection: .init(utf16Location: 0, utf16Length: 4),
            isFirstResponder: true,
            outerScrollOffset: 21,
            currentSearchDescriptor: nil,
            transcriptRow: transcriptRow,
        ))
        renderSession.prepareForSession(
            sessionID,
            hasTranscriptContent: true,
            stableTranscriptMessages: [stableRow: stableMessage],
        )

        XCTAssertEqual(renderSession.retainedSelectionProjectionCount, 0)
        XCTAssertEqual(renderSession.retainedSelectionProjectionBytes, 0)
        XCTAssertFalse(renderSession.hasCapturedViewState)
    }

    /// CBW-001-render_assistant_markdown: 완료된 highlight request는 code source를 session lifetime 동안 보관하지 않는다.
    /// 많은 고유 code block을 순차 완료한 뒤에도 active request map과 retained source bytes가 0으로 돌아오는지 검증합니다.
    /// - 검증 내용: unique block별 highlight 성공, engine invocation, active request count와 retained UTF-8 bytes를 확인합니다.
    /// - 사전 조건: 64개의 서로 다른 stored row가 각각 고유 Swift code block을 한 번씩 highlight합니다.
    /// - 기대 결과: 64개 결과는 모두 표시 가능하지만 완료 후 active request와 source retention은 남지 않습니다.
    func testRenderAssistantMarkdownReleasesCompletedHighlightRequestSources() async throws {
        let recorder = SyntaxHighlightingRecorder()
        let session = AiChatAssistantMarkdownRenderSession(
            highlightingClient: makeSyntaxHighlightingClient(recorder: recorder),
        )

        for index in 0 ..< 64 {
            let source = "```swift\nlet unique_\(index) = \(index)\n```\n"
            let rendered = session.render(content: source, transcriptRow: .message(index: index))
            let block = try XCTUnwrap(rendered.blocks.first)
            let result = await session.highlight(
                block,
                transcriptRow: .message(index: index),
                appearance: .light,
                typographyVersion: 1,
                generation: 1,
            )
            XCTAssertNotNil(result)
        }

        let invocationCount = await recorder.invocationCount()
        XCTAssertEqual(invocationCount, 64)
        XCTAssertEqual(session.activeHighlightRequestCount, 0)
        XCTAssertEqual(session.activeHighlightSourceBytes, 0)
    }

    /// CBW-001-render_assistant_markdown: explicit row와 code copy는 각 projection의 exact 문자열을 기록한다.
    /// 사용자가 Markdown/plain/code 형식을 선택할 때 source marker와 line ending이 변형되지 않는지 검증합니다.
    /// - 검증 내용: repository PasteboardClient clear/setString 경계와 logical row selection의 format 유지를 확인합니다.
    /// - 사전 조건: CRLF Markdown, parsed whole plain projection, Swift code payload와 injected pasteboard recorder가 있습니다.
    /// - 기대 결과: Markdown은 raw source, plain은 document plainText, code는 fence 없는 payload와 정확히 같습니다.
    func testRenderAssistantMarkdownCopiesExactRowAndCodeProjections() {
        let writes = LockIsolated<[String]>([])
        let clearCount = LockIsolated(0)
        let setStringFallbackCount = LockIsolated(0)
        let pasteboard = PasteboardClient(
            changeCount: { 0 },
            clearContents: { clearCount.withValue { $0 += 1 } },
            writeObjects: { objects in
                guard let value = objects.first as? NSString else { return false }
                let string = value as String
                writes.withValue { $0.append(string) }
                return true
            },
            readObjects: { _, _ in nil },
            setString: { _, type in
                guard type == .string else { return false }
                setStringFallbackCount.withValue { $0 += 1 }
                return false
            },
            string: { _ in writes.value.last },
        )
        let raw = "> 인용 `code`\r\n\r\n"
            + "| 이름 | 값 |\r\n| --- | --- |\r\n| 검색 | 👩‍💻 |\r\n\r\n"
            + "```Swift\r\nprint(\"한글\")\r\n```\r\n"
        let document = AiChatMarkdownParser.parse(raw)
        let code = document.blocks.last?.code?.payload ?? ""
        let model = withDependencies {
            $0.pasteboardClient = pasteboard
        } operation: {
            AiChatCopyInteractionModel(announce: { _ in })
        }

        model.copyRow(format: .markdown, rawMarkdown: raw, plainText: document.plainText)
        model.selectAll()
        model.copySelectedRow(rawMarkdown: raw, plainText: document.plainText)
        model.copyRow(format: .plainText, rawMarkdown: raw, plainText: document.plainText)
        model.copyCode(code)

        XCTAssertTrue(model.isRowSelected)
        XCTAssertEqual(model.rowCopyFormat, .plainText)
        XCTAssertEqual(writes.value, [raw, raw, document.plainText, code])
        XCTAssertEqual(clearCount.value, 4)
        XCTAssertEqual(setStringFallbackCount.value, 0)
        XCTAssertFalse(code.contains("```"))
        XCTAssertFalse(code.contains("Swift"))
        assertStoredMessageViewIdentity(raw: raw)
    }

    /// CBW-001-render_assistant_markdown: explicit copy feedback는 2초를 유지하고 반복 action에서 timer를 재시작한다.
    /// 성공·실패마다 접근성 announcement가 한 번만 발생하며 native copy는 이 local state를 통과하지 않는지 검증합니다.
    /// - 검증 내용: immediate success, 1.9초 유지, repeat cancellation, 2초 clear와 actionable failure label을 확인합니다.
    /// - 사전 조건: TestClock, 성공/실패 pasteboard와 announcement recorder가 주입되어 있습니다.
    /// - 기대 결과: explicit action당 announcement 하나, repeat 기준 2초 후 success만 해제되고 failure는 retry 안내를 유지합니다.
    func testRenderAssistantMarkdownRestartsExplicitCopyFeedbackAndAnnouncesOnce() async {
        let clock = TestClock()
        let announcements = LockIsolated<[String]>([])
        let succeeds = LockIsolated(true)
        let pasteboard = PasteboardClient(
            changeCount: { 0 },
            clearContents: {},
            writeObjects: { _ in false },
            readObjects: { _, _ in nil },
            setString: { _, _ in succeeds.value },
            string: { _ in nil },
        )
        let model = withDependencies {
            $0.pasteboardClient = pasteboard
        } operation: {
            AiChatCopyInteractionModel(
                announce: { message in announcements.withValue { $0.append(message) } },
                sleep: { try await clock.sleep(for: $0) },
            )
        }

        let native = makeSelectableOutputHarness(text: "native partial")
        defer { native.window.close() }
        native.coordinator.textView.selectAll(nil as Any?)
        native.coordinator.textView.copy(nil as Any?)
        XCTAssertNil(model.feedback)
        XCTAssertTrue(announcements.value.isEmpty)

        model.copyCode("first")
        await Task.yield()
        XCTAssertEqual(model.feedback, .copied)
        XCTAssertEqual(announcements.value, [AiChatCopyInteractionModel.Feedback.copied.accessibilityLabel])
        await clock.advance(by: .milliseconds(1900))
        XCTAssertEqual(model.feedback, .copied)

        model.copyCode("repeat")
        await Task.yield()
        await clock.advance(by: .milliseconds(100))
        XCTAssertEqual(model.feedback, .copied)
        await clock.advance(by: .milliseconds(1900))
        XCTAssertNil(model.feedback)
        XCTAssertEqual(announcements.value.count, 2)

        succeeds.setValue(false)
        model.copyCode("retry")
        XCTAssertEqual(model.feedback, .failed)
        XCTAssertEqual(model.feedback?.visibleLabel.contains("다시"), true)
        XCTAssertEqual(announcements.value.count, 3)
    }

    /// CBW-001-render_assistant_markdown: selected native Copy와 custom Copy Code는 서로 다른 payload를 복사한다.
    /// code-only action을 추가해도 부분 선택 Copy, Select All, Lookup/Services와 selector enablement가 유지되고,
    /// 반복 menu augmentation 뒤에도 실제 AppKit target/action dispatch가 살아 있는지 검증합니다.
    /// - 검증 내용: menu augmentation, selected substring native copy, repeated augmentation 뒤의 NSApplication.sendAction,
    /// action enablement, Cut/Paste 부재와 exact code callback을 확인합니다.
    /// - 사전 조건: 선택 영역, native Copy/Select All/Lookup base menu와 enabled code action이 있는 hosted output입니다.
    /// - 기대 결과: native Copy는 선택 문자열만, Copy Code는 code payload만 기록하며 native items/submenu는 보존됩니다.
    func testRenderAssistantMarkdownAugmentsNativeContextMenuWithoutEditingActions() throws {
        let copiedCode = LockIsolated<[String]>([])
        let text = "prefix selected suffix"
        let harness = makeSelectableOutputHarness(
            text: text,
            contextMenuActions: [
                .init(title: "Copy Code", isEnabled: true) {
                    copiedCode.withValue { $0.append("let value = 1") }
                },
            ],
        )
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let selectedRange = try XCTUnwrap(text.range(of: "selected"))
        textView.setSelectedRange(NSRange(selectedRange, in: text))
        let base = NSMenu()
        base.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        base.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        base.addItem(services)
        textView.menu = base
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let selection = NSRange(selectedRange, in: text)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: selection,
            actualCharacterRange: nil,
        )
        let selectedRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let selectedPoint = NSPoint(
            x: textView.textContainerOrigin.x + selectedRect.midX,
            y: textView.textContainerOrigin.y + selectedRect.midY,
        )
        let windowPoint = textView.convert(selectedPoint, to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: harness.window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1,
        ))

        let menu = try XCTUnwrap(textView.menu(for: event))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copyItem = try XCTUnwrap(menu.items.first { $0.action == #selector(NSText.copy(_:)) })
        XCTAssertTrue(
            NSApp.sendAction(#selector(NSText.copy(_:)), to: textView, from: copyItem),
            "Native Copy must dispatch through AppKit",
        )
        let copyCode = menu.items.first { $0.title == "Copy Code" }
        _ = textView.augmentedContextMenu(from: base)
        XCTAssertTrue(
            try NSApp.sendAction(
                XCTUnwrap(copyCode?.action),
                to: copyCode?.target,
                from: copyCode,
            ),
            "Copy Code must remain dispatchable through AppKit after menu rebuild",
        )

        XCTAssertEqual(pasteboard.string(forType: .string), "selected")
        XCTAssertNotNil(menu.items.first { $0.action == #selector(NSText.copy(_:)) })
        XCTAssertEqual(menu.items.count(where: { $0.action == #selector(NSText.selectAll(_:)) }), 1)
        let preservedBase = NSMenu()
        let preservedServices = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        preservedServices.submenu = NSMenu(title: "Services")
        preservedBase.addItem(preservedServices)
        let preservedMenu = harness.coordinator.textView.augmentedContextMenu(from: preservedBase)

        XCTAssertNotNil(preservedMenu.items.first { $0.submenu != nil })
        XCTAssertNil(menu.items.first { $0.action == #selector(NSText.cut(_:)) })
        XCTAssertNil(menu.items.first { $0.action == #selector(NSText.paste(_:)) })
        XCTAssertEqual(copyCode?.isEnabled, true)
        XCTAssertEqual(copiedCode.value, ["let value = 1"])
    }

    /// CBW-001-render_assistant_markdown: code block menu는 실제 AppKit dispatch로 code/Markdown/plain payload를 정확히 복사한다.
    /// production menu closure가 주입된 PasteboardClient와 copy feedback state를 직접 갱신하며 native selection copy 계약과 섞이지 않는지
    /// 검증합니다.
    /// - 검증 내용: Copy Code, Copy Entire Message as Markdown, Copy Entire Message as Plain Text의 exact payload와 copied
    /// feedback를 확인합니다.
    /// - 사전 조건: paragraph + Swift fenced code가 있는 production code block view와 injected pasteboard recorder가 있습니다.
    /// - 기대 결과: 세 custom action 모두 NSApplication.sendAction으로 dispatch되고 pasteboard recorder에는 code/raw/plain payload가
    /// 정확히 기록됩니다.
    func testRenderAssistantMarkdownDispatchesExactExplicitCopyPayloadsThroughAppKitMenuActions() throws {
        let raw = """
        설명 문단

        ```swift
        print(\"한글\")
        ```
        """
        let document = AiChatMarkdownParser.parse(raw)
        let code = try XCTUnwrap(document.blocks.last?.code?.payload)
        let plain = document.plainText
        let writes = LockIsolated<[String]>([])
        let clearCount = LockIsolated(0)
        let pasteboard = PasteboardClient(
            changeCount: { 0 },
            clearContents: { clearCount.withValue { $0 += 1 } },
            writeObjects: { objects in
                guard let value = objects.first as? NSString else { return false }
                let string = value as String
                writes.withValue { $0.append(string) }
                return true
            },
            readObjects: { _, _ in nil },
            setString: { _, _ in false },
            string: { _ in writes.value.last },
        )
        let model = withDependencies {
            $0.pasteboardClient = pasteboard
        } operation: {
            AiChatCopyInteractionModel(announce: { _ in })
        }
        let renderSession = AiChatAssistantMarkdownRenderSession(highlightingClient: .testing(
            coalescingDelay: .zero,
            supportedLanguages: { [] },
            highlight: { _, _, _ in [] },
        ))
        let rendered = renderSession.render(content: raw, transcriptRow: .message(index: 0))
        let codeBlock = try XCTUnwrap(rendered.blocks.last)
        let blockView = AiChatAssistantMarkdownBlockView(
            renderedBlock: codeBlock,
            transcriptRow: .message(index: 0),
            blockIndex: rendered.blocks.count - 1,
            searchPresentation: .init(query: "", renderedRows: []),
            currentSearchMatch: nil,
            renderSession: renderSession,
            copyInteraction: model,
            rawMarkdown: raw,
            plainText: plain,
        )
        let hostingView = NSHostingView(rootView: blockView.frame(width: 480))
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        let harness = (window: window, hostingView: hostingView)
        defer { harness.window.close() }
        flushMainRunLoop()

        let codeTextView = try XCTUnwrap(
            descendantTextViews(in: harness.hostingView).first(where: { $0.string == code }),
        )
        let menu = try XCTUnwrap(codeTextView.menu(for: makeContextMenuEvent(for: codeTextView)))
        let copyCode = try XCTUnwrap(menu.items.first { $0.title == "Copy Code" })
        let copyMarkdown = try XCTUnwrap(menu.items.first { $0.title == "Copy Entire Message as Markdown" })
        let copyPlain = try XCTUnwrap(menu.items.first { $0.title == "Copy Entire Message as Plain Text" })

        XCTAssertTrue(
            try NSApp.sendAction(XCTUnwrap(copyCode.action), to: copyCode.target, from: copyCode),
            "Copy Code must dispatch through AppKit",
        )
        XCTAssertEqual(model.feedback, .copied)

        XCTAssertTrue(
            try NSApp.sendAction(XCTUnwrap(copyMarkdown.action), to: copyMarkdown.target, from: copyMarkdown),
            "Copy Entire Message as Markdown must dispatch through AppKit",
        )
        XCTAssertEqual(model.feedback, .copied)

        XCTAssertTrue(
            try NSApp.sendAction(XCTUnwrap(copyPlain.action), to: copyPlain.target, from: copyPlain),
            "Copy Entire Message as Plain Text must dispatch through AppKit",
        )

        XCTAssertEqual(model.feedback, .copied)
        XCTAssertEqual(writes.value, [code, raw, plain])
        XCTAssertEqual(clearCount.value, 3)
    }

    /// CBW-001-render_assistant_markdown: code와 table만 child viewport에서 수평 overflow한다.
    /// 긴 code/table이 transcript 폭을 넓히지 않고 paragraph는 wrap하며 모든 child vertical scroll이 꺼져 있는지 검증합니다.
    /// - 검증 내용: 300자 code geometry, wrapped paragraph geometry, 12열 table policy와 scroller axis를 확인합니다.
    /// - 사전 조건: 120pt hosted viewport, 300자 unbroken code, 같은 paragraph와 12열 table metadata가 있습니다.
    /// - 기대 결과: code/table content width만 viewport보다 크고 paragraph는 viewport 폭에 맞으며 vertical scroller는 없습니다.
    func testRenderAssistantMarkdownConstrainsHorizontalOverflowToCodeAndTable() throws {
        let longText = String(repeating: "x", count: 300)
        let code = makeSelectableOutputHarness(text: longText, width: 120, allowsHorizontalOverflow: true)
        defer { code.window.close() }
        let paragraph = makeSelectableOutputHarness(text: longText, width: 120)
        defer { paragraph.window.close() }

        XCTAssertTrue(code.coordinator.scrollView.hasHorizontalScroller)
        XCTAssertFalse(code.coordinator.scrollView.hasVerticalScroller)
        XCTAssertGreaterThan(code.coordinator.textView.frame.width, code.coordinator.scrollView.contentSize.width)
        XCTAssertFalse(paragraph.coordinator.scrollView.hasHorizontalScroller)
        XCTAssertFalse(paragraph.coordinator.scrollView.hasVerticalScroller)
        XCTAssertEqual(
            paragraph.coordinator.textView.frame.width,
            paragraph.coordinator.scrollView.contentSize.width,
            accuracy: 0.5,
        )
        XCTAssertTrue(AiChatMarkdownBlockLayout.allowsHorizontalOverflow(for: .table))
        XCTAssertTrue(AiChatMarkdownBlockLayout.allowsHorizontalOverflow(for: .code))
        XCTAssertFalse(AiChatMarkdownBlockLayout.allowsHorizontalOverflow(for: .paragraph))
        XCTAssertFalse(AiChatMarkdownBlockLayout.ownsChildVerticalScroll)
        XCTAssertEqual(AiChatMarkdownAccessibility.tableValue(rowCount: 2, columnCount: 12), "표, 2행 12열")

        let tableSource = makeTwelveColumnTableSource()
            + "\n\n> " + String(repeating: "긴 인용문 ", count: 40)
        let renderer = makeAssistantMarkdownHarness(source: tableSource, width: 180)
        defer { renderer.window.close() }
        let scrollViews = descendantScrollViews(in: renderer.hostingView)
        let selectableScrollViews = scrollViews.compactMap {
            $0 as? AiChatSelectableOutputText.IntrinsicTextScrollView
        }

        XCTAssertEqual(renderer.hostingView.frame.width, 180, accuracy: 0.5)
        XCTAssertTrue(scrollViews.contains {
            !($0 is AiChatSelectableOutputText.IntrinsicTextScrollView) && $0.hasHorizontalScroller
        })
        XCTAssertFalse(scrollViews.contains(where: \.hasVerticalScroller))
        let quote = try XCTUnwrap(selectableScrollViews.first {
            ($0.documentView as? NSTextView)?.string.hasPrefix("긴 인용문") == true
        })
        XCTAssertFalse(quote.hasHorizontalScroller)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(quote.documentView as? NSTextView).frame.width,
            quote.contentSize.width + 0.5,
        )
    }

    /// CBW-001-render_assistant_markdown: code/table 접근성은 의미 정보와 단일 AppKit text owner를 제공한다.
    /// 원본 언어와 table 차원을 전달하면서 SwiftUI wrapper가 동일 text를 중복 소유하지 않는지 검증합니다.
    /// - 검증 내용: code accessibility label/value, table row/column value와 scroll/text owner 분리를 확인합니다.
    /// - 사전 조건: 원본 언어가 `Swift`인 code output과 2행 12열 table semantics가 있습니다.
    /// - 기대 결과: code label은 canonical 문자열이고 value는 payload이며 text view만 static-text element입니다.
    func testRenderAssistantMarkdownExposesCodeAndTableAccessibilityWithoutDuplicateTextOwner() throws {
        let code = makeAssistantMarkdownHarness(source: "```Swift\nlet value = 1\n```", width: 180)
        defer { code.window.close() }
        let codeScrollViews = descendantScrollViews(in: code.hostingView)
        let codeTextViews = codeScrollViews.compactMap {
            $0.documentView as? AiChatSelectableOutputText.OutputTextView
        }
        let codeTextView = try XCTUnwrap(
            codeTextViews.first { $0.string.hasPrefix("let value = 1") },
        )
        let codeScrollView = try XCTUnwrap(
            codeScrollViews.first { $0.documentView === codeTextView },
        )

        XCTAssertEqual(codeTextView.accessibilityLabel(), "코드 블록, Swift")
        XCTAssertEqual(codeTextView.accessibilityValue(), "let value = 1\n")
        XCTAssertTrue(codeTextView.isAccessibilityElement())
        XCTAssertEqual(codeTextView.accessibilityRole(), NSAccessibility.Role.staticText)
        XCTAssertFalse(codeScrollView.isAccessibilityElement())
        XCTAssertEqual(AiChatMarkdownAccessibility.tableValue(rowCount: 2, columnCount: 12), "표, 2행 12열")

        let table = makeAssistantMarkdownHarness(source: makeTwelveColumnTableSource(), width: 180)
        defer { table.window.close() }
        let tableScrollViews = descendantScrollViews(in: table.hostingView)
        let tableTextViews = tableScrollViews.compactMap {
            $0.documentView as? AiChatSelectableOutputText.OutputTextView
        }
        let intrinsicTableScrollViews = tableScrollViews.compactMap {
            $0 as? AiChatSelectableOutputText.IntrinsicTextScrollView
        }
        XCTAssertFalse(intrinsicTableScrollViews.contains { $0.isAccessibilityElement() })
        XCTAssertEqual(tableTextViews.count, 24)
        for cell in (1 ... 12).flatMap({ ["H\($0)", "V\($0)"] }) {
            let owners = tableTextViews.filter { $0.string == cell }
            XCTAssertEqual(owners.count, 1)
            XCTAssertTrue(owners.allSatisfy { $0.isAccessibilityElement() })
            XCTAssertTrue(owners.allSatisfy { $0.accessibilityRole() == .staticText })
        }
    }

    /// CBW-001-open_contextual_chat: transcript 검색 상태는 session-list 검색과 분리해 빈 query와 zero-result를 구분한다.
    /// 검색 열기·query·결과 projection·닫기 액션이 현재 session이나 scroll을 바꾸지 않는지 검증합니다.
    /// - 검증 내용: visibility, query, stale projection 무시, 0/0 no-result, 빈 query reset, close reset을 확인합니다.
    /// - 사전 조건: session-list query와 transcript scroll offset이 이미 존재하는 active chat입니다.
    /// - 기대 결과: transcript 검색만 전이되고 session-list query, session ID, scroll offset은 그대로 유지됩니다.
    func testOpenContextualChatKeepsTranscriptSearchSeparateAndDistinguishesEmptyFromNoResults() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let scrollOffsets: [AiChatSessionID: CGFloat] = [sessionID: 42]
        let store = makeTranscriptSearchStore(.init(
            mode: .chat,
            sessionList: .init(query: "history query"),
            sessionID: sessionID,
            transcriptScrollOffsets: scrollOffsets,
        ))
        let expectedContext = transcriptContext(of: store.state)

        await store.send(.transcriptSearchOpened) { state in
            state.transcriptSearch.isPresented = true
            state.transcriptSearch.focusRevision = 1
        }
        await store.send(.transcriptSearchQueryChanged("needle")) { state in
            state.transcriptSearch.query = "needle"
        }
        await store.send(.transcriptSearchMatchCountChanged(.init(
            query: "stale query",
            matchCount: 7,
        )))
        await store.send(.transcriptSearchMatchCountChanged(.init(
            query: "needle",
            matchCount: 0,
        ))) { state in
            state.transcriptSearch.matchCount = 0
            state.transcriptSearch.currentMatchOrdinal = 0
            state.transcriptSearch.status = .noResults
        }

        XCTAssertEqual(transcriptContext(of: store.state), expectedContext)

        await store.send(.transcriptSearchQueryChanged("")) { state in
            state.transcriptSearch.query = ""
            state.transcriptSearch.matchCount = nil
            state.transcriptSearch.currentMatchOrdinal = nil
            state.transcriptSearch.status = nil
        }
        await store.send(.transcriptSearchQueryChanged("again")) { state in
            state.transcriptSearch.query = "again"
        }
        await store.send(.transcriptSearchMatchCountChanged(.init(
            query: "again",
            matchCount: 2,
        ))) { state in
            state.transcriptSearch.matchCount = 2
            state.transcriptSearch.currentMatchOrdinal = 1
            state.transcriptSearch.status = .matches
        }
        await store.send(.transcriptSearchClosed) { state in
            state.transcriptSearch = .init()
        }

        XCTAssertEqual(transcriptContext(of: store.state), expectedContext)
    }

    /// CBW-001-open_contextual_chat: transcript 검색 이전·다음은 결과가 있을 때만 wrap하고 count 변화에 ordinal을 정규화한다.
    /// streaming projection으로 match가 늘거나 줄어도 현재 ordinal이 유효 범위를 벗어나지 않는지 검증합니다.
    /// - 검증 내용: previous/next 양방향 wrap, count growth 보존, shrink clamp, zero-result no-op을 확인합니다.
    /// - 사전 조건: non-empty query에 세 개의 rendered match가 projection된 상태입니다.
    /// - 기대 결과: 1-based ordinal은 wrap하며 결과가 0개가 되면 0/0 상태에서 탐색 액션이 no-op입니다.
    func testOpenContextualChatWrapsTranscriptMatchesAndNormalizesStreamingCountChanges() async {
        let store = makeTranscriptSearchStore(.init(
            mode: .chat,
            sessionID: AiChatSessionID(rawValue: UUID()),
        ))

        await store.send(.transcriptSearchOpened) { state in
            state.transcriptSearch.isPresented = true
            state.transcriptSearch.focusRevision = 1
        }
        await store.send(.transcriptSearchQueryChanged("match")) { state in
            state.transcriptSearch.query = "match"
        }
        await store.send(.transcriptSearchMatchCountChanged(.init(
            query: "match",
            matchCount: 3,
        ))) { state in
            state.transcriptSearch.matchCount = 3
            state.transcriptSearch.currentMatchOrdinal = 1
            state.transcriptSearch.status = .matches
        }
        await store.send(.transcriptSearchPreviousTapped) { state in
            state.transcriptSearch.currentMatchOrdinal = 3
        }
        await store.send(.transcriptSearchNextTapped) { state in
            state.transcriptSearch.currentMatchOrdinal = 1
        }
        await store.send(.transcriptSearchNextTapped) { state in
            state.transcriptSearch.currentMatchOrdinal = 2
        }
        await store.send(.transcriptSearchMatchCountChanged(.init(
            query: "match",
            matchCount: 5,
        ))) { state in
            state.transcriptSearch.matchCount = 5
        }
        await store.send(.transcriptSearchMatchCountChanged(.init(
            query: "match",
            matchCount: 1,
        ))) { state in
            state.transcriptSearch.matchCount = 1
            state.transcriptSearch.currentMatchOrdinal = 1
        }
        await store.send(.transcriptSearchMatchCountChanged(.init(
            query: "match",
            matchCount: 0,
        ))) { state in
            state.transcriptSearch.matchCount = 0
            state.transcriptSearch.currentMatchOrdinal = 0
            state.transcriptSearch.status = .noResults
        }
        await store.send(.transcriptSearchNextTapped)
        await store.send(.transcriptSearchPreviousTapped)
    }

    /// CBW-001-render_assistant_markdown: output이 first responder를 잃으면 보이는 selection이 fold된다.
    /// 사용자가 output 바깥을 클릭해 포커스를 옮길 때 읽기 전용 selection highlight가 사라지는지 검증합니다.
    /// - 검증 내용: first responder 전환 후 selectedRange 길이가 0이 되는 것을 확인합니다.
    /// - 사전 조건: hosted output block이 first responder이고 NFD+emoji substring이 선택되어 있습니다.
    /// - 기대 결과: 다른 responder로 포커스를 옮기면 output의 visible selection이 즉시 빈 range로 collapse합니다.
    func testRenderAssistantMarkdownCollapsesVisibleSelectionWhenOutputResignsFirstResponder() throws {
        let text = "앞 cafe\u{301} 👩‍💻 뒤"
        let selected = "cafe\u{301}"
        let harness = makeSelectableOutputHarness(text: text)
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let range = try XCTUnwrap(text.range(of: selected))
        let selection = try XCTUnwrap(
            AiChatMarkdownDocument.SearchRange(range, in: text).plainSelectionRange(in: text),
        )

        textView.setSelectedRange(selection.nsRange)
        XCTAssertTrue(harness.window.makeFirstResponder(textView))
        XCTAssertGreaterThan(textView.selectedRange().length, 0)

        let otherResponder = SelectableOutputFirstResponderAcceptingView()
        harness.window.contentView?.addSubview(otherResponder)
        XCTAssertTrue(harness.window.makeFirstResponder(otherResponder))

        XCTAssertEqual(textView.selectedRange().length, 0)
    }

    /// CBW-001-render_assistant_markdown: selection collapse는 Copy 동작이나 streaming update를 방해하지 않는다.
    /// 포커스 상태에서 native copy가 동작하고, stable streaming update는 selection을 그대로 보존하는지 검증합니다.
    /// - 검증 내용: first responder copy 동작, stable identity update 후 selection 유지, first responder 복귀를 확인합니다.
    /// - 사전 조건: 선택된 output block이 first responder이고 같은 identity의 suffix update가 준비되어 있습니다.
    /// - 기대 결과: copy는 선택 substring을 내보내고 stable update 뒤에도 exact selection과 first responder가 유지됩니다.
    func testRenderAssistantMarkdownSelectionCollapseKeepsNativeCopyAndStableUpdateIntact() throws {
        let initial = "앞 cafe\u{301} 👩‍💻 뒤"
        let selected = "cafe\u{301} 👩‍💻"
        let blockID = AiChatMarkdownDocument.BlockID(rawValue: "stable-collapse-block")
        let harness = makeSelectableOutputHarness(text: initial, blockID: blockID)
        defer { harness.window.close() }
        let textView = harness.coordinator.textView
        let range = try XCTUnwrap(initial.range(of: selected))
        let selection = try XCTUnwrap(
            AiChatMarkdownDocument.SearchRange(range, in: initial).plainSelectionRange(in: initial),
        )

        textView.setSelectedRange(selection.nsRange)
        XCTAssertTrue(harness.window.makeFirstResponder(textView))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        textView.copy(nil as Any?)
        XCTAssertEqual(pasteboard.string(forType: .string), selected)

        harness.coordinator.update(
            blockID: blockID,
            attributedText: NSAttributedString(string: initial + " 추가"),
        )
        XCTAssertEqual(try selectedSubstring(in: textView), selected)
        XCTAssertIdentical(harness.window.firstResponder, textView)
    }

    /// CBW-001-render_assistant_markdown: dismantle은 포커스를 잃기 전 selection snapshot을 보존한다.
    /// view detach 중에 resignFirstResponder가 먼저 불려도 capture-then-suppress 계약이 유지되는지 검증합니다.
    /// - 검증 내용: prepareForDismantle 후 render session restoration이 캡처한 selection을 반환하는지 확인합니다.
    /// - 사전 조건: render session과 transcript row가 연결된 hosted block이 first responder이고 selection이 있습니다.
    /// - 기대 결과: dismantle 직후 snapshot에서 복원된 selection이 dismantle 전 사용자 selection과 같습니다.
    func testRenderAssistantMarkdownPreservesSelectionSnapshotAcrossDismantleCapture() throws {
        let renderSession = AiChatAssistantMarkdownRenderSession(highlightingClient: .testing(
            coalescingDelay: .zero,
            supportedLanguages: { [] },
            highlight: { _, _, _ in [] },
        ))
        let transcriptRow = AiChatTranscriptRowDiscriminator.message(index: 0)
        let text = "앞 cafe\u{301} 👩‍💻 뒤"
        let selected = "cafe\u{301}"

        let rendered = renderSession.render(content: text, transcriptRow: transcriptRow)
        let blockID = try XCTUnwrap(rendered.blocks.first).presentationID

        let coordinator = AiChatSelectableOutputText.Coordinator()
        coordinator.scrollView.frame = NSRect(x: 0, y: 0, width: 240, height: 120)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.scrollView
        coordinator.update(
            blockID: blockID,
            attributedText: NSAttributedString(string: text),
            renderSession: renderSession,
            transcriptRow: transcriptRow,
        )
        coordinator.scrollView.layoutSubtreeIfNeeded()
        defer { window.close() }

        let textView = coordinator.textView
        let range = try XCTUnwrap(text.range(of: selected))
        let selection = try XCTUnwrap(
            AiChatMarkdownDocument.SearchRange(range, in: text).plainSelectionRange(in: text),
        )
        textView.setSelectedRange(selection.nsRange)
        XCTAssertTrue(window.makeFirstResponder(textView))

        coordinator.prepareForDismantle()

        let restoration = renderSession.restoration(presentationID: blockID, transcriptRow: transcriptRow)
        XCTAssertEqual(restoration?.selection, selection)
    }

    /// CBW-001-render_assistant_markdown: user/request selectable surface 선택은 render session에 view state를 캡처한다.
    /// assistant block과 동일하게 hosted user-message selectable surface의 selection이 정확한 Unicode substring과
    /// outer scroll 문맥을 보존하며, selection 해제 시 캡처된 state가 clear되는지 검증합니다.
    /// - 검증 내용: hasCapturedViewState 전환, exact NFD/emoji selected substring, outer scroll offset 보존,
    ///   resign 후 captured state clear를 확인합니다.
    /// - 사전 조건: message.content를 plain/search projection으로 등록한 user-message block이 hosted output에 연결되어 있습니다.
    /// - 기대 결과: Coordinator capture path를 통해 selection이 캡처되고 exact substring과 outer offset이 복원되며,
    ///   selection 해제 시 hasCapturedViewState가 false로 돌아갑니다.
    func testRenderUserMessageSelectionCapturesViewStateAndPreservesExactSubstring() throws {
        let renderSession = AiChatAssistantMarkdownRenderSession(highlightingClient: .testing(
            coalescingDelay: .zero,
            supportedLanguages: { [] },
            highlight: { _, _, _ in [] },
        ))
        let transcriptRow = AiChatTranscriptRowDiscriminator.message(index: 0)
        let text = "앞 cafe\u{301} 👩‍💻 뒤"
        let selected = "cafe\u{301} 👩‍💻"
        let blockID = AiChatMarkdownDocument.BlockID(rawValue: "user-message-0")

        // production userMessage 표면과 동일하게 message.content를 plain/search projection으로 등록한다.
        renderSession.registerSelectionProjection(
            presentationID: blockID,
            plainText: text,
            searchText: text,
            transcriptRow: transcriptRow,
            blockIndex: 0,
        )

        let coordinator = AiChatSelectableOutputText.Coordinator()
        coordinator.scrollView.frame = NSRect(x: 0, y: 0, width: 240, height: 120)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.scrollView
        coordinator.update(
            blockID: blockID,
            attributedText: NSAttributedString(string: text),
            renderSession: renderSession,
            transcriptRow: transcriptRow,
            sizingMode: .fitsContent,
        )
        coordinator.scrollView.layoutSubtreeIfNeeded()
        defer { window.close() }

        XCTAssertFalse(renderSession.hasCapturedViewState, "선택 전에는 캡처된 view state가 없어야 한다")

        let textView = coordinator.textView
        let range = try XCTUnwrap(text.range(of: selected))
        let selection = try XCTUnwrap(
            AiChatMarkdownDocument.SearchRange(range, in: text).plainSelectionRange(in: text),
        )
        textView.setSelectedRange(selection.nsRange)
        XCTAssertTrue(window.makeFirstResponder(textView))

        XCTAssertTrue(renderSession.hasCapturedViewState, "Coordinator capture path 후에는 view state가 캡처되어야 한다")

        // outer scroll 문맥이 보존되는지 검증하기 위해 transcript scroll observer가 호출하는 API로 offset을 기록한다.
        let outerOffset: CGFloat = 64
        renderSession.captureContext(outerScrollOffset: outerOffset, currentSearchDescriptor: nil)

        let restoration = try XCTUnwrap(
            renderSession.restoration(presentationID: blockID, transcriptRow: transcriptRow),
        )
        let restoredSearchRange = try XCTUnwrap(
            restoration.selection?.searchRange(in: text, invalidRangePolicy: .discard),
        )
        XCTAssertEqual(
            restoredSearchRange.substring(in: text),
            selected,
            "exact NFD/emoji selected substring가 보존되어야 한다",
        )
        XCTAssertEqual(restoration.outerScrollOffset, outerOffset, "outer scroll offset이 보존되어야 한다")
        XCTAssertTrue(restoration.isFirstResponder, "first responder 상태가 보존되어야 한다")

        // selection 해제(포커스 이탈) 시 캡처된 state가 clear되는지 검증한다.
        // resignFirstResponder 직후에는 window.firstResponder가 아직 변경 전이므로 isFirstResponder가
        // true로 평가된다. production에서는 이후 updateNSView 주기의 captureSelection()이 empty selection과
        // 함께 clearViewState를 호출한다. 동일한 Coordinator capture path로 이 주기를 재현한다.
        let otherResponder = SelectableOutputFirstResponderAcceptingView()
        window.contentView?.addSubview(otherResponder)
        XCTAssertTrue(window.makeFirstResponder(otherResponder))
        coordinator.captureSelection()

        XCTAssertFalse(renderSession.hasCapturedViewState, "selection 해제 후에는 캡처된 view state가 clear되어야 한다")
    }

    /// CBW-001-render_assistant_markdown: transcript scroll observer는 저장 offset을 첫 게시로 적용한다.
    /// 대기 중인 restore가 있을 때 초기 top=0이 reducer로 게시되는 race를 방지하는지 검증합니다.
    /// - 검증 내용: attach 직후 offset 게시가 비어있고 restore 적용 후 첫 게시가 저장된 nonzero offset인지 확인합니다.
    /// - 사전 조건: 1000pt document, 200pt viewport에 session A의 120pt restore 요청이 대기 중입니다.
    /// - 기대 결과: attach는 아무것도 게시하지 않고 restore 이후 첫 게시가 정확히 120pt가 됩니다.
    func testRenderAssistantMarkdownTranscriptObserverAppliesSavedOffsetBeforePublishingInitialZero() throws {
        let sessionA = AiChatSessionID(rawValue: UUID())
        var published: [(offset: CGFloat, session: AiChatSessionID?)] = []
        let coordinator = AiChatTranscriptScrollObserver.Coordinator()
        coordinator.sessionID = sessionA
        coordinator.onScrollOffsetChanged = { offset, session in
            published.append((offset, session))
        }

        let scrollView = makeTranscriptScrollHarnessScrollView(
            documentHeight: 1000,
            viewportHeight: 200,
        )
        let host = NSView(frame: .zero)
        scrollView.documentView?.addSubview(host)

        let request = AiChatTranscriptScrollRestoreRequest(
            sessionID: sessionA,
            offsetY: 120,
            sequence: 1,
        )
        coordinator.restoreRequest = request

        coordinator.attachScrollView(from: host)
        XCTAssertTrue(published.isEmpty, "pending restore가 있을 때 초기 offset을 게시하면 안 된다")

        coordinator.applyPendingRestoreIfNeeded()
        flushMainRunLoop()

        let firstPublished = try XCTUnwrap(published.first)
        XCTAssertEqual(firstPublished.session, sessionA)
        XCTAssertEqual(firstPublished.offset, 120, accuracy: 0.5)
    }

    /// CBW-001-render_assistant_markdown: session 전환은 각 session의 저장 offset을 복원하고 이후 사용자 scroll을 게시한다.
    /// session switch restore와 정상 사용자 scroll publish가 함께 보존되는지 검증합니다.
    /// - 검증 내용: session B restore offset 적용, 이후 사용자 scroll의 현재 session offset 게시를 확인합니다.
    /// - 사전 조건: 두 session A/B에 서로 다른 restore offset이 있고 scroll observer가 A를 이미 복원한 상태입니다.
    /// - 기대 결과: B 전환 시 B의 offset으로 복원하고 사용자 scroll은 B의 현재 offset을 게시합니다.
    func testRenderAssistantMarkdownTranscriptObserverRestoresPerSessionOffsetAndPublishesUserScroll() throws {
        let sessionA = AiChatSessionID(rawValue: UUID())
        let sessionB = AiChatSessionID(rawValue: UUID())
        var published: [(offset: CGFloat, session: AiChatSessionID?)] = []
        let coordinator = AiChatTranscriptScrollObserver.Coordinator()
        coordinator.onScrollOffsetChanged = { offset, session in
            published.append((offset, session))
        }

        let scrollView = makeTranscriptScrollHarnessScrollView(
            documentHeight: 1000,
            viewportHeight: 200,
        )
        let host = NSView(frame: .zero)
        scrollView.documentView?.addSubview(host)

        coordinator.sessionID = sessionA
        coordinator.restoreRequest = .init(sessionID: sessionA, offsetY: 100, sequence: 1)
        coordinator.attachScrollView(from: host)
        coordinator.applyPendingRestoreIfNeeded()
        flushMainRunLoop()
        published.removeAll()

        coordinator.sessionID = sessionB
        coordinator.restoreRequest = .init(sessionID: sessionB, offsetY: 200, sequence: 2)
        coordinator.applyPendingRestoreIfNeeded()
        flushMainRunLoop()

        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 200, accuracy: 0.5)
        let restoredBOffset = try XCTUnwrap(
            published.last(where: { $0.session == sessionB }),
            "session B restore offset이 게시되어야 한다",
        )
        XCTAssertEqual(restoredBOffset.offset, 200, accuracy: 0.5)

        published.removeAll()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 50))
        flushMainRunLoop()

        let userScrollOffset = try XCTUnwrap(published.first)
        XCTAssertEqual(userScrollOffset.offset, 50, accuracy: 0.5)
        XCTAssertEqual(userScrollOffset.session, sessionB)
    }

    /// CBW-001-render_assistant_markdown: 빠른 session 전환 중 이전 session의 offset이 새 session으로 게시되지 않는다.
    /// restore generation 추적이 rapid switch race에서 stale offset cross-contamination을 방지하는지 검증합니다.
    /// - 검증 내용: A offset이 B session으로 게시 부재, 최종 게시가 B offset, 이후 사용자 scroll이 B로 게시를 확인합니다.
    /// - 사전 조건: session A restore를 예약하고 runloop flush 전 session B로 전환한 뒤 B restore도 예약합니다.
    /// - 기대 결과: flush 후 A의 offset이 B session으로 게시되지 않고 최종 viewport와 게시가 B의 offset입니다.
    func testRenderAssistantMarkdownTranscriptObserverRapidSessionSwitchDoesNotPublishStaleOffset() throws {
        let sessionA = AiChatSessionID(rawValue: UUID())
        let sessionB = AiChatSessionID(rawValue: UUID())
        var published: [(offset: CGFloat, session: AiChatSessionID?)] = []
        let coordinator = AiChatTranscriptScrollObserver.Coordinator()
        coordinator.onScrollOffsetChanged = { offset, session in
            published.append((offset, session))
        }

        let scrollView = makeTranscriptScrollHarnessScrollView(
            documentHeight: 1000,
            viewportHeight: 200,
        )
        let host = NSView(frame: .zero)
        scrollView.documentView?.addSubview(host)

        coordinator.sessionID = sessionA
        coordinator.restoreRequest = .init(sessionID: sessionA, offsetY: 100, sequence: 1)
        coordinator.attachScrollView(from: host)
        coordinator.applyPendingRestoreIfNeeded()

        // runloop flush 전 session B로 전환하고 B restore도 예약한다.
        coordinator.sessionID = sessionB
        coordinator.restoreRequest = .init(sessionID: sessionB, offsetY: 200, sequence: 2)
        coordinator.applyPendingRestoreIfNeeded()

        flushMainRunLoop()

        let aOffsetPublishedAsB = published.filter {
            $0.session == sessionB && abs($0.offset - 100) < 1
        }
        XCTAssertTrue(
            aOffsetPublishedAsB.isEmpty,
            "A의 offset(100)이 B session으로 게시되면 안 된다",
        )

        let bOffsets = published.filter { $0.session == sessionB }
        let finalBOffset = try XCTUnwrap(bOffsets.last, "B의 restore offset이 게시되어야 한다")
        XCTAssertEqual(finalBOffset.offset, 200, accuracy: 0.5)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 200, accuracy: 0.5)

        published.removeAll()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 50))
        flushMainRunLoop()

        let userScrollOffset = try XCTUnwrap(published.first)
        XCTAssertEqual(userScrollOffset.offset, 50, accuracy: 0.5)
        XCTAssertEqual(userScrollOffset.session, sessionB)
    }

    /// CBW-001-render_assistant_markdown: probe가 늦게 scroll 계층에 편입되어도 저장 offset을 첫 게시로 복원한다.
    /// lifecycle-driven probe가 fixed timing 가정을 제거해 임의 시점 부착도 restore를 놓치지 않는지 검증합니다.
    /// - 검증 내용: 부착 전 빈 게시, 늦은 부착 후 첫 게시가 저장 nonzero offset, 초기 0 부재를 확인합니다.
    /// - 사전 조건: probe가 계층에 없는 상태에서 session A의 120pt restore가 대기합니다.
    /// - 기대 결과: probe가 scroll 계층에 편입된 직후 첫 게시가 정확히 120pt이고 초기 0은 없습니다.
    func testRenderAssistantMarkdownTranscriptObserverLateAttachmentRestoresSavedOffsetWithoutInitialZero() throws {
        let sessionA = AiChatSessionID(rawValue: UUID())
        var published: [(offset: CGFloat, session: AiChatSessionID?)] = []
        let coordinator = AiChatTranscriptScrollObserver.Coordinator()
        coordinator.sessionID = sessionA
        coordinator.onScrollOffsetChanged = { offset, session in
            published.append((offset, session))
        }
        coordinator.restoreRequest = .init(sessionID: sessionA, offsetY: 120, sequence: 1)

        let probe = AiChatTranscriptScrollProbeView()
        coordinator.configureProbe(probe)
        flushMainRunLoop()

        XCTAssertTrue(published.isEmpty, "probe가 계층에 없을 때 게시하면 안 된다")

        let scrollView = makeTranscriptScrollHarnessScrollView(documentHeight: 1000, viewportHeight: 200)
        scrollView.documentView?.addSubview(probe)
        flushMainRunLoop()

        let firstPublished = try XCTUnwrap(published.first)
        XCTAssertEqual(firstPublished.session, sessionA)
        XCTAssertEqual(firstPublished.offset, 120, accuracy: 0.5)
    }

    /// CBW-001-render_assistant_markdown: 부착 전 A→B supersedes 시 늦은 부착에서 B만 복원한다.
    /// 미부착 상태의 session 전환이 late attach 시 generation 추적으로 올바르게 처리되는지 검증합니다.
    /// - 검증 내용: A offset이 게시 부재, B 최종 offset/session 게시, 이후 user scroll이 B로 게시를 확인합니다.
    /// - 사전 조건: probe 미부착 상태에서 A restore 후 B로 전환한 뒤 probe를 계층에 편입합니다.
    /// - 기대 결과: A offset은 게시되지 않고 B의 offset만 B session으로 게시됩니다.
    func testRenderAssistantMarkdownTranscriptObserverLateAttachAfterSupersedeRestoresOnlyLatestSession() throws {
        let sessionA = AiChatSessionID(rawValue: UUID())
        let sessionB = AiChatSessionID(rawValue: UUID())
        var published: [(offset: CGFloat, session: AiChatSessionID?)] = []
        let coordinator = AiChatTranscriptScrollObserver.Coordinator()
        coordinator.onScrollOffsetChanged = { offset, session in
            published.append((offset, session))
        }

        let probe = AiChatTranscriptScrollProbeView()
        coordinator.sessionID = sessionA
        coordinator.restoreRequest = .init(sessionID: sessionA, offsetY: 100, sequence: 1)
        coordinator.configureProbe(probe)
        flushMainRunLoop()

        coordinator.sessionID = sessionB
        coordinator.restoreRequest = .init(sessionID: sessionB, offsetY: 200, sequence: 2)
        coordinator.configureProbe(probe)
        flushMainRunLoop()

        XCTAssertTrue(published.isEmpty, "probe 미부착 시 게시하면 안 된다")

        let scrollView = makeTranscriptScrollHarnessScrollView(documentHeight: 1000, viewportHeight: 200)
        scrollView.documentView?.addSubview(probe)
        flushMainRunLoop()

        let aOffsets = published.filter { $0.session == sessionA }
        XCTAssertTrue(aOffsets.isEmpty, "A의 offset은 게시되면 안 된다")
        let bOffsets = published.filter { $0.session == sessionB }
        let finalBOffset = try XCTUnwrap(bOffsets.last, "B의 restore offset이 게시되어야 한다")
        XCTAssertEqual(finalBOffset.offset, 200, accuracy: 0.5)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 200, accuracy: 0.5)
    }

    // MARK: - CBW-001-submit_chat_request

    /// CBW-001-submit_chat_request: composer는 placeholder와 tooltip 기반 Enter/Shift+Enter 안내를 제공한다.
    /// 사용자가 hover 및 VoiceOver로 입력 방법과 현재 send/stop action을 구분할 수 있는지 검증합니다.
    /// - 검증 내용: placeholder, input hint, send tooltip, stop tooltip 문자열을 확인합니다.
    /// - 사전 조건: idle composer display model과 stop mode로 전환한 동일 display model을 구성합니다.
    /// - 기대 결과: Ask anything… 정책과 send/stop별 안내가 정확한 canonical copy를 반환합니다.
    func testSubmitChatRequestComposerGuidanceUsesCanonicalCopyForSendAndStop() {
        let input = AiChatFeature.State().chatInputDisplayModel

        XCTAssertEqual(input.placeholder, "Ask anything…")
        XCTAssertEqual(input.inputAccessibilityHint, "Enter to send, Shift+Enter for new line")
        XCTAssertEqual(input.actionHelp, "Enter to send, Shift+Enter for new line")

        var stopInput = input
        stopInput.isStopVisible = true
        XCTAssertEqual(stopInput.actionHelp, "Stop generating response")
    }

    /// CBW-001-submit_chat_request: Chat Field는 46pt에서 160pt까지 성장하고 이후 내부 스크롤을 사용한다.
    /// 사용자가 짧은 메시지부터 긴 다중 행 메시지까지 입력할 때 composer 외부 높이와 내부 탐색 계약을 검증합니다.
    /// - 검증 내용: 최소/최대 높이 상수, TextKit 측정 높이, clamp 결과, vertical scroller 활성화를 확인합니다.
    /// - 사전 조건: 180pt 너비의 AppKit text view와 짧은 입력, 중간 다중 행 입력, 160pt를 넘는 긴 입력을 구성합니다.
    /// - 기대 결과: 외부 높이는 46...160pt로 제한되고 160pt 초과 콘텐츠는 내부 세로 스크롤을 활성화합니다.
    func testSubmitChatRequestInputGrowsToMaximumThenEnablesInternalScrolling() async {
        let harness = InputTextViewHarness()

        XCTAssertEqual(AiChatView.chatInputMinTextHeight, 46)
        XCTAssertEqual(AiChatView.chatInputMaxTextHeight, 160)

        let shortHeight = await harness.measure("Short")
        XCTAssertEqual(harness.boundedHeight(for: shortHeight), 46)
        XCTAssertFalse(harness.scrollView.hasVerticalScroller)

        let growingHeight = await harness.measure(Array(repeating: "Growing line", count: 5).joined(separator: "\n"))
        XCTAssertGreaterThan(growingHeight, AiChatView.chatInputMinTextHeight)
        XCTAssertLessThan(growingHeight, AiChatView.chatInputMaxTextHeight)
        XCTAssertEqual(harness.boundedHeight(for: growingHeight), growingHeight)
        XCTAssertFalse(harness.scrollView.hasVerticalScroller)

        let overflowingHeight = await harness.measure(String(repeating: "A long wrapped request ", count: 100))
        XCTAssertGreaterThan(overflowingHeight, AiChatView.chatInputMaxTextHeight)
        XCTAssertEqual(harness.boundedHeight(for: overflowingHeight), 160)
        XCTAssertTrue(harness.scrollView.hasVerticalScroller)
    }

    /// CBW-001-submit_chat_request: marked text 조합 중 Enter는 조합 문자열만 확정한다.
    /// 한글·일본어 입력기가 조합 문자열을 확정할 때 Enter가 요청 제출이나 줄바꿈으로 처리되지 않는지 검증합니다.
    /// - 검증 내용: AppKit fallback을 포함한 command 처리 결과, 조합 문자열, marked text, submit 횟수를 확인합니다.
    /// - 사전 조건: AppKit text view에 marked text `ㅎ`를 설정하고 insertNewline command를 전달합니다.
    /// - 기대 결과: command는 처리되고 `ㅎ`는 보존·확정되며 submit과 줄바꿈은 발생하지 않습니다.
    func testSubmitChatRequestCommitsMarkedTextWithoutSubmittingOrInsertingNewline() {
        let harness = InputTextViewHarness()
        harness.textView.setMarkedText(
            "ㅎ",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertTrue(harness.textView.hasMarkedText())

        let handled = harness.pressEnterThroughAppKitFallback()

        XCTAssertTrue(handled)
        XCTAssertEqual(harness.textView.string, "ㅎ")
        XCTAssertFalse(harness.textView.hasMarkedText())
        XCTAssertEqual(harness.state.submitCount, 0)
        XCTAssertFalse(harness.textView.string.contains("\n"))
    }

    /// CBW-001-submit_chat_request: bare Enter는 기존 submit callback을 한 번 호출한다.
    /// 조합 중이 아니고 modifier가 없는 사용자의 Enter 제출 경로가 유지되는지 검증합니다.
    /// - 검증 내용: insertNewline command 처리 결과와 submit callback 호출 횟수를 확인합니다.
    /// - 사전 조건: marked text가 없고 modifier가 없는 text view command를 구성합니다.
    /// - 기대 결과: command는 처리되며 submit callback이 정확히 한 번 호출됩니다.
    func testSubmitChatRequestBareEnterSubmits() {
        let harness = InputTextViewHarness()

        let handled = harness.coordinator.handleNewlineCommand(
            in: harness.textView,
            modifierFlags: [],
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(AiChatInputTextView.Coordinator.newlineCommand(for: []), .submit)
        XCTAssertEqual(harness.state.submitCount, 1)
        XCTAssertEqual(harness.textView.string, "")
    }

    /// CBW-001-submit_chat_request: Shift+Enter는 submit하지 않고 줄바꿈을 삽입한다.
    /// 사용자가 요청 내용을 여러 줄로 작성할 때 Shift modifier가 기존 newline 계약을 유지하는지 검증합니다.
    /// - 검증 내용: Shift command 분류, text view 문자열, submit callback 호출 횟수를 확인합니다.
    /// - 사전 조건: AppKit text view와 Shift modifier가 포함된 newline command를 구성합니다.
    /// - 기대 결과: 문자열에 줄바꿈이 삽입되고 submit callback은 호출되지 않습니다.
    func testSubmitChatRequestShiftEnterInsertsNewlineWithoutSubmitting() {
        let harness = InputTextViewHarness()

        let handled = harness.coordinator.handleNewlineCommand(
            in: harness.textView,
            modifierFlags: .shift,
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(AiChatInputTextView.Coordinator.newlineCommand(for: .shift), .insertNewline)
        XCTAssertEqual(harness.state.submitCount, 0)
        XCTAssertEqual(harness.textView.string, "\n")
    }

    /// CBW-001-submit_chat_request: Option+Enter는 기존 줄바꿈 동작을 유지한다.
    /// 기존 macOS modifier 계약이 Task 1 변경으로 submit 동작에 흡수되지 않는지 회귀 검증합니다.
    /// - 검증 내용: Option command 분류, text view 문자열, submit callback 호출 횟수를 확인합니다.
    /// - 사전 조건: AppKit text view와 Option modifier가 포함된 newline command를 구성합니다.
    /// - 기대 결과: 문자열에 줄바꿈이 삽입되고 submit callback은 호출되지 않습니다.
    func testSubmitChatRequestOptionEnterPreservesNewlineWithoutSubmitting() {
        let harness = InputTextViewHarness()

        let handled = harness.coordinator.handleNewlineCommand(
            in: harness.textView,
            modifierFlags: .option,
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(AiChatInputTextView.Coordinator.newlineCommand(for: .option), .insertNewline)
        XCTAssertEqual(harness.state.submitCount, 0)
        XCTAssertEqual(harness.textView.string, "\n")
    }

    private func syntaxHighlightingRequest(
        identity: String,
        code: String,
        generation: UInt64,
        languageLabel: String? = "swift",
    ) -> AiChatSyntaxHighlightingClient.Request {
        .init(
            identity: .init(rawValue: identity),
            code: code,
            languageLabel: languageLabel,
            appearance: .light,
            typographyVersion: 1,
            generation: generation,
        )
    }

    private func assertIndependentSyntaxHighlightingReverseCompletion() async {
        let recorder = SyntaxHighlightingRecorder(suspends: true)
        let client = makeSyntaxHighlightingClient(recorder: recorder)
        let firstRequest = syntaxHighlightingRequest(identity: "block-a", code: "let a = 1", generation: 1)
        let secondRequest = syntaxHighlightingRequest(identity: "block-b", code: "let b = 2", generation: 1)
        let firstTask = Task { await client.highlight(firstRequest) }
        await waitForSyntaxHighlightingCalls(1, recorder: recorder)
        let secondTask = Task { await client.highlight(secondRequest) }
        await waitForSyntaxHighlightingCalls(2, recorder: recorder)

        await recorder.resume(code: secondRequest.code)
        let second = await secondTask.value
        await recorder.resume(code: firstRequest.code)
        let first = await firstTask.value
        _ = await client.highlight(syntaxHighlightingRequest(
            identity: "block-a", code: firstRequest.code, generation: 2,
        ))
        _ = await client.highlight(syntaxHighlightingRequest(
            identity: "block-b", code: secondRequest.code, generation: 2,
        ))
        let metrics = await client.cacheMetrics()
        let invocationCount = await recorder.invocationCount()

        XCTAssertEqual(first.disposition, .highlighted)
        XCTAssertTrue(first.isEligibleForDisplay)
        XCTAssertEqual(second.disposition, .highlighted)
        XCTAssertTrue(second.isEligibleForDisplay)
        XCTAssertEqual(metrics.entryCount, 2)
        XCTAssertEqual(invocationCount, 2)
    }

    private func assertSyntaxHighlightingFallbackIdentityIsolation() async {
        let recorder = SyntaxHighlightingRecorder(suspends: true)
        let client = makeSyntaxHighlightingClient(recorder: recorder)
        let activeRequest = syntaxHighlightingRequest(identity: "active", code: "let active = true", generation: 1)
        let activeTask = Task { await client.highlight(activeRequest) }
        await waitForSyntaxHighlightingCalls(1, recorder: recorder)
        let missingSource = "plain source"
        let missing = await client.highlight(syntaxHighlightingRequest(
            identity: "fallback", code: missingSource, generation: 1, languageLabel: nil,
        ))
        let oversizedSource = String(repeating: "x", count: 65537)
        let oversized = await client.highlight(syntaxHighlightingRequest(
            identity: "fallback", code: oversizedSource, generation: 2,
        ))

        await recorder.resume(code: activeRequest.code)
        let active = await activeTask.value
        _ = await client.highlight(syntaxHighlightingRequest(
            identity: "active", code: activeRequest.code, generation: 2,
        ))
        let invocationCount = await recorder.invocationCount()

        XCTAssertEqual(missing.disposition, .plain(.missingLanguage))
        assertExactPlainSyntaxResult(missing, source: missingSource)
        XCTAssertEqual(oversized.disposition, .plain(.preflightLimit))
        assertExactPlainSyntaxResult(oversized, source: oversizedSource)
        XCTAssertEqual(active.disposition, .highlighted)
        XCTAssertTrue(active.isEligibleForDisplay)
        XCTAssertEqual(invocationCount, 1)
    }

    private func assertSyntaxHighlightingLateFailureIsStale() async {
        let recorder = SyntaxHighlightingRecorder(suspends: true)
        let client = makeSyntaxHighlightingClient(recorder: recorder)
        let olderRequest = syntaxHighlightingRequest(identity: "shared", code: "let old = 1", generation: 1)
        let latestRequest = syntaxHighlightingRequest(identity: "shared", code: "let new = 2", generation: 2)
        let olderTask = Task { await client.highlight(olderRequest) }
        await waitForSyntaxHighlightingCalls(1, recorder: recorder)
        let latestTask = Task { await client.highlight(latestRequest) }
        await waitForSyntaxHighlightingCalls(2, recorder: recorder)

        await recorder.resume(code: latestRequest.code)
        let latest = await latestTask.value
        olderTask.cancel()
        await recorder.fail(code: olderRequest.code, with: .highlight)
        let older = await olderTask.value
        _ = await client.highlight(syntaxHighlightingRequest(
            identity: "shared", code: latestRequest.code, generation: 3,
        ))
        let metrics = await client.cacheMetrics()
        let invocationCount = await recorder.invocationCount()

        XCTAssertEqual(latest.disposition, .highlighted)
        XCTAssertTrue(latest.isEligibleForDisplay)
        XCTAssertEqual(older.disposition, .stale)
        XCTAssertFalse(older.isEligibleForDisplay)
        XCTAssertEqual(metrics.entryCount, 1)
        XCTAssertEqual(invocationCount, 2)
    }

    private func assertSyntaxHighlightingRejectsLateLowerGeneration() async {
        let recorder = SyntaxHighlightingRecorder()
        let client = makeSyntaxHighlightingClient(recorder: recorder)
        let source = "let monotonic = true"
        let high = await client.highlight(syntaxHighlightingRequest(
            identity: "monotonic", code: source, generation: 2,
        ))
        let lower = await client.highlight(syntaxHighlightingRequest(
            identity: "monotonic", code: source, generation: 1,
        ))
        let latest = await client.highlight(syntaxHighlightingRequest(
            identity: "monotonic", code: source, generation: 3,
        ))
        let invocationCount = await recorder.invocationCount()

        XCTAssertEqual(high.disposition, .highlighted)
        XCTAssertEqual(lower.disposition, .stale)
        XCTAssertFalse(lower.isEligibleForDisplay)
        XCTAssertEqual(latest.disposition, .highlighted)
        XCTAssertTrue(latest.isEligibleForDisplay)
        XCTAssertEqual(invocationCount, 1)
    }

    private func assertSyntaxHighlightingTrailingEdgeCoalescing() async throws {
        let recorder = SyntaxHighlightingRecorder()
        let client = makeSyntaxHighlightingClient(
            recorder: recorder,
            coalescingDelay: .milliseconds(80),
        )
        let firstTask = Task {
            await client.highlight(.init(
                identity: .init(rawValue: "test-block"),
                code: "let first = 1",
                languageLabel: "swift",
                appearance: .light,
                typographyVersion: 1,
                generation: 1,
            ))
        }
        try await ContinuousClock().sleep(for: .milliseconds(10))
        let secondTask = Task {
            await client.highlight(.init(
                identity: .init(rawValue: "test-block"),
                code: "let second = 2",
                languageLabel: "swift",
                appearance: .light,
                typographyVersion: 1,
                generation: 2,
            ))
        }
        let first = await firstTask.value
        let second = await secondTask.value
        let invocationCount = await recorder.invocationCount()

        XCTAssertEqual(first.disposition, .stale)
        XCTAssertFalse(first.isEligibleForDisplay)
        XCTAssertEqual(second.disposition, .highlighted)
        XCTAssertEqual(invocationCount, 1)
    }

    private func assertSyntaxHighlightingStaleGenerationDiscard() async {
        let recorder = SyntaxHighlightingRecorder(suspends: true)
        let client = makeSyntaxHighlightingClient(recorder: recorder)
        let olderTask = Task {
            await client.highlight(.init(
                identity: .init(rawValue: "test-block"),
                code: "let older = 1",
                languageLabel: "swift",
                appearance: .light,
                typographyVersion: 1,
                generation: 10,
            ))
        }
        await waitForSyntaxHighlightingCalls(1, recorder: recorder)
        let latestTask = Task {
            await client.highlight(.init(
                identity: .init(rawValue: "test-block"),
                code: "let latest = 2",
                languageLabel: "swift",
                appearance: .light,
                typographyVersion: 1,
                generation: 11,
            ))
        }
        await waitForSyntaxHighlightingCalls(2, recorder: recorder)
        await recorder.resume(code: "let older = 1")
        let older = await olderTask.value
        await recorder.resume(code: "let latest = 2")
        let latest = await latestTask.value
        let metrics = await client.cacheMetrics()

        XCTAssertEqual(older.disposition, .stale)
        XCTAssertFalse(older.isEligibleForDisplay)
        XCTAssertEqual(latest.disposition, .highlighted)
        XCTAssertTrue(latest.isEligibleForDisplay)
        XCTAssertEqual(metrics.entryCount, 1)
    }

    private func makeSyntaxHighlightingClient(
        recorder: SyntaxHighlightingRecorder,
        coalescingDelay: Duration = .zero,
    ) -> AiChatSyntaxHighlightingClient {
        AiChatSyntaxHighlightingClient.testing(
            coalescingDelay: coalescingDelay,
            supportedLanguages: { ["swift", "javascript"] },
            highlight: { code, language, theme in
                try await recorder.highlight(code: code, language: language, theme: theme)
            },
        )
    }

    private func assertExactPlainSyntaxResult(
        _ result: AiChatSyntaxHighlightingClient.Result,
        source: String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(result.source, source, file: file, line: line)
        XCTAssertEqual(result.runs, [.plain(source)], file: file, line: line)
    }

    private func waitForSyntaxHighlightingCalls(
        _ count: Int,
        recorder: SyntaxHighlightingRecorder,
    ) async {
        while await recorder.invocationCount() < count {
            await Task.yield()
        }
    }

    private actor SuspendedSupportedLanguagesLoader {
        private var didStart = false
        private var startContinuation: CheckedContinuation<Void, Never>?
        private var operationContinuation: CheckedContinuation<Set<String>, any Error>?

        func load() async throws -> Set<String> {
            didStart = true
            startContinuation?.resume()
            startContinuation = nil
            return try await withCheckedThrowingContinuation { continuation in
                operationContinuation = continuation
            }
        }

        func waitUntilStarted() async {
            if didStart {
                return
            }
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }

        func fail(with failure: AiChatSyntaxHighlightingClient.EngineFailure) {
            operationContinuation?.resume(throwing: failure)
            operationContinuation = nil
        }
    }

    private actor SuspendedHighlightOperation {
        private var didStart = false
        private var startContinuation: CheckedContinuation<Void, Never>?
        private var operationContinuation: CheckedContinuation<[AiChatSyntaxHighlightingClient.Run], any Error>?

        func highlight() async throws -> [AiChatSyntaxHighlightingClient.Run] {
            didStart = true
            startContinuation?.resume()
            startContinuation = nil
            return try await withCheckedThrowingContinuation { continuation in
                operationContinuation = continuation
            }
        }

        func waitUntilStarted() async {
            if didStart {
                return
            }
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }

        func fail(with failure: AiChatSyntaxHighlightingClient.EngineFailure) {
            operationContinuation?.resume(throwing: failure)
            operationContinuation = nil
        }
    }

    private struct LifecycleAnnouncementCase {
        let phase: AiChatExecutionPhase
        let expectedPhase: AiChatLifecycleAnnouncementPhase
        let message: String
        let priority: AiChatLifecycleAnnouncementPriority
    }

    private actor SyntaxHighlightingRecorder {
        private let failure: AiChatSyntaxHighlightingClient.EngineFailure?
        private let suspends: Bool
        private var calls: [String] = []
        private var continuations: [String: CheckedContinuation<[AiChatSyntaxHighlightingClient.Run], any Error>] = [:]

        init(
            failure: AiChatSyntaxHighlightingClient.EngineFailure? = nil,
            suspends: Bool = false,
        ) {
            self.failure = failure
            self.suspends = suspends
        }

        func invocationCount() -> Int {
            calls.count
        }

        func highlight(
            code: String,
            language: String,
            theme: String,
        ) async throws -> [AiChatSyntaxHighlightingClient.Run] {
            calls.append("\(language):\(theme):\(code)")
            if let failure {
                throw failure
            }
            if suspends {
                return try await withCheckedThrowingContinuation { continuation in
                    continuations[code] = continuation
                }
            }
            return [
                .init(
                    sourceRange: .init(utf16Offsets: 0 ..< code.utf16.count),
                    attributes: .init(isBold: true),
                ),
            ]
        }

        func fail(code: String, with failure: AiChatSyntaxHighlightingClient.EngineFailure) {
            continuations.removeValue(forKey: code)?.resume(throwing: failure)
        }

        func resume(code: String) {
            continuations.removeValue(forKey: code)?.resume(returning: [
                .init(
                    sourceRange: .init(utf16Offsets: 0 ..< code.utf16.count),
                    attributes: .init(isBold: true),
                ),
            ])
        }
    }

    private actor IndexedSyntaxHighlightingRecorder {
        private var invocationTotal = 0
        private var continuations: [Int: IndexedSyntaxHighlightingContinuation] = [:]

        func invocationCount() -> Int {
            invocationTotal
        }

        func highlight(code _: String) async -> [AiChatSyntaxHighlightingClient.Run] {
            let invocation = invocationTotal
            invocationTotal += 1
            return await withCheckedContinuation { continuation in
                continuations[invocation] = continuation
            }
        }

        func resume(invocation: Int, source: String) {
            continuations.removeValue(forKey: invocation)?.resume(returning: [
                .init(
                    sourceRange: .init(utf16Offsets: 0 ..< source.utf16.count),
                    attributes: .init(isBold: true),
                ),
            ])
        }
    }

    private func waitForIndexedSyntaxHighlightingCalls(
        _ expectedCount: Int,
        recorder: IndexedSyntaxHighlightingRecorder,
    ) async {
        for _ in 0 ..< 1000 {
            if await recorder.invocationCount() >= expectedCount { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) indexed syntax highlighting calls")
    }

    private final class InputTextViewHarnessState {
        var text = ""
        var measuredHeight: CGFloat = 0
        var submitCount = 0
    }

    @MainActor
    private final class InputTextViewHarness {
        let state = InputTextViewHarnessState()
        let parent: AiChatInputTextView
        let coordinator: AiChatInputTextView.Coordinator
        let scrollView: NSScrollView
        let textView: AiChatInputTextView.AttachmentDroppingTextView

        init() {
            _ = NSApplication.shared
            let state = state
            let composerIdentity = AiChatViewScope().composerIdentity(displayedSessionID: nil)
            let focusOwner = AiChatInputFocusOwner()
            parent = AiChatInputTextView(
                text: Binding(
                    get: { state.text },
                    set: { state.text = $0 },
                ),
                measuredHeight: Binding(
                    get: { state.measuredHeight },
                    set: { state.measuredHeight = $0 },
                ),
                composerIdentity: composerIdentity,
                focusOwner: focusOwner,
                isDisabled: false,
                maxVisibleHeight: AiChatView.chatInputMaxTextHeight,
                onSubmit: { state.submitCount += 1 },
                onAttachmentsDropped: { _ in },
            )
            coordinator = parent.makeCoordinator()
            scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 180, height: 160))
            textView = AiChatInputTextView.AttachmentDroppingTextView()
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            coordinator.textView = textView
            coordinator.scrollView = scrollView
            textView.delegate = coordinator
            textView.frame.size.width = scrollView.contentSize.width
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.textContainerInset = NSSize(
                width: AiChatInputTextView.textHorizontalInset,
                height: AiChatInputTextView.textVerticalInset,
            )
            textView.font = NSFont.systemFont(ofSize: 13)
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = false
        }

        func pressEnterThroughAppKitFallback() -> Bool {
            let handled = coordinator.textView(
                textView,
                doCommandBy: #selector(NSResponder.insertNewline(_:)),
            )
            if !handled {
                textView.insertNewline(nil)
            }
            return handled
        }

        func measure(_ text: String) async -> CGFloat {
            textView.string = text
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
            return state.measuredHeight
        }

        func boundedHeight(for measuredHeight: CGFloat) -> CGFloat {
            min(
                max(measuredHeight, AiChatView.chatInputMinTextHeight),
                AiChatView.chatInputMaxTextHeight,
            )
        }
    }

    /// CBW-001-submit_chat_request: 선택한 provider executor로 요청을 위임하고 완료 응답을 transcript에 반영한다.
    /// submit 동작이 선택 모델, credential, session persistence까지 포함한 실제 실행 체인을 deterministic하게 통과하는지 검증합니다.
    /// - 검증 내용: request context model/credential, streaming delta, final assistant message, persistence snapshot을
    /// 확인합니다.
    /// - 사전 조건: OpenAI 모델과 API key credential이 연결되어 있고 draft에는 사용자 prompt가 있습니다.
    /// - 기대 결과: 사용자 메시지와 assistant 응답이 저장되며 실행 phase는 completed terminal lock으로 종료됩니다.
    func testSubmitChatRequestStreamsFinalAssistantMessageAndPersistsSession() async {
        let fixture = makeSubmitFixture()
        let store = makeSubmitStore(fixture: fixture)
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            self.applySubmitStartedState(
                &state,
                selectedHandle: fixture.selectedHandle,
                sessionID: fixture.sessionID,
                submittedAtMs: fixture.fixedMs,
            )
        }
        guard case let .processing(lock) = store.state.executionPhase else {
            XCTFail("Expected processing state after submit")
            return
        }

        let completedLock = await receiveSuccessfulSubmitEvents(on: store, lock: lock, fixture: fixture)
        await store.finish()
        await assertSuccessfulSubmitResult(store: store, lock: lock, completedLock: completedLock, fixture: fixture)
    }

    /// CBW-001-submit_chat_request: pending 해석 중에는 Stop을 유지하고 processing 경계의 늦은 다음 draft를 보존한다.
    /// submit 시점에 고정된 prompt와 resolver가 늦은 AppKit text callback 때문에 다음 메시지 draft를 잃지 않는지 검증합니다.
    /// - 검증 내용: pending Stop/Send projection, processing lock payload, live draft 보존을 확인합니다.
    /// - 사전 조건: 원 prompt가 pending request에 캡처된 뒤 live draft에는 다음 메시지 text가 도착했습니다.
    /// - 기대 결과: pending에는 Stop만 보이고 lock은 원 prompt를 유지하며 processing composer에는 다음 draft가 남습니다.
    func testSubmitChatRequestPreservesLateNextDraftAcrossPendingResolutionBoundary() {
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let sessionID = AiChatSessionID(rawValue: makeUUID("10101010-1010-1010-1010-101010101635"))
        let resolutionID = makeUUID("20202020-2020-2020-2020-202020202635")
        let originalPrompt = "Original prompt"
        let nextDraft = "Next turn draft"
        let pending = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: models[0],
            selectedRow: catalogRows[0],
            selectedThinking: .effort(.medium),
            preparedRequest: AiChatPreparedRequest(
                prompt: originalPrompt,
                messages: [AiChatMessage(role: .user, content: originalPrompt)],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: kAiChatHistoryCharacterBudget,
                    truncationReason: nil,
                ),
            ),
        )
        var state = AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Original context"),
            draftText: nextDraft,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
            pendingRequestStart: pending,
        )
        let feature = AiChatFeature()

        XCTAssertFalse(state.chatInputDisplayModel.isSubmitVisible)
        XCTAssertTrue(state.chatInputDisplayModel.isStopVisible)
        XCTAssertTrue(state.chatInputDisplayModel.canStop)
        XCTAssertTrue(state.chatInputDisplayModel.isComposerEditingDisabled)

        _ = withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_006_350))
        } operation: {
            feature.completeRequestContextResolution(
                resolutionID: resolutionID,
                resolvedContext: AiChatResolvedRequestContext(
                    currentContext: makeContextSnapshot(summary: "Original context"),
                    addedAttachments: [],
                    parts: [],
                ),
                state: &state,
            )
        }

        guard case let .processing(lock) = state.executionPhase else {
            return XCTFail("Expected processing lock after pending resolution")
        }
        XCTAssertEqual(lock.request.messages.last?.content, originalPrompt)
        XCTAssertEqual(lock.context.promptSummary, originalPrompt)
        XCTAssertEqual(lock.context.selectedThinking, .effort(.medium))
        XCTAssertEqual(state.draftText, nextDraft)
        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.chatInputDisplayModel.isSubmitVisible)
        XCTAssertTrue(state.chatInputDisplayModel.isStopVisible)
        XCTAssertFalse(state.chatInputDisplayModel.isComposerEditingDisabled)
    }

    /// CBW-001-submit_chat_request: 완료된 요청은 상태 문구를 제거하고 다음 submit을 허용한다.
    /// completed terminal state가 사용자에게 오류/진행 문구를 남기지 않고 다음 prompt 입력을 받을 수 있는지 검증합니다.
    /// - 검증 내용: requestStatusText와 canSubmit 계산 결과를 확인합니다.
    /// - 사전 조건: 이전 요청은 completed 상태이고 draft에는 후속 메시지가 있습니다.
    /// - 기대 결과: 상태 문구는 nil이고 composer는 submit 가능한 상태입니다.
    func testSubmitChatRequestClearsStatusTextAfterCompletion() {
        let state = makeCompletedStatusState()

        XCTAssertNil(state.requestStatusText)
        XCTAssertTrue(state.canSubmit)
    }

    // MARK: - CBW-001-show_request_processing_state

    /// CBW-001-show_request_processing_state: matching session lock은 session rows와 무관하게 현재 processing으로 노출한다.
    /// 정상 submit에서 만들어진 request owner가 목록 projection이 비어 있어도 composer disable과 stop affordance를 유지하는지 검증합니다.
    /// - 검증 내용: matching session lock에서 processing, canSubmit, submit/stop visibility, cancel affordance를 확인합니다.
    /// - 사전 조건: 현재 session과 lock session이 같고 session rows는 비어 있습니다.
    /// - 기대 결과: composer submit은 비활성화되고 stop 가능한 processing 상태가 표시됩니다.
    func testShowRequestProcessingStateKeepsMatchingSessionLockVisibleWhenRowsAreEmpty() {
        let rows = makeCatalogRows()
        let sessionID = AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555556001"))
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: makeRequestContext(
                    sessionID: sessionID,
                    requestID: AiChatRequestID(rawValue: makeUUID("66666666-6666-6666-6666-666666666001")),
                    runID: AiChatRunID(rawValue: makeUUID("77777777-7777-7777-7777-777777776001")),
                    model: rows[0].handle,
                    selectedRow: rows[0],
                ),
                messages: [],
            ),
            selectedHandle: rows[0].handle,
            selectedRow: rows[0],
            assistantReplacementIndex: nil,
        )
        let state = AiChatFeature.State(
            sessionList: .init(rows: []),
            sessionID: sessionID,
            sessionStatus: .active,
            draftText: "Queued follow-up",
            catalogRows: rows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: rows[0].handle,
            executionPhase: .processing(lock),
        )

        XCTAssertTrue(state.isProcessing)
        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.chatInputDisplayModel.isSubmitVisible)
        XCTAssertTrue(state.chatInputDisplayModel.isStopVisible)
        XCTAssertTrue(state.chatInputDisplayModel.canStop)
        XCTAssertNotNil(state.streamingAssistantDisplayModel)
    }

    /// CBW-001-show_request_processing_state: completion/failure/cancel은 편집 중인 next-turn composer를 보존한다.
    /// processing 중 준비한 다음 메시지가 현재 response의 terminal 결과에 의해 지워지거나 locked request에 섞이지 않는지 검증합니다.
    /// - 검증 내용: 세 terminal 경로의 draft/context/attachment/model/thinking과 request lock payload를 확인합니다.
    /// - 사전 조건: 첫 요청은 model 0으로 processing이고 live composer는 model 1과 next-turn 값을 담고 있습니다.
    /// - 기대 결과: terminal phase만 전환되고 next-turn state와 첫 request context/request는 그대로 유지됩니다.
    func testShowRequestProcessingStatePreservesNextTurnComposerAcrossTerminalEvents() {
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let sessionID = AiChatSessionID(rawValue: makeUUID("90909090-9090-9090-9090-909090909635"))
        let requestContext = makeRequestContext(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("91919191-9191-9191-9191-919191919635")),
            runID: AiChatRunID(rawValue: makeUUID("92929292-9292-9292-9292-929292929635")),
            model: catalogRows[0].handle,
            selectedRow: catalogRows[0],
        )
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "First prompt")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: catalogRows[0].handle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let nextContext = makeContextSnapshot(summary: "Next context")
        let nextAttachment = AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: "next-attachment"),
            source: .file,
            displayTitle: "Next.txt",
        )
        let processingState = AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: nextContext,
            addedAttachments: [nextAttachment],
            transcriptHistory: [AiChatMessage(role: .user, content: "First prompt")],
            draftText: "Next prompt",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[1].handle,
            selectedThinking: .effort(.minimal),
            lockedModelHandle: catalogRows[0].handle,
            executionPhase: .processing(lock),
        )
        let feature = AiChatFeature()

        var completedState = processingState
        feature.applyFinal(
            response: AiChatResponse(
                context: requestContext,
                assistantMessage: AiChatMessage(role: .assistant, content: "Done"),
                completedAtMs: 1_700_000_006_353,
            ),
            lock: lock,
            state: &completedState,
        )

        var failedState = processingState
        _ = withDependencies {
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_006_353))
        } operation: {
            feature.handleExecutionEvent(
                .failed(context: requestContext, reason: .network),
                state: &failedState,
            )
        }

        var cancelledState = processingState
        _ = withDependencies {
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_006_353))
        } operation: {
            feature.handleCancelTapped(state: &cancelledState)
        }

        for terminalState in [completedState, failedState, cancelledState] {
            XCTAssertEqual(terminalState.currentContext, nextContext)
            XCTAssertEqual(terminalState.addedAttachments, [nextAttachment])
            XCTAssertEqual(terminalState.draftText, "Next prompt")
            XCTAssertEqual(terminalState.selectedModelHandle, catalogRows[1].handle)
            XCTAssertEqual(terminalState.selectedThinking, .effort(.minimal))
            XCTAssertEqual(terminalState.executionPhase.lock?.context, lock.context)
            XCTAssertEqual(terminalState.executionPhase.lock?.request, lock.request)
        }
    }

    /// CBW-001-show_request_processing_state: session 없는 새 chat은 비소유 lock을 processing으로 채택하지 않는다.
    /// current session identity가 아직 없는 lifecycle에서 남은 foreground phase가 composer를 잘못 잠그지 않는지 검증합니다.
    /// - 검증 내용: nil current session과 non-nil lock session 조합의 processing projection을 확인합니다.
    /// - 사전 조건: session rows와 current session은 비어 있고 execution phase에 이전 session lock만 남아 있습니다.
    /// - 기대 결과: processing, stop affordance, streaming assistant projection이 모두 숨겨집니다.
    func testShowRequestProcessingStateDoesNotAdoptLockWithoutCurrentSessionIdentity() {
        let rows = makeCatalogRows()
        let lockSessionID = AiChatSessionID(rawValue: makeUUID("88888888-8888-8888-8888-888888886001"))
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: makeRequestContext(
                    sessionID: lockSessionID,
                    requestID: AiChatRequestID(rawValue: makeUUID("99999999-9999-9999-9999-999999996001")),
                    runID: AiChatRunID(rawValue: makeUUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6001")),
                    model: rows[0].handle,
                    selectedRow: rows[0],
                ),
                messages: [],
            ),
            selectedHandle: rows[0].handle,
            selectedRow: rows[0],
            assistantReplacementIndex: nil,
        )
        let state = AiChatFeature.State(
            sessionList: .init(rows: []),
            sessionID: nil,
            executionPhase: .processing(lock),
        )

        XCTAssertFalse(state.isProcessing)
        XCTAssertFalse(state.chatInputDisplayModel.isStopVisible)
        XCTAssertNil(state.streamingAssistantDisplayModel)
    }

    /// CBW-001-show_request_processing_state: stream 실패 시 부분 assistant draft와 실패 상태를 함께 보여준다.
    /// processing 중 수신한 delta가 실패 terminal event 이후에도 사용자에게 partial response로 보존되는지 검증합니다.
    /// - 검증 내용: streamingAssistantDraft, failed executionPhase, requestStatusText, display model failure를 확인합니다.
    /// - 사전 조건: submit 이후 provider stream이 partial delta를 보낸 뒤 transportError로 실패합니다.
    /// - 기대 결과: partial draft는 보존되고 transcript에는 사용자 메시지만 남으며 실패 배너가 표시됩니다.
    func testShowRequestProcessingStatePreservesPartialDraftWhenStreamFails() async {
        let fixture = makeStreamFixture(draftText: "Partial failure", fixedMs: 1_700_000_000_250)
        applyObservationFocusedExhaustivity(to: fixture.store)

        await fixture.store.send(.submitTapped)
        await resolvePendingRequestContext(fixture.store) { state in
            self.applyProcessingFailureStartedState(
                &state,
                selectedHandle: fixture.selectedHandle,
                submittedAtMs: fixture.fixedMs,
            )
        }
        guard let request = fixture.stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }

        let lock = makeSubmitLock(
            request: request,
            catalogRows: fixture.catalogRows,
            selectedHandle: fixture.selectedHandle,
        )
        await receiveProcessingFailureEvents(
            on: fixture.store,
            stream: fixture.stream,
            request: request,
            lock: lock,
            fixedMs: fixture.fixedMs,
        )
        assertProcessingFailureResult(fixture.store.state, submittedAtMs: fixture.fixedMs)
        await fixture.store.finish()
    }

    /// CBW-001-show_request_processing_state: waiting projection과 accepted chunk revision 경계를 유지한다.
    /// 응답 시작 전과 연속 delta 수신 중 empty/stale event가 시각 revision을 잘못 진행시키지 않는지 검증합니다.
    /// - 검증 내용: initial waiting projection, matched non-empty delta, empty/stale/unmatched delta, content 보존을 확인합니다.
    /// - 사전 조건: visible request lock이 processing 중이고 streaming draft와 chunk count는 비어 있습니다.
    /// - 기대 결과: non-empty matched delta만 content와 revision을 진행시키고 나머지 event는 projection을 변경하지 않습니다.
    func testShowRequestProcessingStateProjectsWaitingAndCountsOnlyAcceptedChunks() async throws {
        let rows = makeCatalogRows()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114001"))
        let requestID = AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222224001"))
        let runID = AiChatRunID(rawValue: makeUUID("33333333-3333-3333-3333-333333334001"))
        let context = makeRequestContext(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            model: rows[0].handle,
            selectedRow: rows[0],
            selectedThinking: .effort(.high),
        )
        let request = AiChatRequest(context: context, messages: [])
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: rows[0].handle,
            selectedRow: rows[0],
            assistantReplacementIndex: nil,
        )
        let fixedMs: Int64 = 1_700_000_004_001
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            transcriptHistory: [AiChatMessage(role: .user, content: "Question")],
            catalogRows: rows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: rows[0].handle,
            executionPhase: .processing(lock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
        }

        let waiting = try XCTUnwrap(store.state.streamingAssistantDisplayModel)
        XCTAssertEqual(waiting.requestID, requestID)
        XCTAssertNil(waiting.content)
        XCTAssertEqual(waiting.acceptedChunkRevision, 0)

        await store.send(.executionEvent(.delta(context: context, text: "")))
        await store.send(.executionEvent(.delta(context: context, text: "  \n")))

        let staleContext = makeRequestContext(
            sessionID: sessionID,
            requestID: requestID,
            runID: AiChatRunID(rawValue: makeUUID("44444444-4444-4444-4444-444444444001")),
            model: rows[0].handle,
            selectedRow: rows[0],
        )
        let unmatchedContext = makeRequestContext(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("55555555-5555-5555-5555-555555554001")),
            runID: runID,
            model: rows[0].handle,
            selectedRow: rows[0],
        )
        await store.send(.executionEvent(.delta(context: staleContext, text: "stale")))
        await store.send(.executionEvent(.delta(context: unmatchedContext, text: "unmatched")))

        let firstAcceptedLock = lock.recordingDelta(at: fixedMs)
        await store.send(.executionEvent(.delta(context: context, text: " Hel "))) { state in
            state.streamingAssistantDraft = " Hel "
            state.executionPhase = .processing(firstAcceptedLock)
            state.transcriptAutoScrollVersion = 1
        }
        let secondAcceptedLock = firstAcceptedLock.recordingDelta(at: fixedMs)
        await store.send(.executionEvent(.delta(context: context, text: "lo"))) { state in
            state.streamingAssistantDraft = " Hel lo"
            state.executionPhase = .processing(secondAcceptedLock)
            state.transcriptAutoScrollVersion = 2
        }

        let streaming = try XCTUnwrap(store.state.streamingAssistantDisplayModel)
        XCTAssertEqual(streaming.requestID, requestID)
        XCTAssertEqual(streaming.content, " Hel lo")
        XCTAssertEqual(streaming.acceptedChunkRevision, 2)
        XCTAssertEqual(store.state.executionPhase.lock?.observabilitySummary.chunkCount, 2)
    }

    /// CBW-001-show_request_processing_state: accepted chunk는 assistant 본문만 짧게 fade-in한다.
    /// Header와 card layout을 고정한 채 Markdown content transition만 revision에 반응하고 Reduce Motion을 우회하는지 검증합니다.
    /// - 검증 내용: opacity content transition, 0.15초 ease-in, revision key, Reduce Motion nil animation을 확인합니다.
    /// - 사전 조건: streaming display model은 acceptedChunkRevision을 제공하고 conversation surface가 이를 렌더링합니다.
    /// - 기대 결과: 본문만 cross-fade하며 whole-card opacity state나 비동기 fade task는 생성되지 않습니다.
    func testShowRequestProcessingStateFadesAcceptedChunkBodyAndRespectsReduceMotion() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerFeaturesAiChat/Ui/AiChatConversationSurface.swift",
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let cardStart = try XCTUnwrap(source.range(of: "private struct AiChatAssistantCard: View"))
        let waitingStart = try XCTUnwrap(source.range(of: "private struct AiChatWaitingIndicator: View"))
        let cardSource = String(source[cardStart.lowerBound ..< waitingStart.lowerBound])
        let bodyStart = try XCTUnwrap(cardSource.range(of: "    @ViewBuilder private var bodyContentView"))
        let failureStart = try XCTUnwrap(cardSource.range(of: "    private func failureView"))
        let bodySource = String(cardSource[bodyStart.lowerBound ..< failureStart.lowerBound])
        let cardRootAndHeader = String(cardSource[..<bodyStart.lowerBound])
        let fadeContracts = [
            ".contentTransition(.opacity)",
            "reduceMotion ? nil : .easeIn(duration: AiChatAssistantBodyPresentation.chunkFadeDuration)",
            "value: acceptedChunkRevision",
        ]
        for contract in fadeContracts {
            XCTAssertTrue(bodySource.contains(contract), "Missing body chunk fade contract: \(contract)")
            XCTAssertFalse(cardRootAndHeader.contains(contract), "Unexpected card/header fade contract: \(contract)")
        }
        XCTAssertEqual(AiChatAssistantBodyPresentation.chunkFadeDuration, 0.15)
        let forbiddenWholeCardContracts = [
            "@State private var responseOpacity",
            "@State private var fadeTask",
            ".opacity(responseOpacity)",
            "applyChunkFade()",
        ]
        for contract in forbiddenWholeCardContracts {
            XCTAssertFalse(cardSource.contains(contract), "Unexpected whole-card fade contract: \(contract)")
        }
        XCTAssertTrue(source.contains("acceptedChunkRevision: streamingAssistant.acceptedChunkRevision"))
    }

    /// CBW-001-show_request_processing_state: timestamp는 calendar day와 시간 경계 우선순위로 표시한다.
    /// 사용자가 메시지 metadata를 확인할 때 locale과 time zone이 고정된 입력에서 날짜·상대 시간 정책이 유지되는지 검증합니다.
    /// - 검증 내용: exact/future/59초, 60초, 정확히 1시간, 자정 교차의 nonempty localized time을 확인합니다.
    ///   같은 해, 다른 해, nil 경계도 함께 확인합니다.
    /// - 사전 조건: en_US_POSIX locale과 GMT에서 2026-07-24의 고정 현재 시각을 사용합니다.
    /// - 기대 결과: 같은 날만 minute-relative 표현을 사용합니다.
    ///   다른 calendar day는 플랫폼별 날짜 단어와 무관하게 dateTime과 localized time을 표시합니다.
    func testShowRequestProcessingStateFormatsTranscriptTimestampsByCalendarDay() throws {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 24,
            hour: 12,
        )))
        let sameYear = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 20,
            hour: 15,
            minute: 4,
        )))
        let differentYear = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2025,
            month: 12,
            day: 31,
            hour: 8,
            minute: 30,
        )))
        let milliseconds: (Date) -> Int64 = { Int64($0.timeIntervalSince1970 * 1000) }
        let presentation = AiChatTranscriptPresentation(
            messages: [
                AiChatMessage(role: .user, content: "Exact", createdAtMs: milliseconds(now)),
                AiChatMessage(
                    role: .assistant,
                    content: "Future",
                    createdAtMs: milliseconds(now.addingTimeInterval(1)),
                ),
                AiChatMessage(
                    role: .user,
                    content: "59 seconds",
                    createdAtMs: milliseconds(now.addingTimeInterval(-59)),
                ),
                AiChatMessage(
                    role: .assistant,
                    content: "60 seconds",
                    createdAtMs: milliseconds(now.addingTimeInterval(-60)),
                ),
                AiChatMessage(
                    role: .user,
                    content: "Exact hour",
                    createdAtMs: milliseconds(now.addingTimeInterval(-3600)),
                ),
                AiChatMessage(role: .assistant, content: "Same year", createdAtMs: milliseconds(sameYear)),
                AiChatMessage(role: .user, content: "Different year", createdAtMs: milliseconds(differentYear)),
                AiChatMessage(role: .assistant, content: "Legacy"),
            ],
            now: now,
            locale: locale,
            timeZone: timeZone,
        )

        XCTAssertEqual(
            presentation.rows.map(\.timestampLabel),
            [
                "Just now",
                "Just now",
                "Just now",
                "1 minute ago",
                "11:00 AM",
                "Jul 20 at 3:04 PM",
                "Dec 31, 2025 at 8:30 AM",
                nil,
            ],
        )
        XCTAssertEqual(
            presentation.rows.map(\.timestampStyle),
            [.relative, .relative, .relative, .relative, .shortTime, .dateTime, .dateTime, nil],
        )
        XCTAssertEqual(presentation.rows.map(\.accessibilityTimestampLabel), presentation.rows.map(\.timestampLabel))

        let crossMidnightNow = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 24,
            minute: 0,
            second: 30,
        )))
        let crossMidnight = AiChatTranscriptPresentation(
            messages: [AiChatMessage(
                role: .user,
                content: "Recent yesterday",
                createdAtMs: milliseconds(crossMidnightNow.addingTimeInterval(-45)),
            )],
            now: crossMidnightNow,
            locale: locale,
            timeZone: timeZone,
        )
        let crossMidnightLabel = try XCTUnwrap(crossMidnight.rows[0].timestampLabel)
        XCTAssertEqual(crossMidnight.rows[0].timestampStyle, .dateTime)
        XCTAssertFalse(crossMidnightLabel.isEmpty)
        XCTAssertTrue(crossMidnightLabel.contains("11:59"))
        XCTAssertFalse(crossMidnightLabel.contains("minute ago"))
        XCTAssertFalse(crossMidnightLabel.contains("minutes ago"))
        XCTAssertNotEqual(crossMidnightLabel, presentation.rows[3].timestampLabel)
    }

    /// CBW-001-show_request_processing_state: 공개된 timestamp는 흐르는 현재 시각으로 다시 계산한다.
    /// hover 또는 focus가 유지되는 동안 초기 Just now 표현이 stale 상태로 남지 않는 갱신 경계를 검증합니다.
    /// - 검증 내용: 동일 row의 timestamp label을 초기 시각과 60초 뒤 시각으로 각각 계산합니다.
    /// - 사전 조건: en_US_POSIX locale과 GMT에서 현재 시각에 생성된 user message를 사용합니다.
    /// - 기대 결과: 초기 label은 Just now이고 60초 뒤 refresh label은 1 minute ago입니다.
    func testShowRequestProcessingStateRefreshesDisclosedTranscriptTimestamp() throws {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let row = try XCTUnwrap(AiChatTranscriptPresentation(
            messages: [AiChatMessage(role: .user, content: "Current", createdAtMs: 1_800_000_000_000)],
            now: now,
            locale: locale,
            timeZone: timeZone,
        ).rows.first)

        XCTAssertEqual(row.timestampLabel, "Just now")
        XCTAssertEqual(
            AiChatTranscriptPresentation.timestampPresentation(
                createdAtMs: row.message.createdAtMs,
                now: now.addingTimeInterval(60),
                locale: locale,
                timeZone: timeZone,
            )?.label,
            "1 minute ago",
        )
    }

    /// CBW-001-show_request_processing_state: message hover와 Clock 상호작용은 timestamp 노출 책임을 분리한다.
    /// message hover는 Clock만 드러내고 Clock hover/focus만 즉시 custom tooltip을 여는 상태 행렬을 검증합니다.
    /// - 검증 내용: rest, Clock hover, Clock focus, metadata 부재의 tooltip 결과를 확인합니다.
    /// - 사전 조건: message hover는 tooltip 입력에서 제외하고 timestamp metadata 유무를 구분합니다.
    /// - 기대 결과: rest와 metadata 부재는 닫히고 Clock hover/focus 중 하나가 있으면 tooltip이 열립니다.
    func testShowRequestProcessingStateSeparatesMessageAndClockTimestampInteractions() {
        XCTAssertFalse(AiChatTimestampAffordancePresentation.presentsTooltip(
            hasTimestampMetadata: true, isClockHovered: false, isClockFocused: false,
        ))
        let clockInteractions = [
            AiChatTimestampAffordancePresentation.presentsTooltip(
                hasTimestampMetadata: true, isClockHovered: true, isClockFocused: false,
            ),
            AiChatTimestampAffordancePresentation.presentsTooltip(
                hasTimestampMetadata: true, isClockHovered: false, isClockFocused: true,
            ),
        ]
        XCTAssertEqual(clockInteractions, [true, true])
        XCTAssertFalse(AiChatTimestampAffordancePresentation.presentsTooltip(
            hasTimestampMetadata: false, isClockHovered: true, isClockFocused: true,
        ))
    }

    /// CBW-001-show_request_processing_state: hover timestamp는 다른 행의 focus timestamp보다 우선한다.
    /// transcript 순서와 관계없이 포인터 아래 Clock의 tooltip이 선택되는 우선순위를 검증합니다.
    /// - 검증 내용: focus 다음 hover와 hover 다음 focus의 양방향 경쟁 상태를 확인합니다.
    /// - 사전 조건: 서로 다른 행에서 focus와 hover anchor가 동시에 발행됩니다.
    /// - 기대 결과: hover는 focus를 대체하고 focus는 hover를 대체하지 않습니다.
    func testShowRequestProcessingStatePrefersHoveredTimestampAcrossTranscriptOrder() {
        XCTAssertTrue(AiChatTimestampTooltipTrigger.hover.outranks(.focus))
        XCTAssertFalse(AiChatTimestampTooltipTrigger.focus.outranks(.hover))
    }

    /// CBW-001-show_request_processing_state: timestamp는 message-owned Clock과 in-surface tooltip으로 투영한다.
    /// role별 안전 영역의 stable overlay가 기존 localized timestamp를 custom tooltip에 그대로 제공하는지 검증합니다.
    /// - 검증 내용: user/assistant placement, control 크기, persistent gutter와 tooltip 최대 안전 폭을 확인합니다.
    /// - 사전 조건: en_US_POSIX locale과 GMT에서 localized timestamp label을 생성한 user/assistant row를 사용합니다.
    /// - 기대 결과: user는 leading gutter, assistant는 top-trailing corner를 사용하고 tooltip은 기존 label과 같습니다.
    func testShowRequestProcessingStateUsesMessageOwnedTimestampClockAffordance() throws {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let localizedLabel = try XCTUnwrap(AiChatTranscriptPresentation.timestampPresentation(
            createdAtMs: 1_799_913_600_000,
            now: now,
            locale: locale,
            timeZone: timeZone,
        )?.label)

        let user = AiChatTimestampAffordancePresentation(placement: .userLeadingGutter)
        let assistant = AiChatTimestampAffordancePresentation(placement: .assistantTopTrailing)

        XCTAssertEqual(user.placement, .userLeadingGutter)
        XCTAssertEqual(assistant.placement, .assistantTopTrailing)
        XCTAssertFalse(localizedLabel.isEmpty)
        XCTAssertEqual(AiChatTimestampAffordancePresentation.controlSize, 24)
        XCTAssertGreaterThan(AiChatTimestampAffordancePresentation.tooltipMaximumWidth, 180)
        XCTAssertGreaterThan(AiChatTimestampAffordancePresentation.tooltipHorizontalPadding, 0)
        XCTAssertGreaterThan(AiChatTimestampAffordancePresentation.tooltipVerticalPadding, 0)
        XCTAssertLessThanOrEqual(
            user.placement.horizontalOffset,
            -AiChatTimestampAffordancePresentation.controlSize,
        )
        XCTAssertGreaterThanOrEqual(
            assistant.placement.horizontalOffset,
            AiChatTimestampAffordancePresentation.controlSize,
        )
        XCTAssertEqual(
            AiChatTimestampAffordancePresentation.assistantTrailingGutter,
            AiChatTimestampAffordancePresentation.controlSize + 4,
        )
        XCTAssertGreaterThanOrEqual(
            AiChatTimestampAffordancePresentation.assistantTrailingGutter,
            assistant.placement.horizontalOffset,
        )
    }

    /// CBW-001-show_request_processing_state: timestamp hover panel은 label을 자르지 않고 내용에 맞춰 확장한다.
    /// 짧은 label은 intrinsic width를 사용하고 긴 label은 viewport 안에서 여러 줄로 확장하는 sizing을 검증합니다.
    /// - 검증 내용: roomy viewport의 compact size와 constrained viewport의 wrapped height를 비교합니다.
    /// - 사전 조건: 짧은 localized timestamp와 의도적으로 긴 timestamp label을 사용합니다.
    /// - 기대 결과: 긴 label은 viewport inset 폭을 사용하고 짧은 label보다 높은 panel을 생성합니다.
    func testShowRequestProcessingStateSizesTimestampHoverPanelWithoutTruncation() {
        let compact = AiChatTimestampTooltipSizing.resolve(
            label: "Aug 1 at 5:28 PM",
            availableWidth: 500,
        )
        let wrapped = AiChatTimestampTooltipSizing.resolve(
            label: String(repeating: "Long localized timestamp ", count: 4),
            availableWidth: 180,
        )

        XCTAssertLessThan(compact.width, AiChatTimestampAffordancePresentation.tooltipMaximumWidth)
        XCTAssertEqual(wrapped.width, 172)
        XCTAssertGreaterThan(wrapped.height, compact.height)
    }

    /// CBW-001-show_request_processing_state: timestamp renderer는 tail truncation 대신 multiline menu panel을 사용한다.
    /// production source가 고정 한 줄 capsule로 회귀하지 않는지 검증합니다.
    /// - 검증 내용: renderer 범위의 multiline, rounded panel과 truncation 부재를 확인합니다.
    /// - 사전 조건: AiChatView가 timestamp hover panel renderer를 소유합니다.
    /// - 기대 결과: lineLimit은 nil이고 tail truncation과 Capsule renderer는 없습니다.
    func testShowRequestProcessingStateRendersTimestampHoverPanelWithoutTailTruncation() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerFeaturesAiChat/Ui/AiChatViewOverlaySupport.swift",
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let rendererStart = try XCTUnwrap(source.range(of: "struct AiChatTimestampTooltip: View"))
        let panelStart = try XCTUnwrap(source.range(of: "struct AiChatAssistantMetadataPanel: View"))
        let renderer = String(source[rendererStart.lowerBound ..< panelStart.lowerBound])

        XCTAssertTrue(renderer.contains(".lineLimit(nil)"))
        XCTAssertTrue(renderer.contains("RoundedRectangle(cornerRadius: VoyagerDS.Radius.control"))
        XCTAssertFalse(renderer.contains(".truncationMode("))
        XCTAssertFalse(renderer.contains("Capsule("))
    }

    /// CBW-001-show_request_processing_state: timestamp tooltip은 visible ScrollView viewport 안에서 flip한다.
    /// scroll-converted negative/overflow 좌표에서도 위·아래 fit을 비교하는지 검증합니다.
    /// - 검증 내용: partially visible top/bottom row와 both-fit above 우선을 확인합니다.
    /// - 사전 조건: 실제 viewport 좌표계의 message/Clock rect와 24pt high, 180pt wide tooltip을 사용합니다.
    /// - 기대 결과: fit 가능한 쪽은 message와 교차하지 않고 fallback을 포함한 모든 frame은 viewport 내부에 있습니다.
    func testShowRequestProcessingStateClampsAndFlipsTimestampTooltipGeometry() {
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 240)
        let tooltipSize = CGSize(width: 180, height: 24)

        let bothFitMessage = CGRect(x: 96, y: 100, width: 220, height: 40)
        let bothFit = AiChatTimestampTooltipGeometry.resolve(
            viewportBounds: viewport,
            messageBounds: bothFitMessage,
            clockBounds: CGRect(x: 68, y: 104, width: 24, height: 24),
            preferredSize: tooltipSize,
        )
        XCTAssertEqual(bothFit.verticalPlacement, .above)
        XCTAssertEqual(bothFit.frame.minX, 4)
        XCTAssertEqual(bothFit.frame.maxY, bothFitMessage.minY - 4)
        XCTAssertFalse(bothFit.frame.intersects(bothFitMessage))

        let partiallyVisibleTopMessage = CGRect(x: 0, y: -20, width: 288, height: 60)
        let partiallyVisibleTop = AiChatTimestampTooltipGeometry.resolve(
            viewportBounds: viewport,
            messageBounds: partiallyVisibleTopMessage,
            clockBounds: CGRect(x: 292, y: -16, width: 24, height: 24),
            preferredSize: tooltipSize,
        )
        XCTAssertEqual(partiallyVisibleTop.verticalPlacement, .below)
        XCTAssertEqual(partiallyVisibleTop.frame.maxX, viewport.maxX - 4)
        XCTAssertEqual(partiallyVisibleTop.frame.minY, partiallyVisibleTopMessage.maxY + 4)
        XCTAssertFalse(partiallyVisibleTop.frame.intersects(partiallyVisibleTopMessage))

        let partiallyVisibleBottomMessage = CGRect(x: 96, y: 200, width: 220, height: 70)
        let partiallyVisibleBottom = AiChatTimestampTooltipGeometry.resolve(
            viewportBounds: viewport,
            messageBounds: partiallyVisibleBottomMessage,
            clockBounds: CGRect(x: 68, y: 204, width: 24, height: 24),
            preferredSize: tooltipSize,
        )
        XCTAssertEqual(partiallyVisibleBottom.verticalPlacement, .above)
        XCTAssertEqual(partiallyVisibleBottom.frame.maxY, partiallyVisibleBottomMessage.minY - 4)
        XCTAssertFalse(partiallyVisibleBottom.frame.intersects(partiallyVisibleBottomMessage))
    }

    /// CBW-001-show_request_processing_state: timestamp tooltip은 좁거나 제한된 viewport 안에서 clamp한다.
    /// - 검증 내용: narrow width와 neither-fit fallback이 full frame을 viewport에 유지하는지 확인합니다.
    /// - 사전 조건: tooltip보다 좁거나 tooltip의 위·아래 공간이 모두 부족한 viewport를 사용합니다.
    /// - 기대 결과: tooltip frame은 viewport의 4pt inset 안에 유지됩니다.
    func testShowRequestProcessingStateClampsTimestampTooltipInConstrainedViewport() {
        let tooltipSize = CGSize(width: 180, height: 24)
        let narrowViewport = CGRect(x: 0, y: 0, width: 96, height: 240)
        let narrow = AiChatTimestampTooltipGeometry.resolve(
            viewportBounds: narrowViewport,
            messageBounds: CGRect(x: 20, y: 80, width: 72, height: 40),
            clockBounds: CGRect(x: -8, y: 84, width: 24, height: 24),
            preferredSize: tooltipSize,
        )
        XCTAssertEqual(narrow.frame, CGRect(x: 4, y: 52, width: 88, height: 24))

        let constrainedViewport = CGRect(x: 0, y: 0, width: 120, height: 60)
        let neitherFits = AiChatTimestampTooltipGeometry.resolve(
            viewportBounds: constrainedViewport,
            messageBounds: CGRect(x: 20, y: 10, width: 96, height: 25),
            clockBounds: CGRect(x: 0, y: 12, width: 24, height: 24),
            preferredSize: tooltipSize,
        )
        XCTAssertEqual(neitherFits.verticalPlacement, .below)
        XCTAssertEqual(neitherFits.frame, CGRect(x: 4, y: 32, width: 112, height: 24))
        XCTAssertTrue(constrainedViewport.insetBy(dx: 4, dy: 4).contains(neitherFits.frame))
    }

    /// CBW-001-show_request_processing_state: legacy timestamp popover와 transcript-owned overlay를 제거한다.
    /// message row 전체 focus/pin 상태가 돌아오지 않고 transcript content가 viewport renderer를 소유하지 않는지 검증합니다.
    /// - 검증 내용: legacy popover 계약과 transcript 내부 overlay/GeometryReader 부재를 확인합니다.
    /// - 사전 조건: conversation surface가 message row와 transcript section을 함께 구성합니다.
    /// - 기대 결과: legacy 계약은 없고 renderer symbol은 AiChatView에만 있습니다.
    func testShowRequestProcessingStateRemovesLegacyTimestampPopoverAndTranscriptOverlay() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerFeaturesAiChat/Ui/AiChatConversationSurface.swift",
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let transcriptStart = try XCTUnwrap(source.range(of: "private struct AiChatTranscriptSection: View"))
        let rowStart = try XCTUnwrap(source.range(of: "private struct AiChatMessageRow: View"))
        let assistantCardStart = try XCTUnwrap(source.range(of: "private struct AiChatAssistantCard: View"))
        let rowSource = String(source[rowStart.lowerBound ..< assistantCardStart.lowerBound])
        let removedContracts = [
            ".focusable(row.hasTimestampMetadata)",
            ".focused($isMetadataFocused)",
            "@FocusState private var isMetadataFocused: Bool",
            ".accessibilityHidden(!shouldRevealTimestampControl)",
            ".popover(",
            "@State private var isTimestampPopoverPinned",
            "isTimestampPopoverPinned.toggle()",
            "timestampPopoverBinding",
            "Binding<Bool>",
            "shouldPresentTimestampPopover",
            "isPinned:",
            ".overlay(alignment: .trailing)",
            ".offset(x: -(AiChatTimestampAffordancePresentation.controlSize + 4))",
        ]
        for removedContract in removedContracts {
            XCTAssertFalse(rowSource.contains(removedContract), "Unexpected timestamp contract: \(removedContract)")
        }

        let transcriptSource = String(source[transcriptStart.lowerBound ..< rowStart.lowerBound])
        XCTAssertFalse(transcriptSource.contains(".overlayPreferenceValue("))
        XCTAssertFalse(transcriptSource.contains("GeometryReader"))
        XCTAssertFalse(source.contains("struct AiChatTimestampTooltipGeometry"))
        XCTAssertFalse(source.contains("private struct AiChatTimestampTooltip: View"))
    }

    /// CBW-001-show_request_processing_state: Clock interaction은 message flow 밖에서 anchor와 접근성을 제공한다.
    /// hover/focus disclosure가 row layout을 바꾸지 않고 single VoiceOver timestamp source를 유지하는지 검증합니다.
    /// - 검증 내용: Clock state, anchor 발행, timeline 갱신과 accessibility 계약을 확인합니다.
    /// - 사전 조건: message row가 timestamp metadata와 role별 placement를 가집니다.
    /// - 기대 결과: Clock만 focus/hover를 소유하고 row accessibilityValue는 한 번만 존재합니다.
    func testShowRequestProcessingStateKeepsTimestampClockInteractionOutOfMessageFlow() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerFeaturesAiChat/Ui/AiChatConversationSurface.swift",
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let presentationURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerFeaturesAiChat/Ui/AiChatTranscriptPresentation.swift",
        )
        let contractSource = try source + "\n" + String(contentsOf: presentationURL, encoding: .utf8)
        let contracts = [
            "Spacer(minLength: 16)",
            "timestampControlOverlay(",
            "@State private var isMessageHovered = false",
            "@State private var isTimestampControlHovered = false",
            "@FocusState private var isTimestampControlFocused: Bool",
            "Image(systemName: \"clock\")",
            ".focusable()",
            ".focused($isTimestampControlFocused)",
            ".onHover { isTimestampControlHovered = $0 }",
            ".opacity(shouldRevealTimestampControl ? 1 : 0)",
            ".allowsHitTesting(shouldRevealTimestampControl)",
            ".anchorPreference(",
            ".transformAnchorPreference(",
            "trigger: isTimestampControlHovered ? .hover : .focus,",
            "row.showsTimestampAffordance && (isMessageHovered || shouldPresentTimestampTooltip)",
            "hasTimestampMetadata && (isClockHovered || isClockFocused)",
            "TimelineView(.animation(minimumInterval: 1, paused: !shouldPresentTimestampTooltip))",
            ".modifier(AiChatTimestampAccessibilityValue(label: timestampLabel))",
            "content.accessibilityValue(\"Sent \\(label)\")",
            ".offset(x: placement.horizontalOffset, y: 4)",
            ".padding(.trailing, AiChatTimestampAffordancePresentation.assistantTrailingGutter)",
        ]
        for contract in contracts {
            XCTAssertTrue(contractSource.contains(contract), "Missing conversation contract: \(contract)")
        }

        let controlStart = try XCTUnwrap(source.range(of: "    private func timestampControlOverlay("))
        let stateStart = try XCTUnwrap(source.range(of: "    private var shouldRevealTimestampControl"))
        let controlSource = String(source[controlStart.lowerBound ..< stateStart.lowerBound])
        XCTAssertFalse(controlSource.contains("Button"))
        XCTAssertFalse(controlSource.contains("action:"))
        XCTAssertTrue(controlSource.contains("if let timestampLabel, row.showsTimestampAffordance"))
        XCTAssertTrue(controlSource.contains(".anchorPreference("))
        XCTAssertTrue(controlSource.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(controlSource.contains(".accessibilityLabel("))
        XCTAssertFalse(controlSource.contains(".accessibilityHint("))
        let accessibilityContract = "content.accessibilityValue(\"Sent \\(label)\")"
        XCTAssertEqual(source.components(separatedBy: accessibilityContract).count - 1, 1)
    }

    /// CBW-001-show_request_processing_state: timestamp hover panel viewport는 visible ScrollView가 소유한다.
    /// geometry와 sizing이 transcript content가 아닌 ScrollView modifier에서 적용되는지 검증합니다.
    /// - 검증 내용: renderer contracts와 ScrollView modifier ordering을 확인합니다.
    /// - 사전 조건: AiChatView가 transcript ScrollView와 hover panel renderer를 구성합니다.
    /// - 기대 결과: viewport overlay는 ScrollView 직후, lifecycle modifier 이전에 있습니다.
    func testShowRequestProcessingStateOwnsTimestampHoverPanelInVisibleScrollViewport() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent("Sources/VoyagerFeaturesAiChat/Ui/AiChatView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let supportURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerFeaturesAiChat/Ui/AiChatViewOverlaySupport.swift",
        )
        let contractSource = try source + "\n" + String(contentsOf: supportURL, encoding: .utf8)
        let contracts = [
            "struct AiChatTimestampTooltipGeometry",
            "struct AiChatTimestampTooltipAnchor",
            "struct AiChatTimestampTooltipAnchorPreferenceKey",
            "guard let candidate = nextValue() else { return }",
            "candidate.trigger.outranks(value?.trigger)",
            "struct AiChatTimestampTooltip: View",
            "transcriptScrollContent(",
            ".overlayPreferenceValue(AiChatTimestampTooltipAnchorPreferenceKey.self)",
            "GeometryReader { proxy in",
            "viewportBounds: CGRect(origin: .zero, size: proxy.size)",
            "messageBounds: proxy[messageBounds]",
            "clockBounds: proxy[anchor.clockBounds]",
            "AiChatTimestampTooltipSizing.resolve(",
            "availableWidth: proxy.size.width",
            ".position(x: geometry.frame.midX, y: geometry.frame.midY)",
            ".allowsHitTesting(false)",
            ".accessibilityHidden(true)",
        ]
        for contract in contracts {
            XCTAssertTrue(contractSource.contains(contract), "Missing viewport contract: \(contract)")
        }

        let transcriptViewStart = try XCTUnwrap(source.range(of: "    private func transcriptView("))
        let scrollContent = try XCTUnwrap(source.range(
            of: "        transcriptScrollContent(",
            range: transcriptViewStart.lowerBound ..< source.endIndex,
        ))
        let viewportOverlay = try XCTUnwrap(source.range(
            of: "        .overlayPreferenceValue(AiChatTimestampTooltipAnchorPreferenceKey.self)",
            range: scrollContent.lowerBound ..< source.endIndex,
        ))
        let scrollOnAppear = try XCTUnwrap(source.range(
            of: "        .onAppear {",
            range: viewportOverlay.lowerBound ..< source.endIndex,
        ))
        XCTAssertLessThan(scrollContent.lowerBound, viewportOverlay.lowerBound)
        XCTAssertLessThan(viewportOverlay.lowerBound, scrollOnAppear.lowerBound)
    }

    /// CBW-001-show_request_processing_state: timestamp 중복 제거는 실제 인접 행과 정확한 60초 경계를 사용한다.
    /// 같은 role의 연속 행이 숨겨진 행을 포함해 이어지더라도 persistence와 무관한 presentation 결과만 억제되는지 검증합니다.
    /// - 검증 내용: 59,999ms, 60,000ms, role 변경, nil, 역순, adjacent chain, identity, hover/focus disclosure를 확인합니다.
    /// - 사전 조건: timestamp 경계를 순서대로 포함한 user/assistant transcript를 사용합니다.
    /// - 기대 결과: 같은 role의 순방향 60초 미만 인접 행만 시각 label이 억제되고 accessibility label은 유지됩니다.
    func testShowRequestProcessingStateDeduplicatesOnlyEligibleAdjacentTranscriptRows() throws {
        let messages = [
            AiChatMessage(role: .assistant, content: "First", createdAtMs: 0),
            AiChatMessage(role: .assistant, content: "Hidden one", createdAtMs: 59999),
            AiChatMessage(role: .assistant, content: "Hidden chain", createdAtMs: 119_998),
            AiChatMessage(role: .assistant, content: "Exact boundary", createdAtMs: 179_998),
            AiChatMessage(role: .user, content: "Role change", createdAtMs: 180_000),
            AiChatMessage(role: .user, content: "Legacy nil"),
            AiChatMessage(role: .user, content: "After nil", createdAtMs: 180_001),
            AiChatMessage(role: .user, content: "Reverse", createdAtMs: 170_000),
        ]
        let presentation = try AiChatTranscriptPresentation(
            messages: messages,
            now: Date(timeIntervalSince1970: 10000),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: XCTUnwrap(TimeZone(secondsFromGMT: 0)),
        )

        XCTAssertEqual(
            presentation.rows.map(\.isTimestampVisuallySuppressed),
            [false, true, true, false, false, false, false, false],
        )
        XCTAssertEqual(
            presentation.rows.map(\.showsTimestampAffordance),
            [true, false, false, true, true, false, true, true],
        )
        let suppressedRow = presentation.rows[1]
        XCTAssertTrue(suppressedRow.hasTimestampMetadata)
        XCTAssertFalse(suppressedRow.showsTimestampAffordance)
        XCTAssertNotNil(suppressedRow.accessibilityTimestampLabel)
        XCTAssertNotNil(presentation.rows[2].accessibilityTimestampLabel)
        XCTAssertNil(presentation.rows[5].accessibilityTimestampLabel)
        XCTAssertFalse(presentation.rows[5].hasTimestampMetadata)
        XCTAssertEqual(
            presentation.rows[2].id,
            AiChatTranscriptRowID(index: 2, role: .assistant, createdAtMs: 119_998),
        )
    }

    /// CBW-001-show_request_processing_state: assistant 응답은 장식 icon 없이 신뢰 가능한 metadata만 표시한다.
    /// 과거 model을 추정하지 않고 본문 접근성을 유지하면서 active model/thinking/status header 계약을 보존하는지 검증합니다.
    /// - 검증 내용: completed historical의 header 부재, full header, 접근성 role label, icon source 부재를 확인합니다.
    /// - 사전 조건: historical 완료 응답과 streaming/processing/partial-failure가 공유하는 두 header 표현을 사용합니다.
    /// - 기대 결과: 양쪽 모두 장식 icon이 없고 historical은 role 접근성, full은 model metadata를 유지합니다.
    func testShowRequestProcessingStateOmitsDecorativeAssistantIcons() throws {
        XCTAssertFalse(AiChatAssistantHeaderPresentation.completedHistorical.showsVisualHeader)
        XCTAssertEqual(
            AiChatAssistantHeaderPresentation.completedHistorical.accessibilityRoleLabel,
            "Assistant response",
        )
        XCTAssertTrue(AiChatAssistantHeaderPresentation.full.showsVisualHeader)
        XCTAssertNil(AiChatAssistantHeaderPresentation.full.accessibilityRoleLabel)

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerFeaturesAiChat/Ui/AiChatConversationSurface.swift",
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let cardStart = try XCTUnwrap(source.range(of: "private struct AiChatAssistantCard: View"))
        let waitingStart = try XCTUnwrap(source.range(of: "private struct AiChatWaitingIndicator: View"))
        let cardSource = String(source[cardStart.lowerBound ..< waitingStart.lowerBound])
        XCTAssertTrue(cardSource.contains("if bodyPresentation.showsInlineHeader"))
        XCTAssertTrue(cardSource.contains("Text(title)"))
        XCTAssertTrue(cardSource.contains("thinkingLabel"))
        XCTAssertTrue(cardSource.contains("bodyContentView"))
        XCTAssertFalse(cardSource.contains("assistantRoleIcon"))
        XCTAssertFalse(cardSource.contains("bubble.right"))
    }

    /// CBW-001-show_request_processing_state: user message는 전용 borderless bubble token을 사용한다.
    /// Input·overlay token을 재해석하지 않고 더 둥근 user message semantic surface를 일관되게 적용하는지 검증합니다.
    /// - 검증 내용: shared token 정의, userMessage 함수 범위의 background·radius 참조, border 부재를 확인합니다.
    /// - 사전 조건: VoyagerDS가 user message bubble의 surface와 radius를 소유합니다.
    /// - 기대 결과: user message는 20pt continuous radius와 전용 background만 사용하고 stroke를 렌더링하지 않습니다.
    func testShowRequestProcessingStateUsesDedicatedBorderlessUserMessageBubbleToken() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let conversationURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerFeaturesAiChat/Ui/AiChatConversationSurface.swift",
        )
        let bubbleURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerFeaturesAiChat/Ui/AiChatUserMessageBubble.swift",
        )
        let packagesRoot = packageRoot.deletingLastPathComponent().deletingLastPathComponent()
        let tokenURL = packagesRoot.appendingPathComponent(
            "06_Shared/VoyagerShared/Sources/VoyagerShared/Config/VoyagerDS.swift",
        )
        _ = try String(contentsOf: conversationURL, encoding: .utf8)
        let bubbleSource = try String(contentsOf: bubbleURL, encoding: .utf8)
        let tokens = try String(contentsOf: tokenURL, encoding: .utf8)

        XCTAssertTrue(tokens.contains("public static let userMessageBubble: CGFloat = 20"))
        XCTAssertTrue(tokens.contains("public static func userMessageBubbleBackground"))
        XCTAssertTrue(bubbleSource.contains("VoyagerDS.Surface.userMessageBubbleBackground(for: colorScheme)"))
        XCTAssertTrue(bubbleSource.contains("VoyagerDS.Radius.userMessageBubble"))
        XCTAssertFalse(bubbleSource.contains(".strokeBorder("))
        XCTAssertFalse(bubbleSource.contains("VoyagerDS.Surface.inputBorder"))
    }

    /// CBW-001-show_request_processing_state: 대화 표면과 timestamp panel은 기존 VoyagerDS 토큰을 사용한다.
    /// 상태 카드, code surface, tooltip의 surface·border·radius·shadow가 토큰화되는지 검증합니다.
    /// - 검증 내용: ConversationSurface와 AiChatView의 토큰 참조 및 기존 하드코딩 surface/radius 제거를 확인합니다.
    /// - 사전 조건: VoyagerDS에 overlay, input, popover, radius, shadow 토큰이 정의되어 있습니다.
    /// - 기대 결과: 새 토큰 없이 named conversation surface가 기존 semantic token만 참조합니다.
    func testShowRequestProcessingStateUsesVoyagerDSTokensForConversationSurfaces() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let uiRoot = packageRoot.appendingPathComponent("Sources/VoyagerFeaturesAiChat/Ui")
        let conversation = try String(
            contentsOf: uiRoot.appendingPathComponent("AiChatConversationSurface.swift"),
            encoding: .utf8,
        )
        let markdown = try String(
            contentsOf: uiRoot.appendingPathComponent("AiChatAssistantMarkdownText.swift"),
            encoding: .utf8,
        ) + "\n" + String(
            contentsOf: uiRoot.appendingPathComponent("AiChatAssistantMarkdownBlock.swift"),
            encoding: .utf8,
        )
        let overlaySupport = try String(
            contentsOf: uiRoot.appendingPathComponent("AiChatViewOverlaySupport.swift"),
            encoding: .utf8,
        )

        let conversationContracts = [
            "VoyagerDS.Surface.overlayBackground(for: colorScheme)",
            "VoyagerDS.Surface.overlayBorder",
            "VoyagerDS.Surface.inputBackground(for: colorScheme)",
            "VoyagerDS.Surface.inputBorder(for: colorScheme)",
            "VoyagerDS.Radius.overlayCard",
        ]
        for contract in conversationContracts {
            XCTAssertTrue(conversation.contains(contract), "Missing conversation token: \(contract)")
        }
        for legacy in ["Color(nsColor: .controlBackgroundColor)", "cornerRadius: 16", "cornerRadius: 18"] {
            XCTAssertFalse(conversation.contains(legacy), "Unexpected conversation literal: \(legacy)")
        }
        XCTAssertTrue(markdown.contains("VoyagerDS.Surface.inputBackground(for: colorScheme)"))
        XCTAssertTrue(markdown.contains("VoyagerDS.Radius.control"))
        let tooltipStart = try XCTUnwrap(overlaySupport.range(of: "struct AiChatTimestampTooltip: View"))
        let panelStart = try XCTUnwrap(overlaySupport.range(of: "struct AiChatAssistantMetadataPanel: View"))
        let tooltipSource = String(overlaySupport[tooltipStart.lowerBound ..< panelStart.lowerBound])
        let tooltipContracts = [
            "VoyagerDS.Surface.popoverBackground(for: colorScheme)",
            "VoyagerDS.Surface.popoverBorder",
            "VoyagerDS.Shadow.popoverColor(for: colorScheme)",
            "VoyagerDS.Shadow.popoverRadius",
            "VoyagerDS.Shadow.popoverYOffset",
        ]
        for contract in tooltipContracts {
            XCTAssertTrue(tooltipSource.contains(contract), "Missing tooltip token: \(contract)")
        }
        XCTAssertFalse(tooltipSource.contains("cornerRadius: 7"))
    }

    /// CBW-001-show_request_processing_state: compact connection CTA 외곽은 VoyagerDS overlay 토큰을 사용한다.
    /// 버튼뿐 아니라 ChatPane 대응 container의 background·border·radius가 semantic token을 따르는지 검증합니다.
    /// - 검증 내용: compactConnectionCTA 함수 범위의 overlay token과 legacy literal 부재를 확인합니다.
    /// - 사전 조건: provider connection CTA가 AiChatView 내부 compact surface로 렌더링됩니다.
    /// - 기대 결과: 외곽과 버튼 모두 light/dark mode 대응 VoyagerDS surface를 사용합니다.
    func testShowRequestProcessingStateUsesVoyagerDSTokensForCompactConnectionCTA() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent("Sources/VoyagerFeaturesAiChat/Ui/AiChatView.swift")
        let view = try String(contentsOf: sourceURL, encoding: .utf8)
        let compactCTAStart = try XCTUnwrap(view.range(of: "    private func compactConnectionCTA(\n        title:"))
        let restoreStart = try XCTUnwrap(view.range(of: "    private func requestTranscriptScrollOffsetRestore"))
        let compactCTASource = String(view[compactCTAStart.lowerBound ..< restoreStart.lowerBound])
        XCTAssertTrue(compactCTASource.contains("VoyagerDS.Radius.overlayCard"))
        XCTAssertTrue(compactCTASource.contains("VoyagerDS.Surface.overlayBackground(for: colorScheme)"))
        XCTAssertTrue(compactCTASource.contains("VoyagerDS.Surface.overlayBorder"))
        XCTAssertFalse(compactCTASource.contains("cornerRadius: 16"))
        XCTAssertFalse(compactCTASource.contains("Color.primary.opacity"))
    }

    /// CBW-001-show_request_processing_state: composer와 session surface는 VoyagerDS 토큰을 사용한다.
    /// develop의 native selector menu와 VOY-635 surface에서 legacy literal이 제거되는지 검증합니다.
    /// - 검증 내용: input/session semantic token, native model/thinking menu, 금지 literal을 확인합니다.
    /// - 사전 조건: selector는 custom popover 대신 native Menu를 사용합니다.
    /// - 기대 결과: composer·session surface는 VoyagerDS 토큰을, selector는 native Menu를 사용합니다.
    func testShowRequestProcessingStateUsesVoyagerDSTokensForComposerSelectorsAndSessions() throws {
        struct SourceContract {
            let file: String
            let expected: String
            let forbidden: String
        }

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let uiRoot = packageRoot.appendingPathComponent("Sources/VoyagerFeaturesAiChat/Ui")
        let contracts = [
            SourceContract(
                file: "AiChatInputBar.swift", expected: "VoyagerDS.Radius.composer", forbidden: "cornerRadius: 18",
            ),
            SourceContract(
                file: "AiChatSelectors.swift",
                expected: "Menu {",
                forbidden: "Color.black.opacity(0.16)",
            ),
            SourceContract(
                file: "AiChatSelectors.swift",
                expected: "Menu {",
                forbidden: "row.isSelected ? Color.primary.opacity",
            ),
            SourceContract(
                file: "AiChatThinkingSelector.swift",
                expected: "Menu {",
                forbidden: "isSelected ? Color.primary.opacity",
            ),
            SourceContract(
                file: "AiChatSessionsView.swift", expected: "VoyagerDS.Radius.control", forbidden: "cornerRadius: 10",
            ),
        ]
        for contract in contracts {
            let source = try String(
                contentsOf: uiRoot.appendingPathComponent(contract.file), encoding: .utf8,
            )
            XCTAssertTrue(source.contains(contract.expected), "Missing \(contract.file) token: \(contract.expected)")
            XCTAssertFalse(
                source.contains(contract.forbidden),
                "Unexpected \(contract.file) literal: \(contract.forbidden)",
            )
        }
    }

    /// CBW-001-show_request_processing_state: waiting은 processing의 nil 또는 trim-empty content에서만 표시한다.
    /// 첫 유효 chunk와 terminal failure가 waiting을 즉시 제거하고 Reduce Motion이 정적 표현을 사용하는지 검증합니다.
    /// - 검증 내용: nil/whitespace/content/terminal/partial failure와 dot cycle projection을 확인합니다.
    /// - 사전 조건: 같은 assistant body 입력에서 processing, final, failure 조합을 각각 구성합니다.
    /// - 기대 결과: processing empty만 waiting이고 dot은 .→..→...로 순환하며 Reduce Motion은 항상 ...입니다.
    func testShowRequestProcessingStateWaitsOnlyForEmptyProcessingContent() {
        let nilWaiting = AiChatAssistantBodyPresentation(content: nil, isProcessing: true, failure: nil)
        let whitespaceWaiting = AiChatAssistantBodyPresentation(
            content: "  \n", isProcessing: true, failure: nil,
        )
        let activeBody = AiChatAssistantBodyPresentation(
            content: "First chunk", isProcessing: true, failure: nil,
        )
        let contentlessFailure = AiChatAssistantBodyPresentation(
            content: nil, isProcessing: false, failure: .network,
        )
        let partialFailure = AiChatAssistantBodyPresentation(
            content: "Partial response", isProcessing: false, failure: .network,
        )

        XCTAssertEqual(nilWaiting.state, .waiting)
        XCTAssertTrue(nilWaiting.showsInlineHeader)
        XCTAssertTrue(nilWaiting.showsWaiting)
        XCTAssertEqual(whitespaceWaiting.state, .waiting)
        XCTAssertTrue(whitespaceWaiting.showsWaiting)
        XCTAssertEqual(activeBody.state, .activeProcessingBody)
        XCTAssertFalse(activeBody.showsInlineHeader)
        XCTAssertFalse(activeBody.showsWaiting)
        XCTAssertEqual(contentlessFailure.state, .terminalContentlessFailure)
        XCTAssertFalse(contentlessFailure.showsInlineHeader)
        XCTAssertEqual(partialFailure.state, .partialFailureBody)
        XCTAssertEqual(partialFailure.content, "Partial response")
        XCTAssertEqual(
            (0 ..< 6).map { AiChatAssistantBodyPresentation.waitingText(step: $0, reduceMotion: false) },
            [".", "..", "...", ".", "..", "..."],
        )
        XCTAssertEqual(AiChatAssistantBodyPresentation.waitingText(step: 1, reduceMotion: true), "...")
    }

    /// CBW-001-show_request_processing_state: model metadata panel은 현재 active body에만 허용한다.
    /// model-only와 model+thinking label을 정규화하고 failure·historical·request 불일치를 배제하는지 검증합니다.
    /// - 검증 내용: metadata label 조합과 processing/failure/history/request identity eligibility를 확인합니다.
    /// - 사전 조건: 두 request identity와 active, partial failure, historical 표시 입력을 구성합니다.
    /// - 기대 결과: matching active body만 eligible이며 thinking이 없으면 model title만 남습니다.
    func testShowRequestProcessingStateAllowsMetadataOnlyForMatchingActiveBody() {
        let currentID = AiChatRequestID(rawValue: makeUUID("11111111-1111-1111-1111-111111114201"))
        let staleID = AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222224201"))
        let active = AiChatAssistantBodyPresentation(
            content: "Answer",
            isProcessing: true,
            failure: nil,
            title: "Model",
            thinkingLabel: "High",
            requestID: currentID,
            foregroundRequestID: currentID,
        )
        let stale = AiChatAssistantBodyPresentation(
            content: "Answer",
            isProcessing: true,
            failure: nil,
            title: "Model",
            thinkingLabel: nil,
            requestID: staleID,
            foregroundRequestID: currentID,
        )
        let partialFailure = AiChatAssistantBodyPresentation(
            content: "Partial",
            isProcessing: false,
            failure: .network,
            requestID: currentID,
            foregroundRequestID: currentID,
        )
        let historical = AiChatAssistantBodyPresentation(
            content: "Done",
            isProcessing: false,
            failure: nil,
            headerPresentation: .completedHistorical,
        )

        XCTAssertEqual(active.metadataPanelLabel, "Model · High")
        XCTAssertTrue(active.isMetadataPanelEligible)
        XCTAssertEqual(stale.metadataPanelLabel, "Model")
        XCTAssertFalse(stale.isMetadataPanelEligible)
        XCTAssertFalse(partialFailure.isMetadataPanelEligible)
        XCTAssertFalse(historical.isMetadataPanelEligible)
        XCTAssertEqual(historical.state, .historical)
    }

    /// CBW-001-show_request_processing_state: hover 또는 keyboard focus가 metadata panel을 즉시 표시한다.
    /// 두 trigger가 독립적으로 동작하고 eligibility 제거 시 panel이 닫히는 순수 표시 결정을 검증합니다.
    /// - 검증 내용: hover/focus OR 조건과 ineligible reset 결과를 확인합니다.
    /// - 사전 조건: active body eligibility와 hover/focus Boolean 조합을 사용합니다.
    /// - 기대 결과: eligible hover 또는 focus만 true이고 identity 교체로 ineligible이면 즉시 false입니다.
    func testShowRequestProcessingStateTriggersMetadataPanelFromHoverOrFocus() {
        let presents = AiChatAssistantBodyPresentation.presentsMetadataPanel
        XCTAssertFalse(presents(true, false, false))
        XCTAssertTrue(presents(true, true, false))
        XCTAssertTrue(presents(true, false, true))
        XCTAssertTrue(presents(true, true, true))
        XCTAssertFalse(presents(false, true, false))
        XCTAssertFalse(presents(false, false, true))
    }

    /// CBW-001-show_request_processing_state: metadata panel geometry는 visible viewport 안에서 flip·clamp한다.
    /// body의 visible intersection만 기준으로 top/bottom/narrow/oversized/empty 경계를 계산하는지 검증합니다.
    /// - 검증 내용: vertical placement, 4pt inset, width clamp, oversized intersection, empty rejection을 확인합니다.
    /// - 사전 조건: 200x120 viewport와 220x40 preferred panel 및 다양한 body frame을 사용합니다.
    /// - 기대 결과: panel은 viewport를 벗어나지 않고 보이지 않는 body에는 생성되지 않습니다.
    func testShowRequestProcessingStateClampsMetadataPanelToVisibleViewport() throws {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 120)
        let preferred = CGSize(width: 220, height: 40)
        let top = try XCTUnwrap(AiChatAssistantMetadataPanelGeometry.resolve(
            viewportBounds: viewport,
            bodyBounds: CGRect(x: 10, y: 0, width: 180, height: 20),
            preferredSize: preferred,
        ))
        let bottom = try XCTUnwrap(AiChatAssistantMetadataPanelGeometry.resolve(
            viewportBounds: viewport,
            bodyBounds: CGRect(x: 10, y: 100, width: 180, height: 20),
            preferredSize: preferred,
        ))
        let narrow = try XCTUnwrap(AiChatAssistantMetadataPanelGeometry.resolve(
            viewportBounds: CGRect(x: 0, y: 0, width: 40, height: 120),
            bodyBounds: CGRect(x: 0, y: 40, width: 80, height: 20),
            preferredSize: preferred,
        ))
        let oversized = try XCTUnwrap(AiChatAssistantMetadataPanelGeometry.resolve(
            viewportBounds: viewport,
            bodyBounds: CGRect(x: -20, y: -40, width: 240, height: 220),
            preferredSize: preferred,
        ))

        XCTAssertEqual(top.verticalPlacement, .below)
        XCTAssertEqual(bottom.verticalPlacement, .above)
        XCTAssertEqual(narrow.frame.minX, 4)
        XCTAssertLessThanOrEqual(narrow.frame.maxX, 36)
        XCTAssertEqual(oversized.visibleBodyBounds, viewport)
        XCTAssertNil(AiChatAssistantMetadataPanelGeometry.resolve(
            viewportBounds: viewport,
            bodyBounds: CGRect(x: 300, y: 300, width: 20, height: 20),
            preferredSize: preferred,
        ))
    }

    /// CBW-001-show_request_processing_state: metadata trigger와 panel source contract는 전용 subtree에만 존재한다.
    /// Markdown interaction을 보존하면서 request 교체 cleanup, anchor 발행, 비상호작용 panel을 정확한 범위에서 검증합니다.
    /// - 검증 내용: card hover/focus/accessibility/anchor와 panel hit testing/accessibility/motion/native help 부재를 확인합니다.
    /// - 사전 조건: conversation card와 AiChatView metadata panel source subtree를 분리해 읽습니다.
    /// - 기대 결과: active card만 trigger를 소유하고 panel은 hit-test와 VoiceOver에서 제외됩니다.
    func testShowRequestProcessingStateKeepsMetadataPanelCustomAndNoninteractive() throws {
        let sources = try aiChatMetadataSourceSubtrees()
        let cardContracts = [
            ".onHover { isMetadataHovered = bodyPresentation.isMetadataPanelEligible && $0 }",
            ".focusable(bodyPresentation.isMetadataPanelEligible)",
            ".focused($isMetadataFocused)",
            ".onChange(of: requestID)",
            ".onChange(of: bodyPresentation.isMetadataPanelEligible)",
            "key: AiChatAssistantMetadataAnchorPreferenceKey.self",
            ".modifier(AiChatAssistantMetadataAccessibilityValue(label: bodyPresentation.accessibilityMetadataLabel))",
        ]
        for contract in cardContracts {
            XCTAssertTrue(sources.card.contains(contract), "Missing card metadata contract: \(contract)")
        }
        XCTAssertFalse(sources.card.contains(".help("))
        XCTAssertTrue(sources.panel.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(sources.panel.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(sources.panel.contains(".help("))
        XCTAssertFalse(sources.panel.contains(".transition("))
        XCTAssertFalse(sources.panel.contains(".animation("))
    }

    /// CBW-001-show_request_processing_state: ScrollView renderer는 현재 request anchor만 deterministic하게 선택한다.
    /// 동시 stale preference가 있어도 foreground requestID lookup으로 viewport panel이 누출되지 않는지 검증합니다.
    /// - 검증 내용: requestID-keyed preference reduction, current lookup, visible intersection renderer ownership을 확인합니다.
    /// - 사전 조건: AiChatView의 anchor preference와 transcript ScrollView source subtree를 읽습니다.
    /// - 기대 결과: renderer는 anchors[foregroundRequestID]만 사용하고 historical card는 anchor identity를 받지 않습니다.
    func testShowRequestProcessingStateSelectsOnlyCurrentMetadataAnchorInViewport() throws {
        let sources = try aiChatMetadataSourceSubtrees()
        let viewportContracts = [
            "static let defaultValue: [AiChatRequestID: AiChatAssistantMetadataAnchor] = [:]",
            "value.merge(nextValue()) { _, candidate in candidate }",
            ".overlayPreferenceValue(AiChatAssistantMetadataAnchorPreferenceKey.self)",
            "(state.streamingAssistantDisplayModel?.requestID).flatMap { anchors[$0] }",
            "bodyBounds: proxy[anchor.bodyBounds]",
            "if let geometry = AiChatAssistantMetadataPanelGeometry.resolve(",
        ]
        for contract in viewportContracts {
            XCTAssertTrue(sources.viewport.contains(contract), "Missing viewport metadata contract: \(contract)")
        }
        XCTAssertTrue(sources.card.contains("requestID: AiChatRequestID?"))
        XCTAssertTrue(sources.card.contains("foregroundRequestID: AiChatRequestID?"))
        XCTAssertFalse(sources.historicalCard.contains("requestID:"))
        XCTAssertFalse(sources.historicalCard.contains("foregroundRequestID:"))
    }

    /// CBW-001-show_request_processing_state: 현재 보이는 request의 coarse lifecycle만 announcement로 투영한다.
    /// 화면 밖 request와 delta·selector·timestamp 변화가 lifecycle announcement를 만들지 않는지 검증합니다.
    /// - 검증 내용: visible session 일치, requestID+phase key, lifecycle message/priority, coarse projection 동등성을 확인합니다.
    /// - 사전 조건: 현재 session과 다른 request lock으로 시작한 뒤 같은 lock을 visible session에 연결합니다.
    /// - 기대 결과: offscreen은 nil이고 processing/final/failure/cancel만 고유 key를 가지며 비-lifecycle 변화는 동일 projection입니다.
    func testShowRequestProcessingStateProjectsOnlyVisibleRequestLifecycleAnnouncements() throws {
        let rows = makeCatalogRows()
        let visibleSessionID = AiChatSessionID(
            rawValue: makeUUID("11111111-1111-1111-1111-111111115001"),
        )
        let requestSessionID = AiChatSessionID(
            rawValue: makeUUID("22222222-2222-2222-2222-222222225001"),
        )
        let requestID = AiChatRequestID(
            rawValue: makeUUID("33333333-3333-3333-3333-333333335001"),
        )
        let context = makeRequestContext(
            sessionID: requestSessionID,
            requestID: requestID,
            runID: AiChatRunID(rawValue: makeUUID("44444444-4444-4444-4444-444444445001")),
            model: rows[0].handle,
            selectedRow: rows[0],
        )
        let request = AiChatRequest(context: context, messages: [])
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: rows[0].handle,
            selectedRow: rows[0],
            assistantReplacementIndex: nil,
        )
        var state = AiChatFeature.State(
            sessionID: visibleSessionID,
            executionPhase: .processing(lock),
        )

        XCTAssertNil(AiChatLifecycleAnnouncement(state: state))

        state.sessionID = requestSessionID
        let lifecycleCases: [LifecycleAnnouncementCase] = [
            .init(
                phase: .processing(lock),
                expectedPhase: .processing,
                message: "Assistant response started.",
                priority: .medium,
            ),
            .init(
                phase: .completed(lock),
                expectedPhase: .final,
                message: "Assistant response completed.",
                priority: .medium,
            ),
            .init(
                phase: .failed(lock, .network),
                expectedPhase: .failure,
                message: "Assistant response failed.",
                priority: .high,
            ),
            .init(
                phase: .cancelled(lock),
                expectedPhase: .cancel,
                message: "Assistant response cancelled.",
                priority: .medium,
            ),
        ]

        for lifecycleCase in lifecycleCases {
            state.executionPhase = lifecycleCase.phase
            let announcement = try XCTUnwrap(AiChatLifecycleAnnouncement(state: state))
            XCTAssertEqual(announcement.key.sessionID, requestSessionID)
            XCTAssertEqual(announcement.key.requestID, requestID)
            XCTAssertEqual(announcement.key.phase, lifecycleCase.expectedPhase)
            XCTAssertEqual(announcement.message, lifecycleCase.message)
            XCTAssertEqual(announcement.priority, lifecycleCase.priority)
        }

        state.executionPhase = .processing(lock)
        let processing = try XCTUnwrap(AiChatLifecycleAnnouncement(state: state))
        state.streamingAssistantDraft = "delta"
        state.selectedModelHandle = rows.last?.handle
        state.transcriptHistory = [
            AiChatMessage(role: .user, content: "Question", createdAtMs: 1_700_000_005_001),
        ]
        XCTAssertEqual(AiChatLifecycleAnnouncement(state: state), processing)
    }

    /// CBW-001-show_request_processing_state: mounted stable chat root는 lifecycle announcement를 정확히 한 번씩 전달한다.
    /// 실제 SwiftUI observer가 centered-empty 전환과 rerender에서 started를 중복하지 않고 sessions에는 발화하지 않는지 검증합니다.
    /// - 검증 내용: initial, processing, same-processing rerender, completed, sessions 순서의 injected sink post를 확인합니다.
    /// - 사전 조건: centered content가 있는 chat mode AiChatView를 NSHostingView에 mount하고 내부 sink를 주입합니다.
    /// - 기대 결과: initial 0회, started 1회, rerender 추가 0회, completed 추가 1회, sessions 추가 0회입니다.
    func testShowRequestProcessingStatePostsMountedStableRootLifecycleExactlyOnce() async {
        let wasPerceptionCheckingEnabled = isPerceptionCheckingEnabled
        isPerceptionCheckingEnabled = false
        defer { isPerceptionCheckingEnabled = wasPerceptionCheckingEnabled }

        let rows = makeCatalogRows()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111115002"))
        let context = makeRequestContext(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222225002")),
            runID: AiChatRunID(rawValue: makeUUID("33333333-3333-3333-3333-333333335002")),
            model: rows[0].handle,
            selectedRow: rows[0],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(context: context, messages: []),
            selectedHandle: rows[0].handle,
            selectedRow: rows[0],
            assistantReplacementIndex: nil,
        )
        let fixture = makeMountedLifecycleAnnouncementFixture(sessionID: sessionID, lock: lock)
        await settleMountedLifecycleAnnouncementView(fixture.hostingView)
        XCTAssertEqual(fixture.recorder.announcements, [])

        fixture.store.send(.draftTextChanged(CBW001LifecycleViewCommand.processing))
        await settleMountedLifecycleAnnouncementView(fixture.hostingView)
        XCTAssertEqual(fixture.recorder.announcements.map(\.message), ["Assistant response started."])

        fixture.store.send(.draftTextChanged(CBW001LifecycleViewCommand.processingRerender))
        await settleMountedLifecycleAnnouncementView(fixture.hostingView)
        XCTAssertEqual(fixture.recorder.announcements.map(\.message), ["Assistant response started."])

        fixture.store.send(.draftTextChanged(CBW001LifecycleViewCommand.completed))
        await settleMountedLifecycleAnnouncementView(fixture.hostingView)
        XCTAssertEqual(
            fixture.recorder.announcements.map(\.message),
            ["Assistant response started.", "Assistant response completed."],
        )

        fixture.store.send(.draftTextChanged(CBW001LifecycleViewCommand.sessions))
        await settleMountedLifecycleAnnouncementView(fixture.hostingView)
        XCTAssertEqual(
            fixture.recorder.announcements.map(\.message),
            ["Assistant response started.", "Assistant response completed."],
        )
        XCTAssertEqual(fixture.recorder.announcements.map(\.key.phase), [.processing, .final])
        XCTAssertIdentical(fixture.window.contentView, fixture.hostingView)
    }

    /// CBW-001-show_request_processing_state: provider status를 손실 없이 Feature event로 전달한다.
    /// provider가 보낸 typed activity signal이 context와 함께 동일한 Feature event로 도착하는 경계를 검증합니다.
    /// - 검증 내용: AiChatExecutionClient live adapter의 status context와 signal 1:1 mapping을 확인합니다.
    /// - 사전 조건: provider stream이 하나의 searching began status를 보낸 뒤 종료합니다.
    /// - 기대 결과: Feature stream은 동일한 context와 signal을 가진 status event 하나를 방출합니다.
    func testShowRequestProcessingStateMapsProviderStatusOneToOne() async {
        let rows = makeCatalogRows()
        let context = makeRequestContext(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114101")),
            requestID: AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222224101")),
            runID: AiChatRunID(rawValue: makeUUID("33333333-3333-3333-3333-333333334101")),
            model: rows[0].handle,
            selectedRow: rows[0],
        )
        let signal = makeActivitySignal(id: "search-1", kind: .searching, phase: .began)
        let providerClient = AiChatProviderExecutionClient { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.status(context: context, signal: signal))
                continuation.finish()
            }
        }
        var iterator = AiChatExecutionClient.live(providerExecutionClient: providerClient)
            .execute(AiChatRequest(context: context, messages: []), nil)
            .makeAsyncIterator()

        let mappedEvent = await iterator.next()
        let terminalEvent = await iterator.next()
        XCTAssertEqual(mappedEvent, .status(context: context, signal: signal))
        XCTAssertNil(terminalEvent)
    }

    /// CBW-001-show_request_processing_state: 병렬 activity는 ID와 명시적 begin 순서로 선택된다.
    /// interleaving status가 transcript나 stream observability를 건드리지 않고 matching request lock만 갱신하는지 검증합니다.
    /// - 검증 내용: A begin, B begin, B end, unknown end, repeated A begin과 session identity rejection을 확인합니다.
    /// - 사전 조건: visible processing request에 고정 transcript, draft, chunk count, autoscroll version이 있습니다.
    /// - 기대 결과: B 종료 후 A가 다시 선택되고 중복 ID는 하나만 남으며 status 외 상태는 불변입니다.
    func testShowRequestProcessingStateTracksInterleavedActivitiesWithoutStreamSideEffects() async {
        let rows = makeCatalogRows()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114102"))
        let context = makeRequestContext(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222224102")),
            runID: AiChatRunID(rawValue: makeUUID("33333333-3333-3333-3333-333333334102")),
            model: rows[0].handle,
            selectedRow: rows[0],
            selectedThinking: .effort(.high),
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(context: context, messages: []),
            selectedHandle: rows[0].handle,
            selectedRow: rows[0],
            assistantReplacementIndex: nil,
        )
        let transcript = [AiChatMessage(role: .user, content: "Question")]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            transcriptHistory: transcript,
            streamingAssistantDraft: "Partial",
            transcriptAutoScrollVersion: 7,
            catalogRows: rows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: rows[0].handle,
            executionPhase: .processing(lock),
        )) {
            AiChatFeature()
        }
        let thinking = makeActivitySignal(id: "activity-a", kind: .thinking, phase: .began)
        let tool = makeActivitySignal(id: "activity-b", kind: .toolExecution, phase: .began)

        await store.send(.executionEvent(.status(context: context, signal: thinking))) {
            $0.executionPhase = .processing(lock.recordingActivity(thinking))
        }
        let thinkingAndTool = lock.recordingActivity(thinking).recordingActivity(tool)
        await store.send(.executionEvent(.status(context: context, signal: tool))) {
            $0.executionPhase = .processing(thinkingAndTool)
        }
        let toolEnded = makeActivitySignal(id: "activity-b", kind: .toolExecution, phase: .ended)
        let toolEndedLock = thinkingAndTool.recordingActivity(toolEnded)
        await store.send(.executionEvent(.status(context: context, signal: toolEnded))) {
            $0.executionPhase = .processing(toolEndedLock)
        }
        XCTAssertEqual(toolEndedLock.activityState.selectedActivity?.activityID, thinking.activityID)
        XCTAssertEqual(store.state.streamingAssistantDisplayModel?.activityStatusLabel, "Thinking…")

        let beforeNoOps = store.state
        let unknownEnd = makeActivitySignal(id: "unknown", kind: .searching, phase: .ended)
        await store.send(.executionEvent(.status(context: context, signal: unknownEnd)))
        let wrongSessionContext = makeRequestContext(
            sessionID: AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444102")),
            requestID: context.requestID,
            runID: context.runID,
            model: rows[0].handle,
            selectedRow: rows[0],
        )
        await store.send(.executionEvent(.status(context: wrongSessionContext, signal: thinking)))
        XCTAssertEqual(store.state, beforeNoOps)

        await store.send(.executionEvent(.status(context: context, signal: thinking))) {
            $0.executionPhase = .processing(toolEndedLock.recordingActivity(thinking))
        }
        XCTAssertEqual(store.state.executionPhase.lock?.activityState.activeActivities.count, 1)
        XCTAssertEqual(store.state.executionPhase.lock?.activityState.beginOrder, [thinking.activityID])
        XCTAssertEqual(store.state.transcriptHistory, transcript)
        XCTAssertEqual(store.state.streamingAssistantDraft, "Partial")
        XCTAssertEqual(store.state.executionPhase.lock?.observabilitySummary.chunkCount, 0)
        XCTAssertEqual(store.state.transcriptAutoScrollVersion, 7)
    }

    /// CBW-001-show_request_processing_state: runtime activity와 waiting 상태만 truthful label로 투영한다.
    /// 선택 thinking 구성은 header metadata로 유지하되 provider activity evidence로 오해하지 않는 표시 계약을 검증합니다.
    /// - 검증 내용: closed activity kind labels, empty waiting fallback, content 상태, spinner-free header를 확인합니다.
    /// - 사전 조건: processing display model에 activity 유무와 content 유무 조합을 구성합니다.
    /// - 기대 결과: activity는 고정 label, empty/no-activity는 waiting, content/no-activity는 nil이며 spinner는 표시하지 않습니다.
    func testShowRequestProcessingStateProjectsTruthfulActivityLabelsWithoutSpinner() {
        XCTAssertEqual(AiChatExecutionActivityKind.thinking.aiChatStatusLabel, "Thinking…")
        XCTAssertEqual(AiChatExecutionActivityKind.searching.aiChatStatusLabel, "Searching…")
        XCTAssertEqual(AiChatExecutionActivityKind.toolExecution.aiChatStatusLabel, "Running a tool…")
        XCTAssertEqual(AiChatExecutionActivityKind.retrying.aiChatStatusLabel, "Retrying…")
        XCTAssertEqual(AiChatExecutionActivityKind.answerGeneration.aiChatStatusLabel, "Generating answer…")
        XCTAssertFalse(AiChatAssistantHeaderPresentation.full.showsProgressIndicator)

        let requestID = AiChatRequestID(rawValue: makeUUID("11111111-1111-1111-1111-111111114202"))
        let waiting = AiChatStreamingAssistantDisplayModel(
            requestID: requestID,
            content: nil,
            title: "Model",
            thinkingLabel: "High",
            acceptedChunkRevision: 0,
            activityStatusLabel: "Waiting for response…",
        )
        let streaming = AiChatStreamingAssistantDisplayModel(
            requestID: requestID,
            content: "Answer",
            title: "Model",
            thinkingLabel: "High",
            acceptedChunkRevision: 1,
            activityStatusLabel: nil,
        )
        XCTAssertEqual(waiting.thinkingLabel, "High")
        XCTAssertEqual(waiting.activityStatusLabel, "Waiting for response…")
        XCTAssertNil(streaming.activityStatusLabel)
    }

    /// CBW-001-show_request_processing_state: activity announcement는 stable transition key마다 한 번만 전달된다.
    /// delta나 view 재생성 경계에서도 같은 request/activity/kind/phase transition이 반복 발화되지 않는지 검증합니다.
    /// - 검증 내용: activity key 구성, deduper 중복 거부, coarse final key 전달을 확인합니다.
    /// - 사전 조건: visible processing lock에 searching began activity가 있고 동일 announcement를 두 번 평가합니다.
    /// - 기대 결과: activity transition은 첫 평가만 허용되고 final lifecycle announcement는 별도로 허용됩니다.
    func testShowRequestProcessingStateDeduplicatesActivityAccessibilityAnnouncements() throws {
        let rows = makeCatalogRows()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114103"))
        let context = makeRequestContext(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222224103")),
            runID: AiChatRunID(rawValue: makeUUID("33333333-3333-3333-3333-333333334103")),
            model: rows[0].handle,
            selectedRow: rows[0],
        )
        let signal = makeActivitySignal(id: "search-accessibility", kind: .searching, phase: .began)
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(context: context, messages: []),
            selectedHandle: rows[0].handle,
            selectedRow: rows[0],
            assistantReplacementIndex: nil,
        ).recordingActivity(signal)
        var state = AiChatFeature.State(sessionID: sessionID, executionPhase: .processing(lock))
        let activity = try XCTUnwrap(AiChatLifecycleAnnouncement(state: state))
        XCTAssertEqual(activity.key.activityID, signal.activityID)
        XCTAssertEqual(activity.key.activityKind, .searching)
        XCTAssertEqual(activity.key.activityPhase, .began)

        var deduper = AiChatAccessibilityAnnouncementDeduper()
        XCTAssertTrue(deduper.shouldAnnounce(activity.key))
        XCTAssertFalse(deduper.shouldAnnounce(activity.key))

        state.executionPhase = .completed(lock.recordingTerminal(at: 10, failure: nil, wasCancelled: false))
        let final = try XCTUnwrap(AiChatLifecycleAnnouncement(state: state))
        XCTAssertTrue(deduper.shouldAnnounce(final.key))

        let otherSessionKey = AiChatLifecycleAnnouncementKey(
            sessionID: AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444103")),
            requestID: activity.key.requestID,
            phase: activity.key.phase,
            activityID: activity.key.activityID,
            activityKind: activity.key.activityKind,
            activityPhase: activity.key.activityPhase,
        )
        XCTAssertTrue(deduper.shouldAnnounce(otherSessionKey))
    }

    // MARK: - CBW-001-cancel_active_chat_request

    /// CBW-001-cancel_active_chat_request: 취소로 streaming draft가 제거되면 검색 projection identity를 갱신한다.
    /// 사용자가 partial response를 검색하던 중 요청을 취소해도 사라진 응답의 검색 결과가 남지 않는지 검증합니다.
    /// - 검증 내용: 전용 draft revision, auto-scroll 독립성, request identity, stale result 거부와 zero-result 상태를 확인합니다.
    /// - 사전 조건: active transcript search query `Hel`이 partial streaming assistant draft 한 건과 일치합니다.
    /// - 기대 결과: 취소 후 draft revision만 증가하고 projection은 no-results이며 기존 navigation intent는 유지됩니다.
    func testCancelActiveChatRequestInvalidatesStreamingSearchProjectionWhenDraftClears() async throws {
        let fixture = makeStreamFixture(draftText: "Cancel me", fixedMs: 1_700_000_000_200)
        applyObservationFocusedExhaustivity(to: fixture.store)

        await fixture.store.send(.submitTapped)
        await resolvePendingRequestContext(fixture.store) { state in
            self.applyCancelStartedState(
                &state,
                selectedHandle: fixture.selectedHandle,
                submittedAtMs: fixture.fixedMs,
            )
        }
        let request = try XCTUnwrap(fixture.stream.requests.first)
        let lock = makeSubmitLock(
            request: request,
            catalogRows: fixture.catalogRows,
            selectedHandle: fixture.selectedHandle,
        )
        let streamingLock = await receiveCancelStreamingDelta(
            on: fixture.store,
            stream: fixture.stream,
            request: request,
            lock: lock,
            fixedMs: fixture.fixedMs,
        )
        await fixture.store.send(.transcriptSearchOpened) { state in
            state.transcriptSearch.isPresented = true
            state.transcriptSearch.focusRevision = 1
        }
        await fixture.store.send(.transcriptSearchQueryChanged("Hel")) { state in
            state.transcriptSearch.query = "Hel"
        }

        var requestCache = AiChatTranscriptSearchRequestCache()
        let beforeRequest = makeTranscriptSearchProjectionRequest(
            for: fixture.store.state,
            cache: &requestCache,
        )
        let projector = AiChatTranscriptSearchProjector(streamingDebounce: .zero)
        let beforeResult = try await projector.project(beforeRequest, generation: 1)
        let draftRevisionBeforeCancel = fixture.store.state.streamingAssistantDraftMutationTracker.value
        let autoScrollVersionBeforeCancel = fixture.store.state.transcriptAutoScrollVersion
        let navigationRevisionBeforeCancel = fixture.store.state.transcriptSearch.navigationRevision

        await sendCancelAndLateTerminalEvents(
            on: fixture.store,
            request: request,
            streamingLock: streamingLock,
            fixedMs: fixture.fixedMs,
        )
        let afterRequest = makeTranscriptSearchProjectionRequest(
            for: fixture.store.state,
            cache: &requestCache,
        )
        let afterResult = try await projector.project(afterRequest, generation: 2)

        XCTAssertNil(fixture.store.state.streamingAssistantDraft)
        XCTAssertNotEqual(
            fixture.store.state.streamingAssistantDraftMutationTracker.value,
            draftRevisionBeforeCancel,
        )
        XCTAssertEqual(fixture.store.state.transcriptAutoScrollVersion, autoScrollVersionBeforeCancel)
        XCTAssertNotEqual(beforeRequest, afterRequest)
        XCTAssertFalse(beforeResult.isCurrent(request: afterRequest, generation: 2))
        XCTAssertTrue(afterResult.presentation.matches.isEmpty)

        let countProjection: AiChatTranscriptSearchMatchCountProjection = afterResult.presentation.matchCountProjection
        await fixture.store.send(.transcriptSearchMatchCountChanged(countProjection)) { state in
            state.transcriptSearch.matchCount = 0
            state.transcriptSearch.currentMatchOrdinal = 0
            state.transcriptSearch.status = .noResults
        }
        XCTAssertEqual(fixture.store.state.transcriptSearch.status, .noResults)
        XCTAssertNil(afterResult.presentation
            .descriptor(atOrdinal: fixture.store.state.transcriptSearch.currentMatchOrdinal))
        XCTAssertEqual(fixture.store.state.transcriptSearch.navigationRevision, navigationRevisionBeforeCancel)
        assertCancelResult(fixture.store.state, streamingLock: streamingLock, fixedMs: fixture.fixedMs)
        await fixture.store.finish()
    }

    /// CBW-001-cancel_active_chat_request: 취소 이후 늦게 도착한 terminal event는 transcript를 변경하지 않는다.
    /// 사용자가 active request를 취소한 뒤 stale delta/final/failure가 durable state를 오염시키지 않는지 검증합니다.
    /// - 검증 내용: cancelled executionPhase, assistant message 부재, locked model/draft/failure cleanup을 확인합니다.
    /// - 사전 조건: provider stream이 partial delta를 보낸 뒤 사용자가 cancel을 누릅니다.
    /// - 기대 결과: late event는 무시되고 transcript에는 취소 전 사용자 메시지만 유지됩니다.
    func testCancelActiveChatRequestRejectsLateTerminalEvents() async {
        let fixture = makeStreamFixture(draftText: "Cancel me", fixedMs: 1_700_000_000_200)
        applyObservationFocusedExhaustivity(to: fixture.store)

        await fixture.store.send(.submitTapped)
        await resolvePendingRequestContext(fixture.store) { state in
            self.applyCancelStartedState(
                &state,
                selectedHandle: fixture.selectedHandle,
                submittedAtMs: fixture.fixedMs,
            )
        }
        guard let request = fixture.stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }

        let lock = makeSubmitLock(
            request: request,
            catalogRows: fixture.catalogRows,
            selectedHandle: fixture.selectedHandle,
        )
        let streamingLock = await receiveCancelStreamingDelta(
            on: fixture.store,
            stream: fixture.stream,
            request: request,
            lock: lock,
            fixedMs: fixture.fixedMs,
        )
        await sendCancelAndLateTerminalEvents(
            on: fixture.store,
            request: request,
            streamingLock: streamingLock,
            fixedMs: fixture.fixedMs,
        )
        assertCancelResult(fixture.store.state, streamingLock: streamingLock, fixedMs: fixture.fixedMs)
        await fixture.store.finish()
    }

    // MARK: - CBW-001-regenerate_chat_response

    /// CBW-001-regenerate_chat_response: 기존 assistant 응답을 새 응답으로 교체하고 user turn은 중복하지 않는다.
    /// regenerate 요청이 마지막 assistant turn을 replacement target으로 고정하고 원래 user prompt만 provider에 전달하는지 검증합니다.
    /// - 검증 내용: regenerate request messages, assistantReplacementIndex, final transcript, persistence snapshot을 확인합니다.
    /// - 사전 조건: transcript에는 user 한 개와 기존 assistant 답변 한 개가 있습니다.
    /// - 기대 결과: provider 요청은 user turn만 포함하고 최종 transcript는 새 assistant 답변으로 교체됩니다.
    func testRegenerateChatResponseReplacesAssistantWithoutDuplicatingUserTurn() async {
        let persistence = AiChatSessionPersistenceSpy()
        let fixture = makeStreamFixture(
            draftText: "",
            fixedMs: 1_700_000_000_300,
            transcriptHistory: regenerationTranscript,
            persistence: persistence,
        )
        applyObservationFocusedExhaustivity(to: fixture.store)

        await fixture.store.send(.regenerateTapped)
        await resolvePendingRequestContext(fixture.store) { state in
            self.applyRegenerateStartedState(&state, selectedHandle: fixture.selectedHandle)
        }
        guard let request = fixture.stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }

        let lock = makeRegenerateLock(
            request: request,
            catalogRows: fixture.catalogRows,
            selectedHandle: fixture.selectedHandle,
        )
        assertRegenerateRequest(request, store: fixture.store, lock: lock)
        await receiveRegenerateFinal(
            on: fixture.store,
            stream: fixture.stream,
            request: request,
            lock: lock,
            fixedMs: fixture.fixedMs,
        )
        await fixture.store.finish()
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory, regeneratedTranscript)
    }

    // MARK: - CBW-001-open_contextual_chat

    /// CBW-001-open_contextual_chat: current context summary fixture가 진입 표면 계약과 일치한다.
    /// context summary가 selection 유무에 따라 title/detail을 안정적으로 구성하는지 검증합니다.
    /// - 검증 내용: selected entries, location only, empty context의 summary title/detail을 확인합니다.
    /// - 사전 조건: provider는 연결되어 있고 current context fixture만 서로 다르게 주입됩니다.
    /// - 기대 결과: summary display는 inspector와 동일한 텍스트 계약을 유지합니다.
    func testOpenContextualChatUsesCurrentContextSummaryFixturesThatMatchInspectorContract() {
        let selectedHandle = makeCatalogRows()[0].handle

        let selectedEntriesState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(
                summary: "Documents · 2 selected",
                references: [],
                items: [],
                attachments: [],
            ),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(selectedEntriesState.currentContextSummaryDisplayModel.title, "Documents · 2 selected")
        XCTAssertNil(selectedEntriesState.currentContextSummaryDisplayModel.detail)

        let locationOnlyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(locationOnlyState.currentContextSummaryDisplayModel.title, "Documents")
        XCTAssertNil(locationOnlyState.currentContextSummaryDisplayModel.detail)

        let emptyContextState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(emptyContextState.currentContextSummaryDisplayModel.title, "No current selection")
        XCTAssertNil(emptyContextState.currentContextSummaryDisplayModel.detail)
    }

    /// CBW-001-open_contextual_chat: provider unavailable 상태는 고정 배너와 비활성 composer로 노출된다.
    /// 모델이 전혀 없는 진입 상태에서 사용자가 submit할 수 없고 빈 모델 라벨을 보는지 검증합니다.
    /// - 검증 내용: connectionState, canSubmit, modelLabel, empty surface summary를 확인합니다.
    /// - 사전 조건: current context는 존재하지만 catalogRows와 selectedModelHandle은 비어 있습니다.
    /// - 기대 결과: provider unavailable banner와 No models available composer label이 유지됩니다.
    func testOpenContextualChatShowsProviderUnavailableSurfaceAndEmptyComposerModelLabel() {
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        XCTAssertEqual(state.connectionState, .connected)
        XCTAssertFalse(state.canSubmit)
        XCTAssertEqual(state.chatInputDisplayModel.modelLabel, "No models available")
        XCTAssertEqual(state.chatInputDisplayModel.effortLabel, "No models available")

        if case let .empty(summary, selectedModel) = state.surfaceState {
            XCTAssertNil(selectedModel)
            XCTAssertEqual(summary.title, "Documents")
        } else {
            XCTFail("Expected empty surface with no loaded models")
        }
    }

    /// CBW-001-open_contextual_chat: 연결되지 않은 provider CTA는 AI Settings 열기로 위임된다.
    /// 빈 provider 상태에서 사용자가 fix action을 눌렀을 때 delegate 이벤트가 올바르게 발생하는지 검증합니다.
    /// - 검증 내용: openSettingsTapped 이후 delegate(.openAISettings)와 connectionState를 확인합니다.
    /// - 사전 조건: active session은 존재하지만 providerConnectionSnapshot은 빈 known 상태입니다.
    /// - 기대 결과: 표면은 그대로 유지되고 Settings 열기 delegate만 방출됩니다.
    func testOpenContextualChatDelegatesOpenAISettingsForNoProviderCTA() async {
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            providerConnectionSnapshot: .known([]),
        )) {
            AiChatFeature()
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.openSettingsTapped)
        await store.receive(.delegate(.openAISettings))

        XCTAssertEqual(
            store.state.connectionState,
            .unconnected(.init(
                title: "Connect an AI provider",
                detail: "Set up a provider in Settings to chat with this context.",
                fixLabel: "Open Settings",
            )),
        )
    }

    // MARK: - CBW-001-submit_chat_request

    /// CBW-001-submit_chat_request: 선택 모델이 현재 loaded catalog에 없으면 submit은 시작되지 않는다.
    /// stale selectedModelHandle이 남아 있어도 잘못된 실행 요청이 만들어지지 않는지 검증합니다.
    /// - 검증 내용: canSubmit, execution request count, executionPhase, draftText 보존을 확인합니다.
    /// - 사전 조건: selectedModelHandle은 존재하지만 loaded model list와 catalogRows가 서로 불일치합니다.
    /// - 기대 결과: submitTapped는 no-op이고 request는 한 건도 생성되지 않습니다.
    func testSubmitChatRequestDoesNotStartWhenSelectedModelIsMissingFromLoadedCatalog() async {
        final class RequestSpy: @unchecked Sendable {
            private(set) var requests: [AiChatRequest] = []

            func append(_ request: AiChatRequest) {
                requests.append(request)
            }
        }

        let spy = RequestSpy()
        let catalogRows = makeCatalogRows()
        let loadedModels = [makeThinkingCapableProviderModels()[1]]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("dddddddd-dddd-dddd-dddd-dddddddddddd")),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [catalogRows[1]],
            modelListState: .loaded(loadedModels),
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                spy.append(request)
                return AsyncStream { continuation in
                    continuation.finish()
                }
            })
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.submitTapped)

        XCTAssertTrue(spy.requests.isEmpty)
        XCTAssertEqual(store.state.draftText, "Hello")
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
    }

    /// CBW-001-submit_chat_request: canSubmit이 false면 submitTapped는 no-op이다.
    /// provider/model 미선택 상태에서 submit 액션이 side effect를 만들지 않는지 검증합니다.
    /// - 검증 내용: execution request count, draftText, executionPhase, lockedModelHandle을 확인합니다.
    /// - 사전 조건: current context는 있으나 catalogRows와 selectedModelHandle이 비어 있어 canSubmit이 false입니다.
    /// - 기대 결과: submitTapped 이후에도 상태 변화 없이 기존 draft가 유지됩니다.
    func testSubmitChatRequestIsNoOpWhenCanSubmitIsFalse() async {
        final class ExecutionRequestSpy: @unchecked Sendable {
            private(set) var requests: [AiChatRequest] = []

            func append(_ request: AiChatRequest) {
                requests.append(request)
            }
        }

        let requestSpy = ExecutionRequestSpy()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                requestSpy.append(request)
                return AsyncStream { continuation in
                    continuation.finish()
                }
            })
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.submitTapped)

        XCTAssertTrue(requestSpy.requests.isEmpty)
        XCTAssertEqual(store.state.draftText, "Hello")
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
        await store.finish()
    }

    /// CBW-001-submit_chat_request: 두 번째 submit은 이전 assistant turn을 포함한 contiguous history를 전달한다.
    /// 한 번 완료된 assistant 응답 이후 후속 질문을 보낼 때 provider request history가 누락 없이 이어지는지 검증합니다.
    /// - 검증 내용: 첫 번째 final 이후 두 번째 request.messages와 transcriptHistory 누적을 확인합니다.
    /// - 사전 조건: 동일 session에서 첫 요청이 완료된 뒤 두 번째 user draft를 입력합니다.
    /// - 기대 결과: 두 번째 provider request는 user-assistant-user 순서의 history를 포함합니다.
    func testSubmitChatRequestIncludesPreviousAssistantTurnInSecondExecutionRequest() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111121"))
        let fixedMs: Int64 = 1_700_000_000_260

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = selectedHandle
            state.streamingAssistantDraft = nil
        }

        guard let firstRequest = stream.requests.first else {
            XCTFail("Expected first execution request")
            return
        }
        stream.yield(.final(response: AiChatResponse(
            context: firstRequest.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "First answer"),
            completedAtMs: fixedMs,
        )))
        await store.receive(.executionEvent(.final(response: AiChatResponse(
            context: firstRequest.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "First answer"),
            completedAtMs: fixedMs,
        )))) { state in
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello", createdAtMs: fixedMs),
                AiChatMessage(role: .assistant, content: "First answer", createdAtMs: fixedMs),
            ]
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
        }

        await store.send(.draftTextChanged("Second question")) { state in
            state.draftText = "Second question"
        }
        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = selectedHandle
            state.streamingAssistantDraft = nil
        }

        XCTAssertEqual(stream.requests.count, 2)
        XCTAssertEqual(stream.requests[1].messages, [
            AiChatMessage(role: .user, content: "Hello", createdAtMs: fixedMs),
            AiChatMessage(role: .assistant, content: "First answer", createdAtMs: fixedMs),
            AiChatMessage(role: .user, content: "Second question", createdAtMs: fixedMs),
        ])

        stream.finish()
        stream.finish(at: 1)
        await store.finish()
    }

    /// CBW-001-submit_chat_request: oversized recent turn은 contiguous context를 지키기 위해 잘린다.
    /// history budget을 초과한 turn이 있어도 가장 최신 연속 대화만 provider request에 포함되는지 검증합니다.
    /// - 검증 내용: request.messages, historyTruncation included/excluded count와 truncationReason을 확인합니다.
    /// - 사전 조건: transcript에는 oversized recent turn과 latest turn이 함께 존재하고 draft가 추가됩니다.
    /// - 기대 결과: request는 latest contiguous turn과 current draft만 포함하고 truncation metadata가 기록됩니다.
    func testSubmitChatRequestTruncatesHistoryAtOversizedRecentTurnToKeepContiguousContext() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let fixedMs: Int64 = 1_700_000_001_000
        let olderUser = String(repeating: "o", count: 500)
        let olderAssistant = String(repeating: "p", count: 500)
        let oversizedRecentUser = String(repeating: "x", count: 11000)
        let oversizedRecentAssistant = String(repeating: "y", count: 11000)
        let latestUser = String(repeating: "u", count: 1700)
        let latestAssistant = String(repeating: "a", count: 1800)
        let draft = "Current prompt"

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111119")),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: olderUser),
                AiChatMessage(role: .assistant, content: olderAssistant),
                AiChatMessage(role: .user, content: oversizedRecentUser),
                AiChatMessage(role: .assistant, content: oversizedRecentAssistant),
                AiChatMessage(role: .user, content: latestUser),
                AiChatMessage(role: .assistant, content: latestAssistant),
            ],
            draftText: draft,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = catalogRows[0].handle
        }

        guard let request = stream.requests.first,
              case let .processing(lock) = store.state.executionPhase
        else {
            return XCTFail("Expected frozen request lock")
        }

        XCTAssertEqual(request.messages, [
            AiChatMessage(role: .user, content: latestUser),
            AiChatMessage(role: .assistant, content: latestAssistant),
            AiChatMessage(role: .user, content: draft, createdAtMs: fixedMs),
        ])
        XCTAssertEqual(lock.persistenceTranscriptHistory, [
            AiChatMessage(role: .user, content: olderUser),
            AiChatMessage(role: .assistant, content: olderAssistant),
            AiChatMessage(role: .user, content: oversizedRecentUser),
            AiChatMessage(role: .assistant, content: oversizedRecentAssistant),
            AiChatMessage(role: .user, content: latestUser),
            AiChatMessage(role: .assistant, content: latestAssistant),
            AiChatMessage(role: .user, content: draft, createdAtMs: fixedMs),
        ])
        XCTAssertFalse(request.messages.contains(AiChatMessage(role: .user, content: olderUser)))
        XCTAssertFalse(request.messages.contains(AiChatMessage(role: .assistant, content: olderAssistant)))
        XCTAssertEqual(lock.historyTruncation.includedMessageCount, 3)
        XCTAssertEqual(lock.historyTruncation.excludedMessageCount, 4)
        XCTAssertEqual(lock.historyTruncation.truncationReason, .characterBudgetExceeded)
        XCTAssertEqual(request.messages.last?.createdAtMs, fixedMs)
        XCTAssertEqual(lock.persistenceTranscriptHistory.last?.createdAtMs, fixedMs)
        XCTAssertEqual(store.state.transcriptHistory.last?.createdAtMs, fixedMs)
        XCTAssertNil(request.messages.dropLast().last?.createdAtMs)
        XCTAssertNil(lock.persistenceTranscriptHistory.dropLast().last?.createdAtMs)
    }

    /// CBW-001-submit_chat_request: 마지막 user invariant가 없으면 다른 role에 submit timestamp를 기록하지 않는다.
    /// 잘못 준비된 request가 assistant/system message를 user turn으로 위장하지 않는 경계를 검증합니다.
    /// - 검증 내용: execution/persistence 배열의 마지막 role과 기존 timestamp가 request lock 생성 후에도 유지되는지 확인합니다.
    /// - 사전 조건: execution은 assistant, persistence는 system message로 끝나는 malformed prepared request입니다.
    /// - 기대 결과: 두 non-user message는 submitted timestamp로 교체되지 않고 기존 timestamp를 보존합니다.
    func testSubmitChatRequestDoesNotStampNonUserWhenExpectedFinalUserIsMissing() async {
        let fixture = makeMalformedFinalUserFixture()
        applyObservationFocusedExhaustivity(to: fixture.store)

        await fixture.store.send(.requestContextResolved(
            fixture.resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        guard let request = fixture.stream.requests.first,
              case let .processing(lock) = fixture.store.state.executionPhase
        else {
            return XCTFail("Expected malformed request to reach request lock boundary")
        }
        XCTAssertEqual(request.messages, fixture.executionMessages)
        XCTAssertEqual(lock.persistenceTranscriptHistory, fixture.persistenceMessages)
        XCTAssertTrue(fixture.store.state.transcriptHistory.isEmpty)
        fixture.stream.finish()
        await fixture.store.finish()
    }

    /// CBW-001-submit_chat_request: submit 시점의 context timing과 truncation 계산은 요청 동안 고정된다.
    /// 사용자가 제출 후 thinking 선택을 바꾸더라도 실제 request context와 observability summary는 흔들리지 않는지 검증합니다.
    /// - 검증 내용: frozen currentContext, selectedThinking, submittedAtMs, request.messages, historyTruncation을 확인합니다.
    /// - 사전 조건: 긴 transcript, medium thinking, deterministic clock이 설정된 상태에서 submit을 시작합니다.
    /// - 기대 결과: request는 submit 시점 값으로 고정되고 이후 UI 변경은 in-flight request에 영향을 주지 않습니다.
    func testSubmitChatRequestFreezesContextTimingAndDeterministicHistoryTruncation() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let fixedMs: Int64 = 1_700_000_000_800
        let frozenContext = makeContextSnapshot(summary: "Before submit")
        let largeUser1 = String(repeating: "u", count: 9000)
        let largeAssistant1 = String(repeating: "a", count: 9000)
        let largeUser2 = String(repeating: "x", count: 9000)
        let largeAssistant2 = String(repeating: "y", count: 9000)
        let draft = "Current prompt"

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111117")),
            sessionStatus: .active,
            currentContext: frozenContext,
            transcriptHistory: [
                AiChatMessage(role: .user, content: largeUser1),
                AiChatMessage(role: .assistant, content: largeAssistant1),
                AiChatMessage(role: .user, content: largeUser2),
                AiChatMessage(role: .assistant, content: largeAssistant2),
            ],
            draftText: draft,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = catalogRows[0].handle
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first,
              case let .processing(lock) = store.state.executionPhase
        else {
            return XCTFail("Expected frozen request lock")
        }

        XCTAssertEqual(request.context.currentContext, frozenContext)
        XCTAssertEqual(request.context.selectedThinking, .effort(.medium))
        XCTAssertEqual(request.context.submittedAtMs, fixedMs)
        XCTAssertEqual(request.messages, [
            AiChatMessage(role: .user, content: largeUser2),
            AiChatMessage(role: .assistant, content: largeAssistant2),
            AiChatMessage(role: .user, content: draft, createdAtMs: fixedMs),
        ])
        XCTAssertEqual(lock.persistenceTranscriptHistory, [
            AiChatMessage(role: .user, content: largeUser1),
            AiChatMessage(role: .assistant, content: largeAssistant1),
            AiChatMessage(role: .user, content: largeUser2),
            AiChatMessage(role: .assistant, content: largeAssistant2),
            AiChatMessage(role: .user, content: draft, createdAtMs: fixedMs),
        ])
        XCTAssertEqual(lock.historyTruncation.includedMessageCount, 3)
        XCTAssertEqual(lock.historyTruncation.excludedMessageCount, 2)
        XCTAssertEqual(lock.historyTruncation.budget, 24000)
        XCTAssertEqual(lock.historyTruncation.truncationReason, .characterBudgetExceeded)
        XCTAssertEqual(lock.observabilitySummary.submittedAtMs, fixedMs)

        await store.send(.selectedThinkingChanged(.effort(.high))) { state in
            state.selectedThinking = .effort(.high)
        }
        XCTAssertEqual(request.context.currentContext.summary, "Before submit")
        XCTAssertEqual(request.context.selectedThinking, .effort(.medium))
    }

    /// CBW-001-submit_chat_request: 빈 context에서도 deterministic submitted timestamp로 요청이 준비된다.
    /// current context가 비어 있어도 실행 request 자체는 안정적으로 준비되는지 검증합니다.
    /// - 검증 내용: request.context.currentContext, submittedAtMs, request.messages를 확인합니다.
    /// - 사전 조건: empty current context와 non-empty draft를 가진 active session입니다.
    /// - 기대 결과: request는 empty context snapshot과 단일 user message로 생성됩니다.
    func testSubmitChatRequestPreparesEmptyContextWithDeterministicSubmittedTimestamp() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let fixedMs: Int64 = 1_700_000_000_900
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111118")),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "Hello empty context",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = catalogRows[0].handle
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
            return XCTFail("Expected request for empty context")
        }

        XCTAssertEqual(request.context.currentContext, .init())
        XCTAssertEqual(request.context.submittedAtMs, fixedMs)
        XCTAssertEqual(request.messages, [
            AiChatMessage(role: .user, content: "Hello empty context", createdAtMs: fixedMs),
        ])
    }

    // MARK: - CBW-001-show_request_processing_state

    /// CBW-001-show_request_processing_state: empty/ready/processing/error surface는 실행 단계에 맞춰 전환된다.
    /// request 전후와 terminal failure에서 message area와 skeleton surface가 각각 어떤 상태를 노출하는지 검증합니다.
    /// - 검증 내용: surfaceState, skeletonSurfaceDisplayModel, chatInputDisplayModel, canSubmit을 확인합니다.
    /// - 사전 조건: 동일 spec에서 empty, current-context draft, ready, processing, disconnected, failed state를 각각 구성합니다.
    /// - 기대 결과: 각 상태는 user-visible surface contract를 유지하며 processing 중 stop affordance를 노출합니다.
    func testShowRequestProcessingStateCoversEmptyReadyProcessingAndErrorSurfaces() {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let selectedHandle = catalogRows[0].handle

        let emptyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        if case let .empty(summaryDisplay, selectedModel) = emptyState.surfaceState {
            XCTAssertTrue(summaryDisplay.isEmpty)
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected empty surface state")
        }
        if case let .empty(emptyDisplay) = emptyState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(emptyDisplay.title, "Ask about this context")
            XCTAssertEqual(emptyDisplay.detail, "Send a message to start a contextual chat.")
        } else {
            XCTFail("Expected skeleton empty surface state")
        }

        let currentContextInitialState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "What changed?",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        if case let .empty(summaryDisplay, selectedModel) = currentContextInitialState.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(summaryDisplay.title, "Four files selected")
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected current-context draft to keep empty surface state")
        }
        XCTAssertTrue(currentContextInitialState.canSubmit)
        XCTAssertEqual(currentContextInitialState.chatInputDisplayModel.placeholder, "Ask anything…")
        XCTAssertEqual(currentContextInitialState.chatInputDisplayModel.modelLabel, "GPT-4.1 Mini")
        XCTAssertEqual(currentContextInitialState.chatInputDisplayModel.effortLabel, "Thinking unavailable")
        XCTAssertTrue(currentContextInitialState.chatInputDisplayModel.canSubmit)
        XCTAssertTrue(currentContextInitialState.chatInputDisplayModel.isSubmitVisible)
        XCTAssertFalse(currentContextInitialState.chatInputDisplayModel.isStopVisible)
        XCTAssertNil(currentContextInitialState.modelCatalogState.rows.first?.providerBadge)

        let readyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        if case let .ready(summaryDisplay, selectedModel) = readyState.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected ready surface state")
        }
        if case .ready = readyState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected ready skeleton surface state")
        }

        let processingSessionID = AiChatSessionID(rawValue: UUID())
        let processingState = AiChatFeature.State(
            sessionID: processingSessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: processingSessionID,
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: catalogRows[1].handle,
                        selectedRow: catalogRows[1],
                    ),
                    messages: [],
                ),
                selectedHandle: catalogRows[1].handle,
                selectedRow: catalogRows[1],
                assistantReplacementIndex: nil,
            )),
        )

        if case let .processing(processing, _, selectedModel) = processingState.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertEqual(processing.lockedModel.title, "Claude Sonnet 4")
            XCTAssertEqual(processing.cancelAffordance.title, "Cancel request")
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected processing surface state")
        }
        if case let .processing(processing) = processingState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
        } else {
            XCTFail("Expected processing skeleton surface state")
        }
        XCTAssertFalse(processingState.canSubmit)
        XCTAssertTrue(processingState.chatInputDisplayModel.isStopVisible)
        XCTAssertFalse(processingState.chatInputDisplayModel.isSubmitVisible)
        XCTAssertTrue(processingState.chatInputDisplayModel.canStop)

        let refreshedProcessingState = AiChatFeature.State(
            sessionID: processingState.sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: processingState.transcriptHistory,
            draftText: processingState.draftText,
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
            executionPhase: processingState.executionPhase,
        )

        if case let .processing(processing, _, selectedModel) = refreshedProcessingState.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertNil(selectedModel)
        } else {
            XCTFail("Expected processing surface state to survive model refresh")
        }
        XCTAssertTrue(refreshedProcessingState.isProcessing)
        XCTAssertEqual(refreshedProcessingState.chatInputDisplayModel.modelLabel, "No models available")
        XCTAssertTrue(refreshedProcessingState.chatInputDisplayModel.isStopVisible)
        XCTAssertTrue(refreshedProcessingState.chatInputDisplayModel.canStop)

        let errorSessionID = AiChatSessionID(rawValue: UUID())
        let errorState = AiChatFeature.State(
            sessionID: errorSessionID,
            sessionStatus: .failed,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: errorSessionID,
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: selectedHandle,
                        selectedRow: catalogRows[0],
                    ),
                    messages: [],
                ),
                selectedHandle: selectedHandle,
                selectedRow: catalogRows[0],
                assistantReplacementIndex: nil,
            ), .transportError),
        )

        if case let .ready(_, selectedModel) = errorState.surfaceState {
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected terminal failure to remain in message-area ready surface")
        }
        if case .ready = errorState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected terminal failure skeleton to remain in ready surface")
        }
        XCTAssertEqual(errorState.requestStatusText, "The chat service response could not be read.")
    }

    /// CBW-001-show_request_processing_state: completed session은 provider 연결이 끊겨도 ready surface를 유지한다.
    /// terminal completion 이후 모델 선택만 unavailable이 되었을 때 transcript 표면이 오류 상태로 후퇴하지 않는지 검증합니다.
    /// - 검증 내용: ready surface, skeleton ready, selectedModel nil, canSubmit false를 확인합니다.
    /// - 사전 조건: completed execution lock은 존재하지만 catalogRows는 비어 있습니다.
    /// - 기대 결과: message area는 ready 상태를 유지하고 composer만 submit 불가로 남습니다.
    func testShowRequestProcessingStateKeepsCompletedSessionReadyWhenProviderBecomesDisconnected() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: AiChatSessionID(rawValue: UUID()),
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let disconnectedState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Hi"),
            ],
            draftText: "Follow up",
            catalogRows: [],
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .completed(lock),
        )

        if case let .ready(summary, selectedModel) = disconnectedState.surfaceState {
            XCTAssertFalse(summary.isEmpty)
            XCTAssertNil(selectedModel)
        } else {
            XCTFail("Expected completed session to remain ready while model selection is unavailable")
        }
        if case .ready = disconnectedState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected skeleton surface to remain ready after request completion")
        }
        XCTAssertFalse(disconnectedState.canSubmit)
        XCTAssertFalse(disconnectedState.chatInputDisplayModel.canSubmit)
    }

    /// CBW-001-show_request_processing_state: legacy sessionStatus error는 restore flow가 없으면 terminal surface를 오염시키지
    /// 않는다.
    /// 완료된 request가 있는 session에서 오래된 failed status만으로 에러 표면이 다시 나타나지 않는지 검증합니다.
    /// - 검증 내용: ready surface, skeleton ready, canSubmit true, sessionStatusText nil을 확인합니다.
    /// - 사전 조건: executionPhase는 completed이고 sessionStatus만 failed로 설정됩니다.
    /// - 기대 결과: terminal surface는 ready 상태를 유지하고 restore 전용 상태 문구는 노출되지 않습니다.
    func testShowRequestProcessingStateIgnoresLegacySessionStatusErrorWithoutRestoreFlow() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: makeRequestContext(
                    sessionID: AiChatSessionID(rawValue: UUID()),
                    requestID: AiChatRequestID(rawValue: UUID()),
                    runID: AiChatRunID(rawValue: UUID()),
                    model: selectedHandle,
                    selectedRow: catalogRows[0],
                ),
                messages: [],
            ),
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let failedSessionState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .failed,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Follow up",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .completed(lock),
        )

        if case let .ready(summary, selectedModel) = failedSessionState.surfaceState {
            XCTAssertFalse(summary.isEmpty)
            XCTAssertEqual(selectedModel?.handle, selectedHandle)
        } else {
            XCTFail("Expected terminal surface to remain ready when restore flow is disabled")
        }
        if case .ready = failedSessionState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected skeleton surface to remain ready when restore flow is disabled")
        }
        XCTAssertTrue(failedSessionState.canSubmit)
        XCTAssertNil(failedSessionState.sessionStatusText)
    }

    /// CBW-001-show_request_processing_state: persistence recovery는 execution failure를 error surface로 노출한다.
    /// final 응답은 확보됐지만 session persistence가 실패한 경우 retry affordance가 사용자에게 드러나는지 검증합니다.
    /// - 검증 내용: surfaceState.error, skeleton error, requestStatusText, canSubmit false를 확인합니다.
    /// - 사전 조건: transcript는 존재하고 executionPhase는 persistenceRecovery(.unknown)입니다.
    /// - 기대 결과: surface는 Chat unavailable과 Retry affordance를 노출합니다.
    func testShowRequestProcessingStateReflectsPersistenceRecoveryFailureOnSurface() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: makeRequestContext(
                    sessionID: AiChatSessionID(rawValue: UUID()),
                    requestID: AiChatRequestID(rawValue: UUID()),
                    runID: AiChatRunID(rawValue: UUID()),
                    model: selectedHandle,
                    selectedRow: catalogRows[0],
                ),
                messages: [],
            ),
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let recoveryState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .assistant, content: "Recovered locally")],
            draftText: "Follow up",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(lock, .unknown),
        )

        if case let .error(connection, summary) = recoveryState.surfaceState {
            XCTAssertEqual(connection.title, "Chat unavailable")
            XCTAssertEqual(connection.detail, "An unknown chat error occurred.")
            XCTAssertFalse(summary.isEmpty)
        } else {
            XCTFail("Expected persistence recovery to surface execution error")
        }
        if case let .error(connection) = recoveryState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(connection.fixLabel, "Retry")
        } else {
            XCTFail("Expected skeleton surface to expose persistence recovery error")
        }
        XCTAssertEqual(recoveryState.requestStatusText, "Finalized locally; An unknown chat error occurred.")
        XCTAssertFalse(recoveryState.canSubmit)
    }

    // MARK: - CBW-001-recover_failed_chat_request

    /// CBW-001-recover_failed_chat_request: connections file load 실패는 provider 실행 없이 unknown failure로 전환된다.
    /// credential 조회가 실패한 경우 provider client가 호출되지 않고 terminal failure만 남는지 검증합니다.
    /// - 검증 내용: provider request count, failed executionPhase, lastExecutionFailure, requestStatusText를 확인합니다.
    /// - 사전 조건: submit 가능한 상태이지만 aiConnectionsFileClient.load가 unreadable error를 던집니다.
    /// - 기대 결과: provider execution은 0회이며 UI는 unknown failure recovery 상태로 전환됩니다.
    func testRecoverFailedChatRequestEmitsUnknownFailureWhenConnectionsFileLoadFails() async {
        actor ProviderDriver {
            var requestCount = 0

            func increment() {
                requestCount += 1
            }

            func snapshot() -> Int {
                requestCount
            }
        }

        enum LoadFailure: Error {
            case unreadable
        }

        let driver = ProviderDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111122"))
        let fixedMs: Int64 = 1_700_000_000_700
        let providerClient = AiChatProviderExecutionClient(execute: { request, _ in
            AsyncThrowingStream { continuation in
                Task {
                    await driver.increment()
                    continuation.yield(.started(context: request.context))
                    continuation.finish()
                }
            }
        })

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = .live(providerExecutionClient: providerClient)
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { throw LoadFailure.unreadable },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.selectedModelHandle = selectedHandle
            state.lockedModelHandle = selectedHandle
            state.lastExecutionFailure = nil
            state.streamingAssistantDraft = nil
        }

        guard case let .processing(lock) = store.state.executionPhase else {
            XCTFail("Expected processing state after submit")
            return
        }

        let failedLock = lock.recordingTerminal(at: fixedMs, failure: .unknown, wasCancelled: false)
        await store.receive(.executionEvent(.failed(context: lock.request.context, reason: .unknown))) { state in
            state.lockedModelHandle = nil
            state.lastExecutionFailure = .unknown
            state.executionPhase = .failed(failedLock, .unknown)
        }

        let requestCount = await driver.snapshot()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(store.state.requestStatusText, "An unknown chat error occurred.")
    }

    /// CBW-001-recover_failed_chat_request: failure surface가 남아 있으면 submit 재시도는 차단된다.
    /// stale failure banner가 존재하는 동안 사용자가 바로 submit을 다시 누르지 못하는지 검증합니다.
    /// - 검증 내용: canSubmit이 false인지 확인합니다.
    /// - 사전 조건: active session, non-empty draft, transportError failure가 idle phase 위에 남아 있습니다.
    /// - 기대 결과: composer는 retry surface를 지우기 전까지 submit 불가 상태를 유지합니다.
    func testRecoverFailedChatRequestDisallowsSubmitWhileFailureSurfaceExists() {
        let catalogRows = makeCatalogRows()
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Retry after failure",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: .transportError,
            executionPhase: .idle,
        )
        let store = TestStore(initialState: state) {
            AiChatFeature()
        }
        XCTAssertFalse(store.state.canSubmit)
    }

    /// CBW-001-recover_failed_chat_request: draft 수정과 reset은 stale failure surface를 제거한다.
    /// 사용자가 새 prompt를 입력하거나 reset을 눌렀을 때 이전 transport failure가 더 이상 composer를 막지 않는지 검증합니다.
    /// - 검증 내용: draftTextChanged 후 canSubmit 복구와 reset 후 transcript/lock/failure 초기화를 확인합니다.
    /// - 사전 조건: failed execution lock과 stale draft, transcript가 존재합니다.
    /// - 기대 결과: 새 입력은 failure를 지우고 reset은 대화 상태를 완전히 초기화합니다.
    func testRecoverFailedChatRequestClearsStaleFailureOnDraftChangeAndReset() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: selectedHandle,
                        selectedRow: catalogRows[0],
                    ),
                    messages: [],
                ),
                selectedHandle: selectedHandle,
                selectedRow: catalogRows[0],
                assistantReplacementIndex: nil,
            ), .transportError),
        )) {
            AiChatFeature()
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.draftTextChanged("Updated")) { state in
            state.draftText = "Updated"
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertTrue(store.state.canSubmit)

        await store.send(.resetTapped) { state in
            state.draftText = ""
            state.transcriptHistory = []
            state.lastExecutionFailure = nil
            state.lockedModelHandle = nil
            state.executionPhase = .idle
        }

        await store.finish()
    }

    /// CBW-001-recover_failed_chat_request: 모델 변경은 stale failure를 지우고 submit 가능 상태를 복원한다.
    /// 사용자가 다른 모델을 고르면 이전 failure surface가 즉시 내려가고 재시도 가능해지는지 검증합니다.
    /// - 검증 내용: selectedModelHandle 변경, lastExecutionFailure 초기화, executionPhase idle 복귀를 확인합니다.
    /// - 사전 조건: firstHandle로 실패한 뒤 secondHandle이 같은 catalog에 존재합니다.
    /// - 기대 결과: 새 모델 선택 후 canSubmit은 true가 됩니다.
    func testRecoverFailedChatRequestClearsStaleFailureWhenModelChanges() async {
        let catalogRows = makeCatalogRows()
        let firstHandle = catalogRows[0].handle
        let secondHandle = catalogRows[1].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Retry me",
            catalogRows: catalogRows,
            selectedModelHandle: firstHandle,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: firstHandle,
                        selectedRow: catalogRows[0],
                    ),
                    messages: [],
                ),
                selectedHandle: firstHandle,
                selectedRow: catalogRows[0],
                assistantReplacementIndex: nil,
            ), .transportError),
        )) {
            AiChatFeature()
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.selectedModelChanged(secondHandle)) { state in
            state.selectedModelHandle = secondHandle
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertTrue(store.state.canSubmit)
        await store.finish()
    }

    // MARK: - CBW-001-retry_failed_chat_request

    /// CBW-001-retry_failed_chat_request: authentication failure는 같은 user prompt로 retry를 시작한다.
    /// authentication terminal failure 이후 recovery tap이 regenerate flow로 재실행되는지 검증합니다.
    /// - 검증 내용: retry request messages, processing lock, locked model, failure cleanup을 확인합니다.
    /// - 사전 조건: active session에서 첫 submit이 authentication failure로 종료됩니다.
    /// - 기대 결과: errorRecoveryTapped는 동일 prompt의 새 request를 만들고 lastExecutionFailure를 제거합니다.
    func testRetryFailedChatRequestSupportsAuthenticationRecovery() async {
        await assertFailureRecovery(reason: .authentication, sessionIDRaw: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    }

    /// CBW-001-retry_failed_chat_request: model unavailable failure는 같은 user prompt로 retry를 시작한다.
    /// 모델 가용성 오류 이후 recovery tap이 사용자 입력을 보존한 채 재실행되는지 검증합니다.
    /// - 검증 내용: retry request messages, processing lock, locked model, failure cleanup을 확인합니다.
    /// - 사전 조건: active session에서 첫 submit이 modelUnavailable failure로 종료됩니다.
    /// - 기대 결과: errorRecoveryTapped는 동일 prompt의 새 request를 만들고 recovery surface를 닫습니다.
    func testRetryFailedChatRequestSupportsModelUnavailableRecovery() async {
        await assertFailureRecovery(reason: .modelUnavailable, sessionIDRaw: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    }

    /// CBW-001-retry_failed_chat_request: network failure는 같은 user prompt로 retry를 시작한다.
    /// 네트워크 terminal failure 이후 recovery tap이 재시도 경로를 정상적으로 여는지 검증합니다.
    /// - 검증 내용: retry request messages, processing lock, locked model, failure cleanup을 확인합니다.
    /// - 사전 조건: active session에서 첫 submit이 network failure로 종료됩니다.
    /// - 기대 결과: errorRecoveryTapped는 동일 prompt의 새 request를 만들고 processing 상태로 복귀합니다.
    func testRetryFailedChatRequestSupportsNetworkRecovery() async {
        await assertFailureRecovery(reason: .network, sessionIDRaw: "cccccccc-cccc-cccc-cccc-cccccccccccc")
    }

    // MARK: - CBW-001-recover_persisted_chat_state

    /// CBW-001-recover_persisted_chat_state: final transcript persistence 실패는 recovery state를 만든다.
    /// assistant final까지는 성공했지만 snapshot 저장이 실패한 경우 로컬 finalized 상태와 recovery 배너가 남는지 검증합니다.
    /// - 검증 내용: executionEvent.final 이후 persistenceFailed, transcript 보존, requestStatusText를 확인합니다.
    /// - 사전 조건: saveSession dependency는 항상 throw하고 provider stream은 final response를 반환합니다.
    /// - 기대 결과: executionPhase는 persistenceRecovery로 전환되고 transcript는 손실되지 않습니다.
    func testRecoverPersistedChatStateCreatesRecoveryStateWhenPersistenceFails() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111114"))
        let fixedMs: Int64 = 1_700_000_000_400

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in
                    struct PersistenceBoom: Error {}
                    throw PersistenceBoom()
                },
                deleteSession: { _ in },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = selectedHandle
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hi"),
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        let finalizedLock = lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        let expectedFinalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello", createdAtMs: fixedMs),
                AiChatMessage(role: .assistant, content: "Hi", createdAtMs: fixedMs),
            ],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let finalizedLockWithSnapshot = finalizedLock.recordingFinalSnapshot(expectedFinalSnapshot)
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = expectedFinalSnapshot.transcriptHistory
            state.lockedModelHandle = nil
            state.executionPhase = .completed(finalizedLock)
        }

        await store.receive(.persistenceFailed(finalizedLockWithSnapshot, .unknown)) { state in
            state.lastExecutionFailure = .unknown
            state.executionPhase = .persistenceRecovery(finalizedLock, .unknown)
        }

        XCTAssertEqual(store.state.transcriptHistory, [
            AiChatMessage(role: .user, content: "Hello", createdAtMs: fixedMs),
            AiChatMessage(role: .assistant, content: "Hi", createdAtMs: fixedMs),
        ])
        XCTAssertEqual(store.state.requestStatusText, "Finalized locally; An unknown chat error occurred.")

        await store.finish()
    }

    /// CBW-001-recover_persisted_chat_state: persistence retry는 저장을 다시 시도하고 recovery state를 제거한다.
    /// errorRecoveryTapped가 persistenceRecovery 경로에서 saveSession을 재실행해 completed로 복귀하는지 검증합니다.
    /// - 검증 내용: persistence snapshot count, persisted transcript, persistenceRecoverySucceeded 이후 상태를 확인합니다.
    /// - 사전 조건: transcript와 completed lock은 이미 있고 executionPhase는 persistenceRecovery(.unknown)입니다.
    /// - 기대 결과: snapshot이 한 번 저장되고 lastExecutionFailure는 nil로 초기화됩니다.
    func testRecoverPersistedChatStateRetriesSaveAndClearsRecoveryState() async {
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let fixedMs: Int64 = 1_700_000_001_000
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444")),
                runID: AiChatRunID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [AiChatMessage(role: .user, content: "Hello")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        ).recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        let transcript = [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Hi"),
        ]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: transcript,
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(lock, .unknown),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }

        await store.send(.errorRecoveryTapped)

        await store.receive(.persistenceRecoverySucceeded(lock)) { state in
            state.lastExecutionFailure = nil
            state.executionPhase = .completed(lock)
        }

        XCTAssertEqual(persistence.snapshots.count, 1)
        XCTAssertEqual(persistence.snapshots.first?.sessionID, sessionID)
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory, transcript)
        await store.finish()
    }

    /// CBW-001-recover_persisted_chat_state: 이미 성공한 persistence retry 뒤에 늦은 실패 이벤트가 와도 무시된다.
    /// recovery success와 retry failure가 경합할 때 success state가 다시 오염되지 않는지 검증합니다.
    /// - 검증 내용: persistenceRecoverySucceeded 이후 lastExecutionFailure nil, executionPhase completed 유지 여부를 확인합니다.
    /// - 사전 조건: executionPhase는 persistenceRecovery이며 뒤이어 success와 stale retry failure를 순서대로 보냅니다.
    /// - 기대 결과: completed 상태가 유지되고 stale retry failure는 무시됩니다.
    func testRecoverPersistedChatStateIgnoresRetryFailureAfterSuccess() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("77777777-7777-7777-7777-777777777777"))
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("88888888-8888-8888-8888-888888888888")),
                runID: AiChatRunID(rawValue: makeUUID("99999999-9999-9999-9999-999999999999")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [AiChatMessage(role: .user, content: "Hello")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(lock, .unknown),
        )) {
            AiChatFeature()
        }

        await store.send(.persistenceRecoverySucceeded(lock)) { state in
            state.lastExecutionFailure = nil
            state.executionPhase = .completed(lock)
        }

        await store.send(.persistenceRecoveryRetryFailed(lock, .unknown))

        XCTAssertNil(store.state.lastExecutionFailure)
        XCTAssertEqual(store.state.executionPhase, .completed(lock))
        await store.finish()
    }

    /// CBW-001-recover_persisted_chat_state: retryable recovery state가 없으면 errorRecoveryTapped는 no-op이다.
    /// idle surface에서 recovery action이 잘못 실행되어 상태를 바꾸지 않는지 검증합니다.
    /// - 검증 내용: executionPhase idle과 lastExecutionFailure nil 유지 여부를 확인합니다.
    /// - 사전 조건: sessionStatus는 idle이고 executionPhase도 idle입니다.
    /// - 기대 결과: errorRecoveryTapped 이후에도 아무 상태 변화가 없습니다.
    func testRecoverPersistedChatStateDoesNothingWithoutRetryableState() async {
        let catalogRows = makeCatalogRows()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionStatus: .idle,
            currentContext: makeContextSnapshot(),
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        }

        await store.send(.errorRecoveryTapped)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lastExecutionFailure)
        await store.finish()
    }

    // MARK: - CBW-001-continue_inflight_chat_request

    /// CBW-001-continue_inflight_chat_request: 다른 session을 열람했다가 돌아와도 원 request completion은 원 session에 저장된다.
    /// in-flight request 중 session 전환이 발생해도 원래 request lock과 persistence snapshot이 active session 기준으로 마무리되는지 검증합니다.
    /// - 검증 내용: restore 이후 processing lock 유지, final completion transcript, saved session summary, persistence
    /// snapshots를 확인합니다.
    /// - 사전 조건: active session에서 submit을 시작한 뒤 target session으로 이동하고 다시 active session으로 복귀합니다.
    /// - 기대 결과: 원 request final은 active session transcript와 session row를 갱신하고 target session을 오염시키지 않습니다.
    func testContinueInFlightChatRequestPreservesOriginalSessionCompletionAcrossSessionSwitch() async {
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111221"))
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222221"))
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_001_221
        let activeRow = AiChatSessionSummary(
            sessionID: activeSessionID,
            title: "Active request",
            preview: "Question A",
            messageCount: 1,
            contextTitle: "Docs",
            provider: selectedHandle.provider,
            model: selectedHandle,
            createdAtMs: fixedMs - 10,
            updatedAtMs: fixedMs - 10,
            status: .active,
        )
        let targetSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Earlier target chat")],
            updatedAtMs: fixedMs - 1,
        )
        let targetRow = AiChatSessionSummary(snapshot: targetSnapshot)
        let activeRestoreSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Question A", createdAtMs: fixedMs)],
            updatedAtMs: fixedMs,
        )
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { id in
            switch id {
            case targetSessionID:
                targetSnapshot
            case activeSessionID:
                activeRestoreSnapshot
            default:
                nil
            }
        })

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [activeRow, targetRow], selectedSessionID: activeSessionID),
            sessionID: activeSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            draftText: "Question A",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: selectedHandle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in [] },
                loadSession: { try await persistence.loadSession($0) },
                saveSession: { snapshot in await persistence.save(snapshot) },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { AIConnectionsFile.empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = selectedHandle
            state.sessionList.unreadCompletedSessionIDs = []
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let activeRequestStartSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Question A", createdAtMs: fixedMs)],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )

        await store.send(.sessionRowTapped(targetSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = targetSessionID
            state.restoreSessionID = targetSessionID
            state.currentContextFolderStructureModes = [:]
            state.backgroundExecutionPhases[lock.requestID] = .processing(lock)
            state.executionPhase = .idle
            state.lockedModelHandle = nil
            state.streamingAssistantDraft = nil
        }

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: targetSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = targetSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = targetSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = nil
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.selectedModelHandle = targetSnapshot.model
            state.selectedThinking = targetSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: targetSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        await store.send(.sessionRowTapped(activeSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = activeSessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.restoreSessionID = activeSessionID
            state.currentContextFolderStructureModes = [:]
        }

        await store.receive(.restoreOutcome(
            requestedSessionID: activeSessionID,
            .restored(snapshot: activeRequestStartSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = activeSessionID
            state.sessionStatus = .active
            state.transcriptHistory = activeRequestStartSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = activeRequestStartSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = activeRequestStartSnapshot.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .processing(lock)
            state.selectedModelHandle = activeRequestStartSnapshot.model
            state.selectedThinking = activeRequestStartSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: activeRequestStartSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }
        XCTAssertEqual(store.state.surfaceState, .processing(
            processing: AiChatProcessingState(
                lockedModel: AiChatLockedModelDisplayModel(
                    handle: selectedHandle,
                    label: AiChatModelLabel(title: catalogRows[0].displayName),
                ),
                cancelAffordance: AiChatCancelAffordance(title: "Cancel request", isEnabled: true),
            ),
            summary: store.state.currentContextSummaryDisplayModel,
            selectedModel: store.state.selectedModelDisplayModel,
        ))
        XCTAssertTrue(store.state.isProcessing)

        let assistantMessage = AiChatMessage(
            role: .assistant,
            content: "Original request completed",
            createdAtMs: fixedMs,
        )
        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        let finalizedLock = lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Question A", createdAtMs: fixedMs),
                assistantMessage,
            ]
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = lock.context.requestContext
            state.lastRequestContextModelHandle = selectedHandle
            state.executionPhase = .completed(finalizedLock)
            state.transcriptAutoScrollVersion = 3
        }

        let expectedOriginalSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Question A", createdAtMs: fixedMs),
                assistantMessage,
            ],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let expectedOriginalSummary = AiChatSessionSummary(snapshot: expectedOriginalSnapshot)
        await store.receive(.sessionSnapshotSaved(
            AiChatSessionSummary(snapshot: expectedOriginalSnapshot),
            snapshot: expectedOriginalSnapshot,
            requestID: finalizedLock.requestID,
            runID: finalizedLock.runID,
        )) { state in
            state.sessionList.replaceRow(expectedOriginalSummary)
            state.sessionList.selectedSessionID = activeSessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.sessionList.errorMessage = nil
        }

        await store.finish()
        XCTAssertEqual(store.state.sessionID, activeSessionID)
        XCTAssertEqual(store.state.transcriptHistory, expectedOriginalSnapshot.transcriptHistory)
        if case .processing = store.state.surfaceState {
            XCTFail("The restored original session must leave processing after final completion")
        }
        XCTAssertFalse(store.state.isProcessing)
        XCTAssertEqual(persistence.snapshots, [activeRequestStartSnapshot, expectedOriginalSnapshot])
    }

    /// CBW-001-continue_inflight_chat_request: offscreen final은 정규화된 assistant timestamp를 snapshot에 저장한다.
    /// 다른 session을 보는 동안 완료된 응답도 visible completion과 같은 terminal clock을 소비하는지 검증합니다.
    /// - 검증 내용: background completed lock, final snapshot, persistence snapshot의 assistant timestamp를 확인합니다.
    /// - 사전 조건: 원 session request lock은 background processing이고 현재 화면은 다른 session을 표시합니다.
    /// - 기대 결과: raw response timestamp와 무관하게 assistant와 terminal metadata가 하나의 deterministic timestamp를 사용합니다.
    func testContinueInFlightChatRequestNormalizesOffscreenFinalTimestamp() async {
        let rows = makeCatalogRows()
        let selectedHandle = rows[0].handle
        let originalSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111231"))
        let visibleSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222231"))
        let terminalMs: Int64 = 1_700_000_001_231
        let user = AiChatMessage(role: .user, content: "Original question", createdAtMs: terminalMs - 10)
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: originalSessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("33333333-3333-3333-3333-333333333231")),
                runID: AiChatRunID(rawValue: makeUUID("44444444-4444-4444-4444-444444444231")),
                model: selectedHandle,
                selectedRow: rows[0],
            ),
            messages: [user],
        )
        let lock = makeSubmitLock(request: request, catalogRows: rows, selectedHandle: selectedHandle)
        let persistence = AiChatSessionPersistenceSpy()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: visibleSessionID,
            transcriptHistory: [AiChatMessage(role: .user, content: "Visible session")],
            backgroundExecutionPhases: [lock.requestID: .processing(lock)],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(makeFixedDate(milliseconds: terminalMs))
            $0.aiChatSessionPersistenceClient = .init(
                loadSession: { _ in nil },
                saveSession: { snapshot in await persistence.save(snapshot) },
                deleteSession: { _ in },
            )
        }
        applyObservationFocusedExhaustivity(to: store)
        let rawAssistant = AiChatMessage(role: .assistant, content: "Offscreen answer", createdAtMs: 99)
        let rawResponse = AiChatResponse(context: request.context, assistantMessage: rawAssistant, completedAtMs: 88)

        await store.send(.executionEvent(.final(response: rawResponse)))
        guard case let .completed(completedLock) = store.state.backgroundExecutionPhases[lock.requestID],
              let snapshot = completedLock.finalSnapshot
        else {
            return XCTFail("Expected completed background lock with final snapshot")
        }
        XCTAssertEqual(completedLock.observabilitySummary.terminalAtMs, terminalMs)
        XCTAssertEqual(snapshot.transcriptHistory.last?.createdAtMs, terminalMs)

        await store.skipReceivedActions()
        await store.finish()
        XCTAssertEqual(persistence.snapshots.last?.transcriptHistory.last?.createdAtMs, terminalMs)
        XCTAssertEqual(store.state.transcriptHistory.last?.content, "Visible session")
    }

    /// CBW-001-continue_inflight_chat_request: offscreen session failure는 현재 보이는 session을 오염시키지 않는다.
    /// 다른 session을 보는 동안 원 request가 failure로 끝나도 visible session의 transcript와 error surface가 변하지 않는지 검증합니다.
    /// - 검증 내용: target session visible state 보호, active session 복귀 후 original failure 복원, persistence snapshot count를
    /// 확인합니다.
    /// - 사전 조건: active session submit 후 target session으로 이동한 상태에서 원 request가 network failure로 종료됩니다.
    /// - 기대 결과: target session은 깨끗하게 유지되고 active session 복귀 시에만 original failure가 드러납니다.
    func testContinueInFlightChatRequestDoesNotPolluteVisibleSessionWhenOffscreenFailureArrives() async {
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111241"))
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222241"))
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_001_241
        let activeRow = AiChatSessionSummary(
            sessionID: activeSessionID,
            title: "Active request",
            preview: "Question A",
            messageCount: 1,
            contextTitle: "Docs",
            provider: selectedHandle.provider,
            model: selectedHandle,
            createdAtMs: fixedMs - 10,
            updatedAtMs: fixedMs - 10,
            status: .active,
        )
        let targetSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Earlier target chat")],
            updatedAtMs: fixedMs - 1,
        )
        let targetRow = AiChatSessionSummary(snapshot: targetSnapshot)
        let activeRestoreSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Question A", createdAtMs: fixedMs)],
            updatedAtMs: fixedMs,
        )
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { id in
            switch id {
            case targetSessionID:
                targetSnapshot
            case activeSessionID:
                activeRestoreSnapshot
            default:
                nil
            }
        })

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [activeRow, targetRow], selectedSessionID: activeSessionID),
            sessionID: activeSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            draftText: "Question A",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: selectedHandle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in [] },
                loadSession: { try await persistence.loadSession($0) },
                saveSession: { snapshot in await persistence.save(snapshot) },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { AIConnectionsFile.empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = selectedHandle
            state.sessionList.unreadCompletedSessionIDs = []
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let activeRequestStartSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Question A", createdAtMs: fixedMs)],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )

        await store.send(.sessionRowTapped(targetSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = targetSessionID
            state.restoreSessionID = targetSessionID
            state.currentContextFolderStructureModes = [:]
            state.backgroundExecutionPhases[lock.requestID] = .processing(lock)
            state.executionPhase = .idle
            state.lockedModelHandle = nil
            state.streamingAssistantDraft = nil
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: targetSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = targetSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = targetSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = nil
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.selectedModelHandle = targetSnapshot.model
            state.selectedThinking = targetSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: targetSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }
        XCTAssertNil(store.state.requestStatusText)

        stream.yield(.failed(context: request.context, reason: .network))
        stream.finish()

        let failedLock = lock.recordingTerminal(at: fixedMs, failure: .network, wasCancelled: false)
        await store.receive(.executionEvent(.failed(context: request.context, reason: .network))) { state in
            state.backgroundExecutionPhases[lock.requestID] = .failed(failedLock, .network)
        }
        XCTAssertEqual(store.state.sessionID, targetSessionID)
        XCTAssertEqual(store.state.transcriptHistory, targetSnapshot.transcriptHistory)
        XCTAssertNil(store.state.lastExecutionFailure)
        XCTAssertNil(store.state.requestStatusText)
        if case .processing = store.state.surfaceState {
            XCTFail("The visible target session must not show another session's failed request as processing")
        }

        await store.send(.sessionRowTapped(activeSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = activeSessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.restoreSessionID = activeSessionID
            state.currentContextFolderStructureModes = [:]
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: activeSessionID,
            .restored(snapshot: activeRequestStartSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = activeSessionID
            state.sessionStatus = .active
            state.transcriptHistory = activeRequestStartSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = activeRequestStartSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = activeRequestStartSnapshot.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .failed(failedLock, .network)
            state.selectedModelHandle = activeRequestStartSnapshot.model
            state.selectedThinking = activeRequestStartSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: activeRequestStartSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.requestStatusText, AiChatExecutionFailure.network.displayMessage)
        XCTAssertEqual(persistence.snapshots.count, 1)
        await store.finish()
    }

    // MARK: - CBW-001-open_contextual_chat

    /// CBW-001-open_contextual_chat: transcript projection은 plain/Markdown/streaming match와 stable block anchor를 구성한다.
    /// 기존 inline bold/link 속성을 보존하면서 현재 결과에는 underline 의미를 추가하는지 검증합니다.
    /// - 검증 내용: row/block 순서, query-tagged count, stable anchor, highlight kind, Markdown attributes를 확인합니다.
    /// - 사전 조건: user plain, assistant heading/paragraph, streaming assistant에 같은 query가 있습니다.
    /// - 기대 결과: 네 결과가 rendered block 순서로 투영되고 현재 결과만 non-color current decoration을 가집니다.
    func testOpenContextualChatProjectsStableRenderedMatchesAndPreservesInlineStylesWhenHighlighting() throws {
        let presentation = makeTranscriptSearchPresentation()

        XCTAssertEqual(presentation.matchCountProjection, .init(query: "needle", matchCount: 4))
        XCTAssertEqual(
            AiChatView.transcriptSearchCountText(.init(
                isPresented: true,
                query: "needle",
                matchCount: 5,
                currentMatchOrdinal: 2,
                status: .matches,
            )),
            "2/5",
        )
        XCTAssertEqual(presentation.matches.map(\.transcriptRow), [
            .message(index: 0),
            .message(index: 1),
            .message(index: 1),
            .streamingAssistant,
        ])
        XCTAssertEqual(presentation.matches.map(\.blockIndex), [0, 0, 1, 0])
        XCTAssertEqual(
            presentation.anchor(for: presentation.matches[2]),
            AiChatTranscriptBlockAnchor(transcriptRow: .message(index: 1), blockIndex: 1),
        )

        let attributed = try AttributedString(
            markdown: "Use **needle** and [link](https://example.com)",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
        )
        let highlighted = AiChatRenderedTextHighlighter.highlight(
            attributed,
            matchOffsets: [4 ..< 10],
            currentMatchOffsets: 4 ..< 10,
        )

        XCTAssertEqual(String(highlighted.characters), "Use needle and link")
        XCTAssertTrue(highlighted.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        })
        XCTAssertTrue(highlighted.runs.contains { $0.link == URL(string: "https://example.com") })
        XCTAssertTrue(highlighted.runs.contains { $0.underlineStyle != nil })
        XCTAssertEqual(
            AiChatRenderedTextHighlighter.decorations(
                matchOffsets: [4 ..< 10, 15 ..< 19],
                currentMatchOffsets: 4 ..< 10,
            )
            .map(\.kind),
            [.current, .match],
        )
    }

    /// CBW-001-open_contextual_chat: explicit previous/next만 transcript navigation revision을 증가시킨다.
    /// 검색 open/close/query/count와 streaming count reconciliation은 scroll intent를 만들지 않는지 검증합니다.
    /// - 검증 내용: navigation revision, wrap, auto-scroll version/session/offset 보존을 확인합니다.
    /// - 사전 조건: active chat에 기존 scroll offset과 streaming auto-scroll version이 있습니다.
    /// - 기대 결과: next/previous만 revision을 증가시키고 count 변화는 ordinal만 clamp합니다.
    func testOpenContextualChatOnlyExplicitMatchNavigationRequestsScrollIntent() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            transcriptAutoScrollVersion: 9,
            transcriptScrollOffsets: [sessionID: 42],
        )) {
            AiChatFeature()
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.transcriptSearchOpened) { state in
            state.transcriptSearch.isPresented = true
            state.transcriptSearch.focusRevision = 1
        }
        await store.send(.transcriptSearchQueryChanged("match")) { $0.transcriptSearch.query = "match" }
        await store.send(.transcriptSearchMatchCountChanged(.init(query: "match", matchCount: 2))) { state in
            state.transcriptSearch.matchCount = 2
            state.transcriptSearch.currentMatchOrdinal = 1
            state.transcriptSearch.status = .matches
        }
        XCTAssertEqual(store.state.transcriptSearch.navigationRevision, 0)
        XCTAssertTrue(AiChatView.shouldAutoScrollToBottom(transcriptSearch: store.state.transcriptSearch))

        await store.send(.transcriptSearchNextTapped) { state in
            state.transcriptSearch.currentMatchOrdinal = 2
            state.transcriptSearch.navigationRevision = 1
        }
        await store.send(.transcriptSearchMatchCountChanged(.init(query: "match", matchCount: 1))) { state in
            state.transcriptSearch.matchCount = 1
            state.transcriptSearch.currentMatchOrdinal = 1
        }
        XCTAssertEqual(store.state.transcriptSearch.navigationRevision, 1)
        XCTAssertFalse(AiChatView.shouldAutoScrollToBottom(transcriptSearch: store.state.transcriptSearch))

        await store.send(.transcriptSearchPreviousTapped) { state in
            state.transcriptSearch.navigationRevision = 2
        }
        XCTAssertEqual(store.state.transcriptAutoScrollVersion, 9)
        XCTAssertEqual(store.state.transcriptScrollOffsets, [sessionID: 42])
        XCTAssertEqual(store.state.sessionID, sessionID)

        await store.send(.transcriptSearchClosed) { state in
            state.transcriptSearch = .init()
        }
        XCTAssertEqual(store.state.transcriptSearch.navigationRevision, 0)
        XCTAssertTrue(AiChatView.shouldAutoScrollToBottom(transcriptSearch: store.state.transcriptSearch))
    }

    /// CBW-001-open_contextual_chat: streaming render plan은 transcript row와 latest assistant를 한 번의 bounded pass로 준비한다.
    /// token-driven body evaluation이 row마다 latest assistant를 다시 검색해 O(history²)가 되지 않는지 검증합니다.
    /// - 검증 내용: row range, latest assistant index, inspected message upper bound를 확인합니다.
    /// - 사전 조건: 첫 row만 assistant이고 뒤에 999개 user row가 이어지는 긴 stable transcript가 있습니다.
    /// - 기대 결과: 1,000개 row를 allocation-free range로 노출하고 latest scan은 전체 message 수를 넘지 않습니다.
    func testOpenContextualChatBuildsLinearTranscriptRenderPlan() {
        let messages = [AiChatMessage(role: .assistant, content: "answer")]
            + (0 ..< 999).map { AiChatMessage(role: .user, content: "question \($0)") }

        let plan = AiChatTranscriptRenderPlan.make(messages: messages)

        XCTAssertEqual(plan.messageIndices, messages.indices)
        XCTAssertEqual(plan.latestAssistantMessageIndex, 0)
        XCTAssertLessThanOrEqual(plan.latestAssistantInspectionCount, messages.count)
    }

    /// CBW-001-open_contextual_chat: request cache는 streaming token마다 stable history rows를 다시 매핑하지 않는다.
    /// body-side request construction도 actor cache에 도달하기 전에 O(history) 작업을 반복하지 않는지 검증합니다.
    /// - 검증 내용: hidden no-build, active stable-row build/reuse count, O(1) revision identity를 확인합니다.
    /// - 사전 조건: 두 token은 stable history revision을 공유하고, 이후 같은 session/count에서 history content만 변경됩니다.
    /// - 기대 결과: token 사이는 stable rows를 재사용하고 content 변경은 새 stable revision/build로 invalidation합니다.
    func testOpenContextualChatRequestCacheReusesStableRowsAcrossStreamingTokens() {
        let sessionToken = UUID()
        let messages = [AiChatMessage(role: .assistant, content: "# stable needle")]
        var cache = AiChatTranscriptSearchRequestCache()

        _ = cache.request(
            isPresented: false,
            query: "needle",
            source: AiChatTranscriptSearchRequestSource(
                sessionToken: sessionToken,
                messages: messages,
                streamingAssistantContent: "n",
                transcriptRevision: 10,
                streamingRevision: 1,
            ),
        )
        let first = cache.request(
            isPresented: true,
            query: "needle",
            source: AiChatTranscriptSearchRequestSource(
                sessionToken: sessionToken,
                messages: messages,
                streamingAssistantContent: "ne",
                transcriptRevision: 10,
                streamingRevision: 2,
            ),
        )
        let second = cache.request(
            isPresented: true,
            query: "needle",
            source: AiChatTranscriptSearchRequestSource(
                sessionToken: sessionToken,
                messages: messages,
                streamingAssistantContent: "nee",
                transcriptRevision: 10,
                streamingRevision: 3,
            ),
        )
        let changedMessages = [AiChatMessage(role: .assistant, content: "# changed needle")]
        let changed = cache.request(
            isPresented: true,
            query: "needle",
            source: AiChatTranscriptSearchRequestSource(
                sessionToken: sessionToken,
                messages: changedMessages,
                streamingAssistantContent: "need",
                transcriptRevision: 11,
                streamingRevision: 4,
            ),
        )

        XCTAssertEqual(cache.diagnostics.stableRowsBuildCount, 2)
        XCTAssertEqual(cache.diagnostics.stableRowsReuseCount, 1)
        XCTAssertEqual(first.stableRowsRevision, second.stableRowsRevision)
        XCTAssertNotEqual(second.stableRowsRevision, changed.stableRowsRevision)
        XCTAssertEqual(changed.stableRows.first?.content, "# changed needle")
        XCTAssertNotEqual(first.streamingRevision, second.streamingRevision)
        XCTAssertNotEqual(first, second)
    }

    /// CBW-001-open_contextual_chat: hidden 또는 empty transcript search는 projection parsing을 시작하지 않는다.
    /// inactive search가 SwiftUI body 평가만으로 history나 streaming Markdown을 투영하지 않는지 검증합니다.
    /// - 검증 내용: request short-circuit와 projector no-work/stable/streaming diagnostics를 확인합니다.
    /// - 사전 조건: assistant Markdown history와 streaming content가 있지만 search가 hidden이거나 query가 비어 있습니다.
    /// - 기대 결과: 두 request 모두 stable rows와 streaming payload가 비고 parse/build count는 0입니다.
    func testOpenContextualChatProjectionDoesNoWorkWhenHiddenOrQueryIsEmpty() async throws {
        let messages = [AiChatMessage(role: .assistant, content: "# Needle")]
        let hidden = AiChatTranscriptSearchProjectionRequest.make(
            isPresented: false,
            query: "needle",
            sessionToken: UUID(),
            messages: messages,
            streamingAssistantContent: "needle stream",
        )
        let empty = AiChatTranscriptSearchProjectionRequest.make(
            isPresented: true,
            query: "",
            sessionToken: UUID(),
            messages: messages,
            streamingAssistantContent: "needle stream",
        )
        let projector = AiChatTranscriptSearchProjector(streamingDebounce: .zero)

        _ = try await projector.project(hidden, generation: 1)
        _ = try await projector.project(empty, generation: 2)
        let diagnostics = await projector.diagnostics()

        XCTAssertFalse(hidden.requiresWork)
        XCTAssertTrue(hidden.stableRows.isEmpty)
        XCTAssertNil(hidden.streamingAssistantContent)
        XCTAssertFalse(empty.requiresWork)
        XCTAssertTrue(empty.stableRows.isEmpty)
        XCTAssertNil(empty.streamingAssistantContent)
        XCTAssertEqual(diagnostics.noWorkCount, 2)
        XCTAssertEqual(diagnostics.stableProjectionBuildCount, 0)
        XCTAssertEqual(diagnostics.streamingProjectionBuildCount, 0)
    }

    /// CBW-001-open_contextual_chat: streaming token update는 unchanged history projection을 재사용한다.
    /// active streaming search가 매 token마다 stable transcript를 다시 parse/match하지 않는지 검증합니다.
    /// - 검증 내용: stable projection build/reuse와 streaming projection build diagnostics를 확인합니다.
    /// - 사전 조건: session/query/history는 같고 streaming assistant content만 두 request 사이에 변경됩니다.
    /// - 기대 결과: stable projection은 한 번 build·한 번 reuse되고 streaming projection만 두 번 build됩니다.
    func testOpenContextualChatProjectionReusesStableRowsAcrossStreamingUpdates() async throws {
        let sessionToken = UUID()
        let messages = [AiChatMessage(role: .assistant, content: "# stable needle")]
        let firstRequest = AiChatTranscriptSearchProjectionRequest.make(
            isPresented: true,
            query: "needle",
            sessionToken: sessionToken,
            messages: messages,
            streamingAssistantContent: "needle one",
        )
        let secondRequest = AiChatTranscriptSearchProjectionRequest.make(
            isPresented: true,
            query: "needle",
            sessionToken: sessionToken,
            messages: messages,
            streamingAssistantContent: "needle two",
        )
        let projector = AiChatTranscriptSearchProjector(streamingDebounce: .zero)

        _ = try await projector.project(firstRequest, generation: 1)
        let second = try await projector.project(secondRequest, generation: 2)
        let diagnostics = await projector.diagnostics()

        XCTAssertEqual(second.presentation.matches.count, 2)
        XCTAssertEqual(diagnostics.stableProjectionBuildCount, 1)
        XCTAssertEqual(diagnostics.stableProjectionReuseCount, 1)
        XCTAssertEqual(diagnostics.streamingProjectionBuildCount, 2)
    }

    /// CBW-001-open_contextual_chat: superseded projection generation은 stale query/session/transcript 결과를 publish하지
    /// 않는다.
    /// cancelled work와 MainActor publication gate가 최신 request identity만 수락하는지 검증합니다.
    /// - 검증 내용: generation invalidation, CancellationError, result request/generation identity를 확인합니다.
    /// - 사전 조건: 첫 request 완료 후 다른 session/query/history request가 더 높은 generation으로 등록됩니다.
    /// - 기대 결과: 이전 generation 재실행은 취소되고 최신 result만 최신 request/generation과 일치합니다.
    func testOpenContextualChatProjectionRejectsSupersededGenerationResults() async throws {
        let firstRequest = AiChatTranscriptSearchProjectionRequest.make(
            isPresented: true,
            query: "old",
            sessionToken: UUID(),
            messages: [AiChatMessage(role: .user, content: "old")],
            streamingAssistantContent: "old",
        )
        let latestRequest = AiChatTranscriptSearchProjectionRequest.make(
            isPresented: true,
            query: "new",
            sessionToken: UUID(),
            messages: [AiChatMessage(role: .user, content: "new")],
            streamingAssistantContent: "new",
        )
        let projector = AiChatTranscriptSearchProjector(streamingDebounce: .zero)
        let first = try await projector.project(firstRequest, generation: 1)

        await projector.invalidate(generation: 2)
        do {
            _ = try await projector.project(firstRequest, generation: 1)
            XCTFail("Superseded generation must be cancelled")
        } catch is CancellationError {}
        let latest = try await projector.project(latestRequest, generation: 2)

        XCTAssertFalse(first.isCurrent(request: latestRequest, generation: 2))
        XCTAssertTrue(latest.isCurrent(request: latestRequest, generation: 2))
    }

    /// CBW-001-open_contextual_chat: dense transcript match lookup은 block index를 한 번 구성해 descriptor를 한 번만 검사한다.
    /// 많은 block과 occurrence에서도 presentation 조회가 전체 descriptor를 반복 스캔하지 않는지 검증합니다.
    /// - 검증 내용: block lookup 수와 inspected descriptor 합이 B와 M에 선형으로 제한되는지 확인합니다.
    /// - 사전 조건: 12개 user block마다 동일 query가 100회 반복되고 결과가 없는 block도 조회합니다.
    /// - 기대 결과: 1,200개 match를 유지하면서 lookup은 block당 1회, descriptor 검사는 전체 match 수를 넘지 않습니다.
    func testOpenContextualChatIndexesDenseMatchesByBlockWithBoundedLookupWork() {
        let messages = (0 ..< 12).map { _ in
            AiChatMessage(role: .user, content: String(repeating: "needle ", count: 100))
        }
        let presentation = AiChatTranscriptSearchPresentation(
            query: "needle",
            messages: messages,
            streamingAssistantContent: nil,
        )
        let lookups = messages.indices.map { index in
            presentation.matchLookup(transcriptRow: .message(index: index), blockIndex: 0)
        }
        let missingLookup = presentation.matchLookup(transcriptRow: .message(index: 99), blockIndex: 0)

        XCTAssertEqual(presentation.matches.count, 1200)
        XCTAssertTrue(lookups.allSatisfy { $0.offsets.count == 100 })
        XCTAssertEqual(lookups.reduce(0) { $0 + $1.bucketLookupCount }, messages.count)
        XCTAssertEqual(lookups.reduce(0) { $0 + $1.inspectedDescriptorCount }, presentation.matches.count)
        XCTAssertEqual(missingLookup.bucketLookupCount, 1)
        XCTAssertEqual(missingLookup.inspectedDescriptorCount, 0)
    }

    /// CBW-001-open_contextual_chat: dense highlight range 변환은 정렬된 offset을 한 cursor로 처리한다.
    /// 긴 rendered block의 조밀한 match가 매 occurrence마다 문자열 시작부터 다시 순회하지 않는지 검증합니다.
    /// - 검증 내용: malformed range 무시, resolved count, Character cursor advance upper bound를 확인합니다.
    /// - 사전 조건: 2,000 Character block에 200개 valid offset과 음수·범위 밖 offset을 역순으로 전달합니다.
    /// - 기대 결과: valid 200개만 highlight되고 cursor advance는 마지막 valid upper bound 이하이며 current underline이 유지됩니다.
    func testOpenContextualChatHighlightsDenseMatchesWithOneBoundedCharacterCursor() {
        let text = AttributedString(String(repeating: "x", count: 2000))
        let validOffsets = stride(from: 0, to: 2000, by: 10).map { $0 ..< ($0 + 1) }
        let result = AiChatRenderedTextHighlighter.highlighting(
            text,
            matchOffsets: [2500 ..< 2501, -1 ..< 1] + validOffsets.reversed(),
            currentMatchOffsets: 1990 ..< 1991,
        )

        XCTAssertEqual(String(result.attributedText.characters), String(repeating: "x", count: 2000))
        XCTAssertEqual(result.resolvedDecorationCount, validOffsets.count)
        XCTAssertEqual(result.characterAdvanceCount, 1991)
        XCTAssertLessThanOrEqual(result.characterAdvanceCount, text.characters.count)
        XCTAssertTrue(result.attributedText.runs.contains { $0.underlineStyle != nil })
    }

    /// CBW-001-open_contextual_chat: 같은 long block의 먼 occurrence는 서로 다른 scroll target과 위치 intent를 만든다.
    /// block-only dedupe가 명시적 next/previous occurrence 이동을 제거하지 않는지 검증합니다.
    /// - 검증 내용: occurrence range 기반 ID, 상대 anchor, rendered marker ID, 명시적 navigation seam을 확인합니다.
    /// - 사전 조건: 하나의 긴 user paragraph 시작과 끝에 동일 query occurrence가 각각 존재합니다.
    /// - 기대 결과: 두 occurrence는 서로 다른 target ID와 상대 위치를 만들고 두 번째 이동 intent도 유지됩니다.
    func testOpenContextualChatCreatesDistinctScrollIntentsForDistantMatchesInSameBlock() throws {
        let content = "needle" + String(repeating: "x", count: 900) + "needle"
        let presentation = AiChatTranscriptSearchPresentation(
            query: "needle",
            messages: [AiChatMessage(role: .user, content: content)],
            streamingAssistantContent: nil,
        )
        let first = try XCTUnwrap(presentation.scrollTarget(for: presentation.matches[0]))
        let second = try XCTUnwrap(presentation.scrollTarget(for: presentation.matches[1]))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.scrollID, second.scrollID)
        XCTAssertGreaterThan(second.relativeAnchor.y, first.relativeAnchor.y)
        let renderedAnchors = AiChatTranscriptMatchAnchors(
            descriptors: presentation.matchDescriptors(transcriptRow: .message(index: 0), blockIndex: 0),
        )
        XCTAssertEqual(renderedAnchors.targetIDs, [first.scrollID])
        XCTAssertNotNil(AiChatView.searchNavigationTarget(
            presentation: presentation,
            currentMatch: presentation.matches[0],
        ))
        XCTAssertNotNil(AiChatView.searchNavigationTarget(
            presentation: presentation,
            currentMatch: presentation.matches[1],
        ))
        XCTAssertNotNil(AiChatView.searchNavigationTarget(
            presentation: presentation,
            currentMatch: presentation.matches[1],
        ))
    }
}

private actor CBW001ProviderDriver {
    var requests: [(AiChatRequest, StoredCredentialPayload?)] = []

    func append(request: AiChatRequest, credential: StoredCredentialPayload?) {
        requests.append((request, credential))
    }

    func snapshot() -> [(AiChatRequest, StoredCredentialPayload?)] {
        requests
    }
}

private struct AiChatMetadataSourceSubtrees {
    let card: String
    let panel: String
    let viewport: String
    let historicalCard: String
}

private func aiChatMetadataSourceSubtrees() throws -> AiChatMetadataSourceSubtrees {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let uiRoot = packageRoot.appendingPathComponent("Sources/VoyagerFeaturesAiChat/Ui")
    let conversation = try String(
        contentsOf: uiRoot.appendingPathComponent("AiChatConversationSurface.swift"), encoding: .utf8,
    )
    let view = try String(contentsOf: uiRoot.appendingPathComponent("AiChatView.swift"), encoding: .utf8)
    let overlaySupport = try String(
        contentsOf: uiRoot.appendingPathComponent("AiChatViewOverlaySupport.swift"), encoding: .utf8,
    )
    let cardStart = try XCTUnwrap(conversation.range(of: "private struct AiChatAssistantCard: View"))
    let waitingStart = try XCTUnwrap(conversation.range(of: "private struct AiChatWaitingIndicator: View"))
    let historicalStart = try XCTUnwrap(conversation.range(of: "    private func assistantMessage("))
    let regenerateStart = try XCTUnwrap(conversation.range(of: "    private var regenerateAction"))
    let panelStart = try XCTUnwrap(overlaySupport.range(of: "struct AiChatAssistantMetadataPanel: View"))
    let compactStart = try XCTUnwrap(view.range(of: "    @ViewBuilder\n    private func compactConnectionCTA"))
    return AiChatMetadataSourceSubtrees(
        card: String(conversation[cardStart.lowerBound ..< waitingStart.lowerBound]),
        panel: String(overlaySupport[panelStart.lowerBound...]),
        viewport: overlaySupport + "\n" + String(view[..<compactStart.lowerBound]),
        historicalCard: String(conversation[historicalStart.lowerBound ..< regenerateStart.lowerBound]),
    )
}

private struct CBW001TranscriptContext: Equatable {
    let sessionID: AiChatSessionID?
    let sessionListQuery: String
    let scrollOffsets: [AiChatSessionID: CGFloat]
}

private struct CBW001SubmitFixture {
    let persistence: AiChatSessionPersistenceSpy
    let driver: CBW001ProviderDriver
    let catalogRows: [AiModelCatalogRow]
    let selectedHandle: AiModelHandle
    let credential: StoredCredentialPayload
    let sessionID: AiChatSessionID
    let fixedMs: Int64
    let expectedAssistantMessage: String
    let providerClient: AiChatProviderExecutionClient
}

private struct CBW001StreamFixture {
    let stream: AiChatExecutionStreamDriver
    let catalogRows: [AiModelCatalogRow]
    let selectedHandle: AiModelHandle
    let fixedMs: Int64
    let store: TestStore<AiChatFeature.State, AiChatFeature.Action>
}

private enum CBW001LifecycleViewCommand {
    static let processing = "lifecycle-processing"
    static let processingRerender = "lifecycle-processing-rerender"
    static let completed = "lifecycle-completed"
    static let sessions = "lifecycle-sessions"
}

@MainActor
private final class CBW001LifecycleAnnouncementRecorder {
    private(set) var announcements: [AiChatLifecycleAnnouncement] = []

    func record(_ announcement: AiChatLifecycleAnnouncement) {
        announcements.append(announcement)
    }
}

private struct CBW001MountedLifecycleAnnouncementFixture {
    let store: StoreOf<AiChatFeature>
    let hostingView: NSHostingView<AnyView>
    let window: NSWindow
    let recorder: CBW001LifecycleAnnouncementRecorder
}

private final class CBW001FocusableView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

private struct CBW001MalformedFinalUserFixture {
    let stream: AiChatExecutionStreamDriver
    let store: TestStore<AiChatFeature.State, AiChatFeature.Action>
    let resolutionID: UUID
    let executionMessages: [AiChatMessage]
    let persistenceMessages: [AiChatMessage]
}

private extension CBW001ContextualChatRequestTests {
    func makeMountedLifecycleAnnouncementFixture(
        sessionID: AiChatSessionID,
        lock: AiChatRequestLock,
    ) -> CBW001MountedLifecycleAnnouncementFixture {
        let recorder = CBW001LifecycleAnnouncementRecorder()
        let store = Store<AiChatFeature.State, AiChatFeature.Action>(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            sessionStatus: .active,
        )) {
            Reduce<AiChatFeature.State, AiChatFeature.Action> { state, action in
                guard case let .draftTextChanged(command) = action else { return .none }
                switch command {
                case CBW001LifecycleViewCommand.processing:
                    state.executionPhase = .processing(lock)
                case CBW001LifecycleViewCommand.processingRerender:
                    state.draftText = command
                case CBW001LifecycleViewCommand.completed:
                    state.executionPhase = .completed(lock)
                case CBW001LifecycleViewCommand.sessions:
                    state.mode = .sessions
                    state.executionPhase = .processing(lock)
                default:
                    break
                }
                return .none
            }
        }
        let sink = AiChatAccessibilityAnnouncementSink { announcement in
            recorder.record(announcement)
        }
        let rootView = AnyView(WithPerceptionTracking {
            AiChatView(
                store: store,
                allowsAttachmentPicker: false,
                centeredEmptyContent: AnyView(Text("Centered content")),
            )
            .environment(\.aiChatAccessibilityAnnouncementSink, sink)
        })
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = hostingView
        return CBW001MountedLifecycleAnnouncementFixture(
            store: store,
            hostingView: hostingView,
            window: window,
            recorder: recorder,
        )
    }

    func settleMountedLifecycleAnnouncementView(_ hostingView: NSView) async {
        for _ in 0 ..< 6 {
            hostingView.layoutSubtreeIfNeeded()
            await drainMainQueue()
            await Task.yield()
        }
    }

    func makeInputCoordinator(
        focusOwner: AiChatInputFocusOwner,
        identity: AiChatComposerIdentity,
    ) -> AiChatInputTextView.Coordinator {
        var text = ""
        var measuredHeight: CGFloat = 0
        let input = AiChatInputTextView(
            text: Binding(get: { text }, set: { text = $0 }),
            measuredHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            composerIdentity: identity,
            focusOwner: focusOwner,
            isDisabled: false,
            maxVisibleHeight: 120,
            onSubmit: {},
            onAttachmentsDropped: { _ in },
        )
        return input.makeCoordinator()
    }

    func makeComposerIdentity(
        sessionUUID: String,
        scopeID: UUID = makeUUID("99999999-9999-9999-9999-999999999001"),
    ) -> AiChatComposerIdentity {
        AiChatComposerIdentity(
            viewScopeID: scopeID,
            displayedSessionID: AiChatSessionID(rawValue: makeUUID(sessionUUID)),
        )
    }

    func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    func makeActivitySignal(
        id: String,
        kind: AiChatExecutionActivityKind,
        phase: AiChatExecutionActivityPhase,
    ) -> AiChatExecutionActivitySignal {
        AiChatExecutionActivitySignal(
            activityID: AiChatExecutionActivityID(rawValue: id),
            kind: kind,
            phase: phase,
            evidence: AiChatExecutionActivityEvidence(
                origin: .providerWire,
                providerEventType: "test.activity",
            ),
        )
    }

    func makeMalformedFinalUserFixture() -> CBW001MalformedFinalUserFixture {
        let stream = AiChatExecutionStreamDriver()
        let rows = makeCatalogRows()
        let model = makeProviderModels()[0]
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111129"))
        let resolutionID = makeUUID("22222222-2222-2222-2222-222222222229")
        let executionMessages = [
            AiChatMessage(role: .user, content: "Earlier execution user", createdAtMs: 11),
            AiChatMessage(role: .assistant, content: "Malformed execution final", createdAtMs: 22),
        ]
        let persistenceMessages = [
            AiChatMessage(role: .user, content: "Earlier persistence user", createdAtMs: 33),
            AiChatMessage(role: .system, content: "Malformed persistence final", createdAtMs: 44),
        ]
        let pending = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: model,
            selectedRow: rows[0],
            preparedRequest: AiChatPreparedRequest(
                prompt: "Malformed",
                messages: executionMessages,
                persistenceTranscriptHistory: persistenceMessages,
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 2,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        let store = TestStore(initialState: AiChatFeature.State(
            catalogRows: rows,
            modelListState: .loaded([model]),
            pendingRequestStart: pending,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_001_299))
            $0.aiChatExecutionClient = .init(execute: { request in stream.stream(for: request) })
        }
        return CBW001MalformedFinalUserFixture(
            stream: stream,
            store: store,
            resolutionID: resolutionID,
            executionMessages: executionMessages,
            persistenceMessages: persistenceMessages,
        )
    }

    var regenerationTranscript: [AiChatMessage] {
        [
            AiChatMessage(role: .user, content: "Hello", createdAtMs: 1_699_999_999_900),
            AiChatMessage(role: .assistant, content: "Old answer", createdAtMs: 1_699_999_999_950),
        ]
    }

    var regeneratedTranscript: [AiChatMessage] {
        [
            AiChatMessage(role: .user, content: "Hello", createdAtMs: 1_699_999_999_900),
            AiChatMessage(role: .assistant, content: "New answer", createdAtMs: 1_700_000_000_300),
        ]
    }

    func applyObservationFocusedExhaustivity(to store: TestStore<AiChatFeature.State, AiChatFeature.Action>) {
        // 사용자 관찰 상태와 terminal 상태를 검증하기 위해 store.exhaustivity = .off를 사용합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)
    }

    func makeTranscriptSearchProjectionRequest(
        for state: AiChatFeature.State,
        cache: inout AiChatTranscriptSearchRequestCache,
    ) -> AiChatTranscriptSearchProjectionRequest {
        cache.request(
            isPresented: state.transcriptSearch.isPresented,
            query: state.transcriptSearch.query,
            source: AiChatTranscriptSearchRequestSource(
                sessionToken: state.sessionID?.rawValue,
                messages: state.transcriptHistory,
                streamingAssistantContent: state.streamingAssistantDisplayModel?.content,
                transcriptRevision: state.transcriptHistoryMutationTracker.value,
                streamingRevision: state.streamingAssistantDraftMutationTracker.value,
            ),
        )
    }

    func makeTranscriptSearchStore(
        _ state: AiChatFeature.State,
    ) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
        let store = TestStore(initialState: state) {
            AiChatFeature()
        }
        applyObservationFocusedExhaustivity(to: store)
        return store
    }

    func transcriptContext(of state: AiChatFeature.State) -> CBW001TranscriptContext {
        CBW001TranscriptContext(
            sessionID: state.sessionID,
            sessionListQuery: state.sessionList.query,
            scrollOffsets: state.transcriptScrollOffsets,
        )
    }

    func makeTranscriptSearchPresentation() -> AiChatTranscriptSearchPresentation {
        AiChatTranscriptSearchPresentation(
            query: "needle",
            messages: [
                AiChatMessage(role: .user, content: "Needle plain"),
                AiChatMessage(
                    role: .assistant,
                    content: "# Needle\n\nUse **needle** and [link](https://example.com)",
                ),
            ],
            streamingAssistantContent: "needle stream",
        )
    }

    func makeOpenSetupState(
        catalogRows: [AiModelCatalogRow],
        summary: AiChatCurrentContextSnapshot,
    ) -> AiChatSetupState {
        AiChatSetupState(
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
    }

    func applyOpenSetupState(
        _ state: inout AiChatFeature.State,
        catalogRows: [AiModelCatalogRow],
        summary: AiChatCurrentContextSnapshot,
    ) {
        state.sessionID = nil
        state.sessionStatus = .idle
        state.currentContext = summary
        state.transcriptHistory = []
        state.draftText = ""
        state.catalogRows = catalogRows
        state.modelListState = .loaded(makeProviderModels())
        state.selectedModelHandle = nil
        state.selectedThinking = nil
        state.unavailableSelectedModelHandle = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .idle
    }

    func assertOpenContextualChatSurface(_ state: AiChatFeature.State) {
        XCTAssertEqual(state.currentContextSummaryDisplayModel.title, "Four files selected")
        XCTAssertEqual(state.currentContextSummaryDisplayModel.detail, "1 reference · 1 item · 1 attachment")
        XCTAssertEqual(state.connectionState, .unconnected(.init(
            title: "Connect an AI provider",
            detail: "Set up a provider in Settings to chat with this context.",
            fixLabel: "Open Settings",
        )))
        if case let .unconnected(connection, summaryDisplay) = state.surfaceState {
            XCTAssertEqual(connection.fixLabel, "Open Settings")
            XCTAssertEqual(summaryDisplay.title, "Four files selected")
        } else {
            XCTFail("Expected unconnected surface state")
        }
        XCTAssertEqual(state.skeletonDisplayModel.headerTitle, "Chat")
        XCTAssertEqual(state.chatInputDisplayModel.placeholder, "Ask anything…")
        XCTAssertEqual(state.chatInputDisplayModel.modelLabel, "Select model")
        XCTAssertEqual(state.chatInputDisplayModel.effortLabel, "Select model")
        XCTAssertFalse(state.chatInputDisplayModel.canSubmit)
        XCTAssertFalse(state.canSubmit)
        XCTAssertEqual(state.modelFieldLabel, "Model")
        XCTAssertEqual(state.modelCatalogState.rows.first?.label.title, "GPT-4.1 Mini")
        XCTAssertNil(state.modelCatalogState.rows.first?.label.subtitle)
        XCTAssertNil(state.modelCatalogState.rows.first?.providerBadge)
        XCTAssertNil(state.selectedModelDisplayModel)
        XCTAssertNil(state.selectedModelHandle)
    }

    func makeSubmitFixture() -> CBW001SubmitFixture {
        let persistence = AiChatSessionPersistenceSpy()
        let driver = CBW001ProviderDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let fixedMs: Int64 = 1_700_000_000_100
        let expectedAssistantMessage = "Hello"
        let providerClient = AiChatProviderExecutionClient(execute: { request, credential in
            AsyncThrowingStream { continuation in
                Task {
                    await driver.append(request: request, credential: credential)
                    continuation.yield(.started(context: request.context))
                    continuation.yield(.delta(context: request.context, text: "Hel"))
                    continuation.yield(.delta(context: request.context, text: "lo"))
                    continuation.yield(.final(response: AiChatResponse(
                        context: request.context,
                        assistantMessage: AiChatMessage(role: .assistant, content: expectedAssistantMessage),
                        completedAtMs: 0,
                    )))
                    continuation.finish()
                }
            }
        })
        return CBW001SubmitFixture(
            persistence: persistence,
            driver: driver,
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            credential: credential,
            sessionID: sessionID,
            fixedMs: fixedMs,
            expectedAssistantMessage: expectedAssistantMessage,
            providerClient: providerClient,
        )
    }

    func makeSubmitStore(fixture: CBW001SubmitFixture) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
        TestStore(initialState: AiChatFeature.State(
            sessionID: fixture.sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: fixture.catalogRows,
            selectedModelHandle: fixture.selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixture.fixedMs))
            $0.aiChatExecutionClient = .live(providerExecutionClient: fixture.providerClient)
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in await fixture.persistence.save(snapshot) },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: {
                    let providerRecord = makeProviderRecord(provider: .openai, credential: fixture.credential)
                    return makeConnectionsFile(providers: [providerRecord])
                },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
    }

    func applySubmitStartedState(
        _ state: inout AiChatFeature.State,
        selectedHandle: AiModelHandle,
        sessionID: AiChatSessionID,
        submittedAtMs: Int64,
    ) {
        state.draftText = ""
        state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello", createdAtMs: submittedAtMs)]
        state.selectedModelHandle = selectedHandle
        state.lockedModelHandle = selectedHandle
        state.lastExecutionFailure = nil
        state.streamingAssistantDraft = nil
        state.transcriptAutoScrollVersion = 1
        XCTAssertEqual(state.sessionID, sessionID)
        XCTAssertFalse(state.canSubmit)
    }

    func receiveSuccessfulSubmitEvents(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        lock: AiChatRequestLock,
        fixture: CBW001SubmitFixture,
    ) async -> AiChatRequestLock {
        let rawResponse = AiChatResponse(
            context: lock.request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: fixture.expectedAssistantMessage),
            completedAtMs: 0,
        )
        let firstDeltaLock = lock.recordingDelta(at: fixture.fixedMs)
        let secondDeltaLock = firstDeltaLock.recordingDelta(at: fixture.fixedMs)
        await store.receive(.executionEvent(.started(context: lock.request.context)))
        await store.receive(.executionEvent(.delta(context: lock.request.context, text: "Hel"))) { state in
            state.streamingAssistantDraft = "Hel"
            state.executionPhase = .processing(firstDeltaLock)
            state.transcriptAutoScrollVersion = 2
        }
        await store.receive(.executionEvent(.delta(context: lock.request.context, text: "lo"))) { state in
            state.streamingAssistantDraft = "Hello"
            state.executionPhase = .processing(secondDeltaLock)
            state.transcriptAutoScrollVersion = 3
        }
        await store.receive(.executionEvent(.final(response: rawResponse))) { state in
            state.transcriptHistory = self.submitCompletedTranscript(
                assistant: fixture.expectedAssistantMessage,
                timestampMs: fixture.fixedMs,
            )
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.executionPhase = .completed(secondDeltaLock.recordingTerminal(
                at: fixture.fixedMs,
                failure: nil,
                wasCancelled: false,
            ))
            state.transcriptAutoScrollVersion = 4
        }
        return secondDeltaLock.recordingTerminal(at: fixture.fixedMs, failure: nil, wasCancelled: false)
    }

    func assertSuccessfulSubmitResult(
        store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        lock: AiChatRequestLock,
        completedLock: AiChatRequestLock,
        fixture: CBW001SubmitFixture,
    ) async {
        let recorded = await fixture.driver.snapshot()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.0.context.model, fixture.selectedHandle)
        XCTAssertEqual(recorded.first?.1, fixture.credential)
        XCTAssertEqual(fixture.persistence.snapshots.count, 2)
        XCTAssertEqual(
            fixture.persistence.snapshots.first?.transcriptHistory,
            [AiChatMessage(role: .user, content: "Hello", createdAtMs: fixture.fixedMs)],
        )
        XCTAssertEqual(
            fixture.persistence.snapshots.last?.transcriptHistory,
            submitCompletedTranscript(assistant: fixture.expectedAssistantMessage, timestampMs: fixture.fixedMs),
        )
        XCTAssertEqual(fixture.persistence.snapshots.last?.lastRequestID, lock.request.context.requestID)
        XCTAssertEqual(fixture.persistence.snapshots.last?.lastRunID, lock.request.context.runID)
        XCTAssertEqual(store.state.executionPhase, .completed(completedLock))
        XCTAssertEqual(store.state.executionPhase.lock?.observabilitySummary.submittedAtMs, fixture.fixedMs)
        XCTAssertEqual(store.state.executionPhase.lock?.observabilitySummary.terminalAtMs, fixture.fixedMs)
        XCTAssertEqual(store.state.transcriptHistory.first?.createdAtMs, fixture.fixedMs)
        XCTAssertEqual(store.state.transcriptHistory.last?.createdAtMs, fixture.fixedMs)
        XCTAssertEqual(fixture.persistence.snapshots.first?.transcriptHistory.last?.createdAtMs, fixture.fixedMs)
        XCTAssertEqual(fixture.persistence.snapshots.last?.transcriptHistory.last?.createdAtMs, fixture.fixedMs)
        XCTAssertNil(store.state.streamingAssistantDraft)
    }

    func makeCompletedStatusState() -> AiChatFeature.State {
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111120"))
        let requestContext = makeRequestContext(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000120")),
            runID: AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000121")),
            model: selectedHandle,
            selectedRow: catalogRows[0],
            selectedModel: models[0],
        )
        let request = AiChatRequest(context: requestContext, messages: [AiChatMessage(role: .user, content: "Hello")])
        let completedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        ).recordingTerminal(at: 1_700_000_000_500, failure: nil, wasCancelled: false)
        return AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: submitCompletedTranscript(assistant: "Hi"),
            draftText: "Second message",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .completed(completedLock),
        )
    }

    func makeStreamFixture(
        draftText: String,
        fixedMs: Int64,
        transcriptHistory: [AiChatMessage] = [],
        persistence: AiChatSessionPersistenceSpy? = nil,
    ) -> CBW001StreamFixture {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111112"))
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: transcriptHistory,
            draftText: draftText,
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in stream.stream(for: request) })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    guard let persistence else { return snapshot }
                    return await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }
        return CBW001StreamFixture(
            stream: stream,
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            fixedMs: fixedMs,
            store: store,
        )
    }

    func makeSubmitLock(
        request: AiChatRequest,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle,
    ) -> AiChatRequestLock {
        makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
    }

    func makeRegenerateLock(
        request: AiChatRequest,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle,
    ) -> AiChatRequestLock {
        makeRequestLock(
            kind: .regenerate,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: 1,
        )
    }

    func applyProcessingFailureStartedState(
        _ state: inout AiChatFeature.State,
        selectedHandle: AiModelHandle,
        submittedAtMs: Int64,
    ) {
        state.draftText = ""
        state.transcriptHistory = [
            AiChatMessage(role: .user, content: "Partial failure", createdAtMs: submittedAtMs),
        ]
        state.lockedModelHandle = selectedHandle
        state.streamingAssistantDraft = nil
    }

    func receiveProcessingFailureEvents(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        stream: AiChatExecutionStreamDriver,
        request: AiChatRequest,
        lock: AiChatRequestLock,
        fixedMs: Int64,
    ) async {
        stream.yield(.delta(context: request.context, text: "Hel"))
        await store.receive(.executionEvent(.delta(context: request.context, text: "Hel"))) { state in
            state.streamingAssistantDraft = "Hel"
            state.executionPhase = .processing(lock.recordingDelta(at: fixedMs))
        }
        stream.yield(.failed(context: request.context, reason: .transportError))
        await store.receive(.executionEvent(.failed(context: request.context, reason: .transportError))) { state in
            state.lockedModelHandle = nil
            state.lastExecutionFailure = .transportError
            state.executionPhase = .failed(
                lock.recordingDelta(at: fixedMs).recordingTerminal(
                    at: fixedMs,
                    failure: .transportError,
                    wasCancelled: false,
                ),
                .transportError,
            )
        }
    }

    func assertProcessingFailureResult(_ state: AiChatFeature.State, submittedAtMs: Int64) {
        XCTAssertEqual(state.streamingAssistantDraft, "Hel")
        XCTAssertEqual(state.transcriptHistory, [
            AiChatMessage(role: .user, content: "Partial failure", createdAtMs: submittedAtMs),
        ])
        XCTAssertEqual(state.requestStatusText, "The chat service response could not be read.")
        XCTAssertEqual(state.streamingAssistantDisplayModel?.content, "Hel")
        XCTAssertEqual(state.streamingAssistantDisplayModel?.title, "GPT-4.1 Mini")
        XCTAssertNil(state.streamingAssistantDisplayModel?.thinkingLabel)
        XCTAssertEqual(state.streamingAssistantDisplayModel?.failure, .transportError)
        XCTAssertEqual(state.streamingAssistantDisplayModel?.acceptedChunkRevision, 1)
    }

    func applyCancelStartedState(
        _ state: inout AiChatFeature.State,
        selectedHandle: AiModelHandle,
        submittedAtMs: Int64,
    ) {
        state.draftText = ""
        state.transcriptHistory = [
            AiChatMessage(role: .user, content: "Cancel me", createdAtMs: submittedAtMs),
        ]
        state.lockedModelHandle = selectedHandle
        state.streamingAssistantDraft = nil
    }

    func receiveCancelStreamingDelta(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        stream: AiChatExecutionStreamDriver,
        request: AiChatRequest,
        lock: AiChatRequestLock,
        fixedMs: Int64,
    ) async -> AiChatRequestLock {
        let streamingLock = lock.recordingDelta(at: fixedMs)
        XCTAssertEqual(store.state.executionPhase, .processing(lock))
        stream.yield(.delta(context: request.context, text: "Hel"))
        await store.receive(.executionEvent(.delta(context: request.context, text: "Hel"))) { state in
            state.streamingAssistantDraft = "Hel"
            state.executionPhase = .processing(streamingLock)
        }
        return streamingLock
    }

    func sendCancelAndLateTerminalEvents(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        request: AiChatRequest,
        streamingLock: AiChatRequestLock,
        fixedMs: Int64,
    ) async {
        await store.send(.cancelTapped) { state in
            state.lockedModelHandle = nil
            state.streamingAssistantDraft = nil
            state.executionPhase = .cancelled(streamingLock.recordingTerminal(
                at: fixedMs,
                failure: .cancelled,
                wasCancelled: true,
            ))
        }
        await store.send(.executionEvent(.delta(context: request.context, text: "lo")))
        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "late final"),
            completedAtMs: fixedMs,
        ))))
        await store.send(.executionEvent(.failed(context: request.context, reason: .unknown)))
    }

    func assertCancelResult(_ state: AiChatFeature.State, streamingLock: AiChatRequestLock, fixedMs: Int64) {
        let assistantMessages = state.transcriptHistory.filter { $0.role == .assistant }
        XCTAssertTrue(assistantMessages.isEmpty)
        XCTAssertEqual(state.transcriptHistory.first?.createdAtMs, fixedMs)
        XCTAssertEqual(state.transcriptHistory.count, 1)
        XCTAssertNil(state.lockedModelHandle)
        XCTAssertNil(state.lastExecutionFailure)
        XCTAssertNil(state.streamingAssistantDraft)
        XCTAssertEqual(
            state.executionPhase,
            .cancelled(streamingLock.recordingTerminal(at: fixedMs, failure: .cancelled, wasCancelled: true)),
        )
    }

    func applyRegenerateStartedState(_ state: inout AiChatFeature.State, selectedHandle: AiModelHandle) {
        state.selectedModelHandle = selectedHandle
        state.lockedModelHandle = selectedHandle
        state.lastExecutionFailure = nil
        state.streamingAssistantDraft = nil
    }

    func assertRegenerateRequest(
        _ request: AiChatRequest,
        store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        lock: AiChatRequestLock,
    ) {
        XCTAssertEqual(request.messages, [
            AiChatMessage(role: .user, content: "Hello", createdAtMs: 1_699_999_999_900),
        ])
        XCTAssertEqual(lock.persistenceTranscriptHistory.first?.createdAtMs, 1_699_999_999_900)
        XCTAssertEqual(store.state.executionPhase, .processing(lock))
    }

    func receiveRegenerateFinal(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        stream: AiChatExecutionStreamDriver,
        request: AiChatRequest,
        lock: AiChatRequestLock,
        fixedMs: Int64,
    ) async {
        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "New answer"),
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = self.regeneratedTranscript
            state.lockedModelHandle = nil
            state.executionPhase = .completed(lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false))
        }
    }

    func submitCompletedTranscript(assistant: String, timestampMs: Int64? = nil) -> [AiChatMessage] {
        [
            AiChatMessage(role: .user, content: "Hello", createdAtMs: timestampMs),
            AiChatMessage(role: .assistant, content: assistant, createdAtMs: timestampMs),
        ]
    }

    func assertFailureRecovery(reason: AiChatExecutionFailure, sessionIDRaw: String) async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let selectedHandle = catalogRows[0].handle
        let prompt = "Retry me"
        let sessionID = AiChatSessionID(rawValue: makeUUID(sessionIDRaw))
        let fixedMs: Int64 = 1_700_000_001_100

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: prompt,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = selectedHandle
            state.streamingAssistantDraft = nil
        }

        guard let request = stream.requests.first else {
            return XCTFail("Expected execution request")
        }

        let failedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        ).recordingTerminal(at: fixedMs, failure: reason, wasCancelled: false)

        stream.yield(.failed(context: request.context, reason: reason))

        await store.receive(.executionEvent(.failed(context: request.context, reason: reason))) { state in
            state.lockedModelHandle = nil
            state.lastExecutionFailure = reason
            state.executionPhase = .failed(failedLock, reason)
        }

        if case .ready = store.state.surfaceState {
        } else {
            XCTFail("Expected ready surface state after failure")
        }

        XCTAssertEqual(store.state.requestStatusText, reason.displayMessage)
        XCTAssertEqual(store.state.lastExecutionFailure, reason)

        await store.send(.errorRecoveryTapped)

        guard let retryRequest = stream.requests.last, stream.requests.count == 2 else {
            return XCTFail("Expected a retry request")
        }

        let retryLock = makeRequestLock(
            kind: .regenerate,
            request: retryRequest,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        XCTAssertEqual(retryRequest.messages, [
            AiChatMessage(role: .user, content: prompt, createdAtMs: fixedMs),
        ])
        XCTAssertEqual(store.state.executionPhase, .processing(retryLock))
        XCTAssertEqual(store.state.lockedModelHandle, selectedHandle)
        XCTAssertNil(store.state.lastExecutionFailure)

        stream.finish(at: 1)
        await store.finish()
    }

    private func makeSelectableOutputHarness(
        text: String,
        blockID: AiChatMarkdownDocument.BlockID = .init(rawValue: "hosted-block"),
        width: CGFloat = 240,
        allowsHorizontalOverflow: Bool = false,
        sizingMode: AiChatSelectableOutputText.SizingMode = .expandsToFillWidth,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil,
        contextMenuActions: [AiChatOutputContextMenuAction] = [],
        attributedText: NSAttributedString? = nil,
    ) -> (window: NSWindow, coordinator: AiChatSelectableOutputText.Coordinator) {
        let coordinator = AiChatSelectableOutputText.Coordinator()
        coordinator.scrollView.frame = NSRect(x: 0, y: 0, width: width, height: 120)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.scrollView
        coordinator.update(
            blockID: blockID,
            attributedText: attributedText ?? NSAttributedString(string: text),
            allowsHorizontalOverflow: allowsHorizontalOverflow,
            sizingMode: sizingMode,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue,
            contextMenuActions: contextMenuActions,
        )
        coordinator.scrollView.layoutSubtreeIfNeeded()
        return (window, coordinator)
    }

    private func assertStoredMessageViewIdentity(raw: String) {
        let firstSession = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
        let secondSession = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
        let originalIdentity = AiChatStoredMessageViewIdentity(
            sessionID: nil,
            index: 0,
            message: .init(role: .assistant, content: raw),
        )
        XCTAssertEqual(
            originalIdentity,
            AiChatStoredMessageViewIdentity(
                sessionID: nil,
                index: 0,
                message: .init(role: .assistant, content: raw),
            ),
        )
        XCTAssertNotEqual(
            originalIdentity,
            AiChatStoredMessageViewIdentity(
                sessionID: nil,
                index: 0,
                message: .init(role: .assistant, content: "replacement"),
            ),
        )
        XCTAssertNotEqual(
            AiChatStoredMessageViewIdentity(
                sessionID: .init(rawValue: firstSession),
                index: 0,
                message: .init(role: .assistant, content: raw),
            ),
            AiChatStoredMessageViewIdentity(
                sessionID: .init(rawValue: secondSession),
                index: 0,
                message: .init(role: .assistant, content: raw),
            ),
        )
    }

    private func makeAssistantMarkdownHarness(
        source: String,
        width: CGFloat,
    ) -> (window: NSWindow, hostingView: NSView) {
        let renderSession = AiChatAssistantMarkdownRenderSession(highlightingClient: .testing(
            coalescingDelay: .zero,
            supportedLanguages: { [] },
            highlight: { _, _, _ in [] },
        ))
        let presentation = AiChatTranscriptSearchPresentation(query: "", renderedRows: [])
        let view = AiChatAssistantMarkdownText(
            content: source,
            transcriptRow: .message(index: 0),
            searchPresentation: presentation,
            currentSearchMatch: nil,
            renderSession: renderSession,
        )
        .frame(width: width)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        return (window, hostingView)
    }

    /// production `AiChatMessageRow.userMessage` HStack { Spacer; AiChatUserMessageBubble } 레이아웃을
    /// NSHostingView에 호스팅한다. Canonical bubble 레이아웃 seam을 통해 실제 SwiftUI proposal 폭에서
    /// 자연 폭 hug와 cap/wrap 동작을 검증한다.
    private func makeUserMessageBubbleHarness(
        text: String,
        hostWidth: CGFloat,
    ) -> (window: NSWindow, hostingView: NSView) {
        let renderSession = AiChatAssistantMarkdownRenderSession(highlightingClient: .testing(
            coalescingDelay: .zero,
            supportedLanguages: { [] },
            highlight: { _, _, _ in [] },
        ))
        let transcriptRow = AiChatTranscriptRowDiscriminator.message(index: 0)
        let blockID = AiChatMarkdownDocument.BlockID(rawValue: "user-message-0")
        renderSession.registerSelectionProjection(
            presentationID: blockID,
            plainText: text,
            searchText: text,
            transcriptRow: transcriptRow,
            blockIndex: 0,
        )
        let attributedText = AiChatAssistantMarkdownAttributedText.make(
            text: text,
            inlineIntents: [],
            matchOffsets: [],
            currentMatchOffsets: nil,
            appliesHangulWordPriorityLineBreak: true,
        )
        let view = HStack {
            Spacer(minLength: 16)
            AiChatUserMessageBubble(
                blockID: blockID,
                attributedText: attributedText,
                rawMessageContent: text,
                renderSession: renderSession,
                transcriptRow: transcriptRow,
            )
        }
        .frame(width: hostWidth)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: hostWidth, height: 600)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        return (window, hostingView)
    }

    private func makeTwelveColumnTableSource() -> String {
        let headers = (1 ... 12).map { "H\($0)" }.joined(separator: " | ")
        let delimiter = Array(repeating: "---", count: 12).joined(separator: " | ")
        let values = (1 ... 12).map { "V\($0)" }.joined(separator: " | ")
        return "| \(headers) |\n| \(delimiter) |\n| \(values) |"
    }

    private func descendantScrollViews(in view: NSView) -> [NSScrollView] {
        let descendants = view.subviews.flatMap(descendantScrollViews(in:))
        return (view as? NSScrollView).map { [$0] + descendants } ?? descendants
    }

    private func descendantTextViews(in view: NSView) -> [NSTextView] {
        let descendants = view.subviews.flatMap(descendantTextViews(in:))
        return (view as? NSTextView).map { [$0] + descendants } ?? descendants
    }

    private func selectedSubstring(in textView: NSTextView) throws -> String {
        let selection = try XCTUnwrap(AiChatMarkdownDocument.PlainSelectionRange(textView.selectedRange()))
        let range = try XCTUnwrap(
            selection.searchRange(in: textView.string, invalidRangePolicy: .discard),
        )
        return try XCTUnwrap(range.substring(in: textView.string))
    }

    /// 대기 중인 DispatchQueue.main.async 블록을 deterministic하게 비운다.
    /// arbitrary sleep 없이 nested async restore 흐름을 끝까지 실행한다.
    private func flushMainRunLoop(_ iterations: Int = 8) {
        for _ in 0 ..< iterations {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private func makeContextMenuEvent(for textView: NSTextView) throws -> NSEvent {
        let point = NSPoint(x: textView.bounds.midX, y: textView.bounds.midY)
        let windowPoint = textView.convert(point, to: nil)
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: textView.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1,
        ))
    }

    private func makeTranscriptScrollHarnessScrollView(
        documentHeight: CGFloat,
        viewportHeight: CGFloat,
    ) -> NSScrollView {
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 240, height: viewportHeight),
        )
        let documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 240, height: documentHeight),
        )
        scrollView.documentView = documentView
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: 0))
        return scrollView
    }
}

@MainActor
private final class SelectableOutputFirstResponderAcceptingView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

@MainActor
private final class SelectableOutputFallbackResponder: NSResponder {
    private(set) var didReceiveCopy = false
    private(set) var didReceiveSelectAll = false
    private(set) var didReceiveUndo = false

    @objc
    func copy(_: Any?) {
        didReceiveCopy = true
    }

    override func selectAll(_: Any?) {
        didReceiveSelectAll = true
    }

    @objc
    func undo(_: Any?) {
        didReceiveUndo = true
    }
}
