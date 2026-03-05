import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ValuePickerFeatureTests: XCTestCase {
    func testCommitRangeNumberClampsExtraInputsToExpectedArity() async {
        let store = TestStore(
            initialState: ValuePickerState(
                isPresented: true,
                propertyKey: "file_allocated_size",
                operatorCode: "btw",
                valueType: "number",
                valueUIKind: "rangeNumber",
                valueArity: 2,
                values: ["10", "20", "30"],
                errorMessage: nil,
                editingIndex: nil,
            ),
        ) {
            ValuePickerFeature()
        }

        await store.send(.commit)
        await store.receive(\.commitResult)
    }

    func testCommitRangeDateDoesNotCommitOnPartialInput() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "content_modified_at",
                    operatorCode: "btw",
                    valueType: "date",
                    valueUIKind: "rangeDate",
                    valueArity: 2,
                    existingValues: ["2026-02-26", ""],
                    editingIndex: 0,
                ),
            ),
        ) {
            $0.propertyKey = "content_modified_at"
            $0.operatorCode = "btw"
            $0.valueType = "date"
            $0.valueUIKind = "rangeDate"
            $0.valueArity = 2
            $0.values = ["2026-02-26", ""]
            $0.errorMessage = nil
            $0.editingIndex = 0
            $0.isPresented = true
        }

        await store.send(.commit)
    }

    func testCommitRangeDateDoesNotCommitOnToOnlyInput() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "content_modified_at",
                    operatorCode: "btw",
                    valueType: "date",
                    valueUIKind: "rangeDate",
                    valueArity: 2,
                    existingValues: ["", "2026-02-27"],
                    editingIndex: 1,
                ),
            ),
        ) {
            $0.propertyKey = "content_modified_at"
            $0.operatorCode = "btw"
            $0.valueType = "date"
            $0.valueUIKind = "rangeDate"
            $0.valueArity = 2
            $0.values = ["", "2026-02-27"]
            $0.errorMessage = nil
            $0.editingIndex = 1
            $0.isPresented = true
        }

        await store.send(.commit)
    }

    func testCommitRangeNumberShowsErrorAndResetsInvalidIndex() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "file_allocated_size",
                    operatorCode: "btw",
                    valueType: "number",
                    valueUIKind: "rangeNumber",
                    valueArity: 2,
                    existingValues: ["10", "xx"],
                    editingIndex: 1,
                ),
            ),
        ) {
            $0.propertyKey = "file_allocated_size"
            $0.operatorCode = "btw"
            $0.valueType = "number"
            $0.valueUIKind = "rangeNumber"
            $0.valueArity = 2
            $0.values = ["10", "xx"]
            $0.errorMessage = nil
            $0.editingIndex = 1
            $0.isPresented = true
        }

        await store.send(.commit) {
            $0.errorMessage = "Enter valid numbers."
            $0.values = ["10", ""]
        }
    }

    func testCommitRangeNumberDoesNotCommitOnToOnlyInput() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "file_allocated_size",
                    operatorCode: "btw",
                    valueType: "number",
                    valueUIKind: "rangeNumber",
                    valueArity: 2,
                    existingValues: ["", "20"],
                    editingIndex: 1,
                ),
            ),
        ) {
            $0.propertyKey = "file_allocated_size"
            $0.operatorCode = "btw"
            $0.valueType = "number"
            $0.valueUIKind = "rangeNumber"
            $0.valueArity = 2
            $0.values = ["", "20"]
            $0.errorMessage = nil
            $0.editingIndex = 1
            $0.isPresented = true
        }

        await store.send(.commit)
    }

    func testCommitRangeDateShowsErrorAndResetsInvalidIndex() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "content_modified_at",
                    operatorCode: "btw",
                    valueType: "date",
                    valueUIKind: "rangeDate",
                    valueArity: 2,
                    existingValues: ["2026-02-26", "invalid-date"],
                    editingIndex: 1,
                ),
            ),
        ) {
            $0.propertyKey = "content_modified_at"
            $0.operatorCode = "btw"
            $0.valueType = "date"
            $0.valueUIKind = "rangeDate"
            $0.valueArity = 2
            $0.values = ["2026-02-26", "invalid-date"]
            $0.errorMessage = nil
            $0.editingIndex = 1
            $0.isPresented = true
        }

        await store.send(.commit) {
            $0.errorMessage = "Enter valid dates."
            $0.values = ["2026-02-26", ""]
        }
    }
}
