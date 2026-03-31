import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class EntryDropValidationContractTests: XCTestCase {
    func testValidateDropReturnsNoOpForSameParentInternalMove() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        }

        let context = EntryDropValidationContext(
            sourcePaths: ["/tmp/voyager/source.txt"],
            destinationPath: "/tmp/voyager",
            allowedOperationsRawValue: NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = .init(
                destinationPath: "/tmp/voyager",
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        await store.finish()
    }

    func testValidateDropReturnsNoOpForDescendantInternalMove() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        }

        let context = EntryDropValidationContext(
            sourcePaths: ["/tmp/voyager/folder"],
            destinationPath: "/tmp/voyager/folder/child",
            allowedOperationsRawValue: NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = .init(
                destinationPath: "/tmp/voyager/folder/child",
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        await store.finish()
    }
}
