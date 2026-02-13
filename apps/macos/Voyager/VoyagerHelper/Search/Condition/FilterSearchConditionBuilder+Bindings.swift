import StructuredQueries

extension FilterSearchConditionBuilder {
    func bind(_ value: JSONValue?) -> QueryFragment {
        QueryFragment.bind(binding(from: value))
    }

    func bind(_ value: QueryBinding) -> QueryFragment {
        QueryFragment.bind(value)
    }

    func bindMany(_ values: [QueryBinding]) -> QueryFragment {
        QueryFragment.joinWithComma(values.map { QueryFragment.bind($0) })
    }

    func binding(from value: JSONValue?) -> QueryBinding {
        guard let value else { return .null }
        switch value {
        case let .string(text):
            return .text(text)
        case let .number(number):
            return .double(number)
        case let .bool(bool):
            return .bool(bool)
        case .array, .object, .null:
            return .null
        }
    }

    func columnFragment(for key: String) -> QueryFragment {
        switch key {
        case "id":
            "\(FilterSearchEntryTable.id)"
        case "path":
            "\(FilterSearchEntryTable.path)"
        case "name_full":
            "\(FilterSearchEntryTable.nameFull)"
        case "extension":
            "\(FilterSearchEntryTable.fileExtension)"
        case "size":
            "\(FilterSearchEntryTable.size)"
        case "file_kind":
            "\(FilterSearchEntryTable.fileKind)"
        case "modification_date":
            "\(FilterSearchEntryTable.modificationDate)"
        case "original_metadata":
            "\(FilterSearchEntryTable.originalMetadata)"
        default:
            "\(quote: key)"
        }
    }
}
