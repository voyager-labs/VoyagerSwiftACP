import CasePaths
import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

extension TestStore where State == FileManagerFeature.State, Action == FileManagerWindowAction {
    func sendTabContent(
        _ action: FileManagerContentFeature.Action,
        assert updateStateToExpectedResult: ((_ state: inout State) throws -> Void)? = nil,
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) async {
        guard let tabID = state.contentTabs.activeTabID else {
            XCTFail("Active content tab is required", file: filePath, line: line)
            return
        }
        await send(
            .tabContent(tabID: tabID, action: action),
            assert: updateStateToExpectedResult,
            fileID: fileID,
            file: filePath,
            line: line,
            column: column,
        )
    }

    func receiveTabContent<Value: Equatable>(
        _ casePath: CaseKeyPath<FileManagerContentFeature.Action, Value>,
        _ expectedValue: Value,
        assert updateStateToExpectedResult: ((_ state: inout State) throws -> Void)? = nil,
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) async {
        await receive(
            { action in
                guard case let .tabContent(_, contentAction) = action,
                      let receivedValue = contentAction[case: casePath]
                else { return false }
                return receivedValue == expectedValue
            },
            assert: updateStateToExpectedResult,
            fileID: fileID,
            file: filePath,
            line: line,
            column: column,
        )
    }

    func receiveTabContent(
        _ casePath: CaseKeyPath<FileManagerContentFeature.Action, some Any>,
        assert updateStateToExpectedResult: ((_ state: inout State) throws -> Void)? = nil,
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) async {
        await receive(
            { action in
                guard case let .tabContent(_, contentAction) = action else { return false }
                return contentAction[case: casePath] != nil
            },
            assert: updateStateToExpectedResult,
            fileID: fileID,
            file: filePath,
            line: line,
            column: column,
        )
    }

    func receiveTabContentCoreBatch(
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) async {
        await receive(
            { action in
                guard case let .tabContent(_,
                                           .entryViewLayout(.entryOperations(.loading(.streamEvent(event))))) = action
                else { return false }
                switch event.event {
                case .coreBatch, .coreFinished:
                    break
                case .metadataPatches:
                    return false
                }
                return true
            },
            fileID: fileID,
            file: filePath,
            line: line,
            column: column,
        )
        await receiveTabContent(\.entryViewLayout.view.applyContentProjection)
    }
}
