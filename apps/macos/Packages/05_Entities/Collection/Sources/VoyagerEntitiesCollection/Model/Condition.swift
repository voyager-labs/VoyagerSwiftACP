import Foundation
import VoyagerShared

public struct Condition: Equatable, Sendable {
    public struct Property: Equatable, Sendable {
        public let key: String
        public let label: String
        public let type: SystemPropertyTypeKey
        public let unitContract: UnitContract?
        public let operatorOptions: [OperatorOption]

        public init(
            key: String,
            label: String,
            type: SystemPropertyTypeKey,
            unitContract: UnitContract?,
            operatorOptions: [OperatorOption],
        ) {
            self.key = key
            self.label = label
            self.type = type
            self.unitContract = unitContract
            self.operatorOptions = operatorOptions
        }
    }

    public struct UnitOption: Equatable, Sendable {
        public let code: String
        public let label: String
        public let factorToCanonical: Decimal

        public init(code: String, label: String, factorToCanonical: Decimal) {
            self.code = code
            self.label = label
            self.factorToCanonical = factorToCanonical
        }
    }

    public struct UnitContract: Equatable, Sendable {
        public let canonicalUnit: String
        public let options: [UnitOption]
        public let defaultDisplayUnit: String

        public init(canonicalUnit: String, options: [UnitOption], defaultDisplayUnit: String) {
            self.canonicalUnit = canonicalUnit
            self.options = options
            self.defaultDisplayUnit = defaultDisplayUnit
        }

        init?(systemPropertyUnitSpec: SystemPropertyUnitSpec) {
            let options = systemPropertyUnitSpec.units.compactMap { option -> UnitOption? in
                guard let factor = Decimal(
                    string: option.factorToCanonical,
                    locale: Locale(identifier: "en_US_POSIX"),
                ) else {
                    return nil
                }
                return UnitOption(code: option.code, label: option.label, factorToCanonical: factor)
            }
            guard options.count == systemPropertyUnitSpec.units.count else { return nil }
            self.init(
                canonicalUnit: systemPropertyUnitSpec.canonicalUnit,
                options: options,
                defaultDisplayUnit: systemPropertyUnitSpec.defaultDisplayUnit,
            )
        }
    }

    public struct OperatorOption: Equatable, Sendable {
        public let code: String
        public let label: String

        public init(code: String, label: String) {
            self.code = code
            self.label = label
        }
    }

    public struct Operation: Equatable, Sendable {
        public let code: String
        public let label: String
        public let valueContract: ValueContract

        public init(code: String, label: String, valueContract: ValueContract) {
            self.code = code
            self.label = label
            self.valueContract = valueContract
        }
    }

    public struct ValueContract: Equatable, Sendable {
        public let shape: ValueShape
        public let count: ValueCount
        public let input: ValueInputKind

        public init(shape: ValueShape, count: ValueCount, input: ValueInputKind) {
            self.shape = shape
            self.count = count
            self.input = input
        }
    }

    public enum ValueInputKind: Equatable, Sendable {
        case none
        case singleText
        case listText
        case singleNumber
        case listNumber
        case singleDate
        case rangeDate
        case rangeNumber
        case toggle

        init?(registryValue: String) {
            switch registryValue {
            case "none": self = .none
            case "singleText": self = .singleText
            case "listText": self = .listText
            case "singleNumber": self = .singleNumber
            case "listNumber": self = .listNumber
            case "singleDate": self = .singleDate
            case "rangeDate": self = .rangeDate
            case "rangeNumber": self = .rangeNumber
            case "toggle": self = .toggle
            default: return nil
            }
        }
    }

    public enum Availability: Equatable, Sendable {
        case available
        case unsupportedProperty
        case unsupportedOperator
        case invalidPersistedValue
    }

    @_spi(Testing)
    public init(
        property: Property,
        operation: Operation?,
        values: [String]?,
        availability: Availability,
        opaqueSource: CollectionCondition?,
    ) {
        self.property = property
        self.operation = operation
        self.values = values
        self.availability = availability
        self.opaqueSource = opaqueSource
    }

    public let property: Property
    public let operation: Operation?
    public let values: [String]?
    public let availability: Availability
    public let opaqueSource: CollectionCondition?

    public var isExecutionReady: Bool {
        guard availability == .available, let operation else { return false }

        switch operation.valueContract.count {
        case .fixed(0):
            return values == nil || values?.isEmpty == true
        case let .fixed(count):
            return values?.count == count
        case .multiple:
            return values?.isEmpty == false
        }
    }

    public var isPersistable: Bool {
        switch availability {
        case .available:
            isExecutionReady
        case .unsupportedProperty, .unsupportedOperator, .invalidPersistedValue:
            opaqueSource != nil
        }
    }
}
