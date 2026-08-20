import AppKit
import ApplicationServices
import ComposableArchitecture
import SwiftUI
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class FileManagerWindowAiChatAttachmentPickerRoutingTests: XCTestCase {
    func testAiChatHostsExposeAttachmentPickerOnlyInInspector() async throws {
        // 프로덕션 TCA AiChat 뷰를 호스팅하는 동안 발현되는 Perception "not being tracked" 디버그
        // 경고를 의도된 것으로 표기한다. 이 경고는 `#if DEBUG` 와 macOS 14+ Observation 호스트에서만
        // 발생하는 swift-perception 진단으로, 프로덕션(RELEASE/13.5) 동작에는 영향이 없다. 테스트는
        // PerceptionCore 의 macOS-14 전용 심볼을 직접 참조하지 않으므로 13.5 deployment target 으로
        // 링크되며, 이 뷰의 AX 계약(Content 는 attachment picker 를 노출하지 않는다)을 그대로 검증한다.
        // `issueMatcher` 로 Perception 진단 메시지일 때만 예상 실패로 처리하므로, Inspector 버튼
        // 노출·picker delegate 전달·Content 미노출 같은 AX assertion 이 실패하면 정상 실패로 남아
        // 회귀를 탐지한다.
        XCTExpectFailure(
            "Production AiChat TCA view emits Perception 'not being tracked' debug diagnostics only",
            options: {
                var options = XCTExpectedFailure.Options()
                options.isEnabled = true
                options.isStrict = false
                options.issueMatcher = { issue in
                    issue.compactDescription.contains("not being tracked")
                        || issue.compactDescription.contains("Perceptible state was accessed")
                }
                return options
            }(),
        )
        _ = NSApplication.shared
        // production hosting 경로와 AX 계약만 검증하며, 하위 뷰의 기존 Perception 경고는 이 테스트 범위가 아닙니다.
        let aiChatState = makeMountedAiChatState()
        var inspectorState = FileManagerInspectorFeature.State()
        inspectorState.aiChat = aiChatState
        let pickerRequest = expectation(description: "Inspector forwards the attachment picker request")
        let inspectorStore = Store(initialState: inspectorState) {
            FileManagerInspectorFeature()
            Reduce<FileManagerInspectorFeature.State, FileManagerInspectorFeature.Action> { _, action in
                guard case .delegate(.requestAttachmentPicker) = action else { return .none }
                pickerRequest.fulfill()
                return .none
            }
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        let inspectorController = FileManagerWindowMainContainerLayout.makeInspectorHosting(
            store: inspectorStore,
            isDark: false,
        )
        let inspectorWindow = makeWindow(hosting: inspectorController)
        inspectorWindow.title = "VOY-748 Inspector AX Host"
        defer {
            inspectorWindow.close()
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        inspectorWindow.makeKeyAndOrderFront(nil)
        await settleMountedView(inspectorController.view)

        let inspectorElements = try accessibilityDescendants(inWindowNamed: inspectorWindow.title)
        XCTAssertGreaterThan(inspectorElements.count, 1)
        let inspectorPicker = try XCTUnwrap(inspectorElements.first {
            accessibilityString($0, attribute: kAXRoleAttribute) == kAXButtonRole
                && accessibilityLabel(of: $0) == "Add attachment"
        }, "Inspector AX elements: \(accessibilitySummary(inspectorElements))")
        XCTAssertTrue(try XCTUnwrap(accessibilityBool(inspectorPicker, attribute: kAXEnabledAttribute)))
        XCTAssertEqual(AXUIElementPerformAction(inspectorPicker, kAXPressAction as CFString), .success)
        await fulfillment(of: [pickerRequest], timeout: 1)

        for heading in ["Current context", "Attachments"] {
            XCTAssertTrue(inspectorElements.contains {
                accessibilityLabel(of: $0) == heading
                    && accessibilityString($0, attribute: kAXRoleAttribute) == kAXHeadingRole
            })
        }

        var contentState = FileManagerContentFeature.State()
        contentState.aiChat = aiChatState
        let contentStore = Store(initialState: contentState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        let contentController = NSHostingController(rootView: FileManagerAiChatPageView(
            store: contentStore,
            chromeProps: makeAiChatChromeProps(),
            onNavigationAction: { _ in },
        ))
        let contentWindow = makeWindow(hosting: contentController)
        contentWindow.title = "VOY-748 Content AX Host"
        defer {
            contentWindow.close()
        }
        contentWindow.orderFront(nil)
        await settleMountedView(contentController.view)

        let contentElements = try accessibilityDescendants(inWindowNamed: contentWindow.title)
        XCTAssertGreaterThan(contentElements.count, 1)
        XCTAssertFalse(contentElements.contains {
            accessibilityLabel(of: $0) == "Add attachment"
        })
    }

    func testAttachmentPickerCompletionKeepsOriginSessionAcrossWindowRouting() async throws {
        let windowID = makeUUID("19191919-2222-3333-4444-000000000635")
        let sessionA = AiChatSessionID(rawValue: makeUUID("20202020-2222-3333-4444-000000000635"))
        let sessionB = AiChatSessionID(rawValue: makeUUID("21212121-2222-3333-4444-000000000635"))
        let pickerStream = AsyncStream<[URL]>.makeStream()
        let selectedURL = URL(fileURLWithPath: "/tmp/A-window-picker.txt")
        var windowState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        windowState.inspector.aiChat = AiChatFeature.State(
            sessionID: sessionA,
            sessionStatus: .active,
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: windowState)]
        initialState.focusedWindowID = windowID
        let setupB = AiChatSetupState(
            restoreSessionID: nil,
            sessionID: sessionB,
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "B draft",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.attachmentPickerClient.pickAttachments = {
                await pickerStream.stream.first(where: { _ in true }) ?? []
            }
        }
        // store.exhaustivity = .off: host origin propagation과 B attachment 불변성만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.windows(.element(
            id: windowID,
            action: .window(.delegate(.requestAttachmentPicker(sessionA))),
        )))
        await store.send(.windows(.element(
            id: windowID,
            action: .window(.inspector(.aiChat(.setup(setupB)))),
        )))
        pickerStream.continuation.yield([selectedURL])
        pickerStream.continuation.finish()
        await store.receive { action in
            guard case let .windows(.element(
                id: receivedWindowID,
                action: .window(.inspector(.aiChat(.attachmentPickerSelection(originSessionID, urls)))),
            )) = action
            else { return false }
            return receivedWindowID == windowID && originSessionID == sessionA && urls == [selectedURL]
        }

        let aiChat = try XCTUnwrap(store.state.windows[id: windowID]?.window.inspector.aiChat)
        XCTAssertEqual(aiChat.sessionID, sessionB)
        XCTAssertEqual(aiChat.draftText, "B draft")
        XCTAssertTrue(aiChat.addedAttachments.isEmpty)
    }

    func testAiChatDroppedAttachmentClearSelectionDelegateClearsContentSelection() async throws {
        let selectedEntry = makeEntry(name: "Dropped.md", fullPath: "/Users/test/Documents/Dropped.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.entries = [selectedEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id]
        let activeTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.tabContentStates[activeTabID] = initialState.content

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }
        let expectedReference = AiChatContextReference(
            kind: .reference,
            identifier: "/Users/test/Documents",
            title: "Documents",
            subtitle: "/Users/test/Documents",
            metadata: [
                "folderStructureMode": "currentFolderOnly",
                "path": "/Users/test/Documents",
                "route": "folder",
            ],
        )
        let expectedCurrentContext = AiChatCurrentContextSnapshot(
            summary: "Documents",
            references: [expectedReference],
        )
        let expectedFolderStructureKey = AiChatCurrentContextFolderStructureKey(
            source: .reference,
            canonicalPath: "/Users/test/Documents",
        )

        await store.send(.inspector(.aiChat(.delegate(.clearCurrentContextSelection))))
        await store.receive(\.inspector.delegate.clearCurrentContextSelection)
        await store.receive { action in
            guard case let .tabContent(tabID, .entryViewLayout(.internal(.applyClearSelection))) = action else {
                return false
            }
            return tabID == activeTabID
        } assert: {
            $0.content.entryViewLayout.selectedIds = []
            $0.tabContentStates[activeTabID]?.entryViewLayout.selectedIds = []
        }
        await store.receive { action in
            guard case let .tabContent(tabID, .entryViewLayout(.delegate(.selectionChanged))) = action else {
                return false
            }
            return tabID == activeTabID
        }
        await store.receive { action in
            guard case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.lifecycle(.syncSelectedEntryIDs))),
            ) = action else { return false }
            return tabID == activeTabID
        }
        await store.receive { action in
            guard case let .tabContent(tabID, .delegate(.currentContextChanged)) = action else { return false }
            return tabID == activeTabID
        }
        await store.receive(\.inspector.aiChat.currentContextChanged) {
            $0.inspector.aiChat.currentContext = expectedCurrentContext
            $0.inspector.aiChat.currentContextFolderStructureModes = [
                expectedFolderStructureKey: .currentFolderOnly,
            ]
            $0.tabInspectorStates[activeTabID]?.aiChat.currentContext = expectedCurrentContext
            $0.tabInspectorStates[activeTabID]?.aiChat.currentContextFolderStructureModes = [
                expectedFolderStructureKey: .currentFolderOnly,
            ]
        }
    }

    private func makeUUID(_ rawValue: String) -> UUID {
        guard let value = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return UUID()
        }
        return value
    }

    private func makeEntry(name: String, fullPath: String) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: (name as NSString).pathExtension,
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    private func makeMountedAiChatState() -> AiChatFeature.State {
        var state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("22222222-3333-4444-5555-000000000748")),
            sessionStatus: .active,
        )
        state.mode = .chat
        state.currentContext = AiChatCurrentContextSnapshot(
            summary: "Documents",
            references: [
                AiChatContextReference(
                    kind: .reference,
                    identifier: "/Users/test/Documents",
                    title: "Documents",
                    subtitle: "/Users/test/Documents",
                    metadata: [:],
                ),
            ],
        )
        state.addedAttachments = [
            AiChatAttachmentDraft(
                id: AiChatAttachmentID(rawValue: "mounted-attachment"),
                source: .file,
                displayTitle: "Notes.md",
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Notes.md"),
            ),
        ]
        return state
    }

    private func makeAiChatChromeProps() -> FileManagerContentChromeProps {
        FileManagerContentChromeProps(
            computerName: "Test Mac",
            breadcrumbRoots: FileManagerBreadcrumbRoots(homePath: "/Users/test", trashPath: nil),
            pathDisplayNames: [:],
            specialDirectoryIconNames: [:],
            isContextualAiChatPresented: false,
            activeTabID: nil,
            activePageAnchor: .aiChat(sessionID: "mounted-session"),
        )
    }

    private func makeWindow(hosting controller: NSHostingController<some View>) -> NSWindow {
        controller.view.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(controller.view.frame.size)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func settleMountedView(_ view: NSView) async {
        for _ in 0 ..< 8 {
            view.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
            await Task.yield()
        }
    }

    private enum AccessibilityProbeError: Error {
        case copy(String, AXError)
        case unexpectedType(String)
    }

    private func accessibilityDescendants(inWindowNamed title: String) throws -> [AXUIElement] {
        let application = AXUIElementCreateApplication(getpid())
        let windows = try accessibilityElements(application, attribute: kAXWindowsAttribute)
        let window = try XCTUnwrap(windows.first {
            accessibilityString($0, attribute: kAXTitleAttribute) == title
        }, "Self-process AX windows: \(windows.compactMap { accessibilityString($0, attribute: kAXTitleAttribute) })")
        var descendants: [AXUIElement] = []
        var pending = [window]
        var visited = Set<AXUIElement>()
        while let next = pending.popLast() {
            let identity = next
            guard visited.insert(identity).inserted else { continue }
            descendants.append(next)
            try pending.append(contentsOf: accessibilityElements(next, attribute: kAXChildrenAttribute))
        }
        return descendants
    }

    private func accessibilityElements(_ element: AXUIElement, attribute: String) throws -> [AXUIElement] {
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        switch error {
        case .success:
            guard let elements = rawValue as? [AXUIElement] else {
                throw AccessibilityProbeError.unexpectedType(attribute)
            }
            return elements
        case .attributeUnsupported, .noValue:
            return []
        default:
            throw AccessibilityProbeError.copy(attribute, error)
        }
    }

    private func accessibilityLabel(of element: AXUIElement) -> String? {
        accessibilityString(element, attribute: kAXDescriptionAttribute)
            ?? accessibilityString(element, attribute: kAXTitleAttribute)
    }

    private func accessibilityString(_ element: AXUIElement, attribute: String) -> String? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == CFStringGetTypeID()
        else { return nil }
        return rawValue as? String
    }

    private func accessibilityBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == CFBooleanGetTypeID()
        else { return nil }
        return rawValue as? Bool
    }

    private func accessibilitySummary(_ elements: [AXUIElement]) -> String {
        elements.map { element in
            let role = accessibilityString(element, attribute: kAXRoleAttribute) ?? "<nil>"
            return "\(role):\(accessibilityLabel(of: element) ?? "<nil>")"
        }
        .joined(separator: ", ")
    }
}
