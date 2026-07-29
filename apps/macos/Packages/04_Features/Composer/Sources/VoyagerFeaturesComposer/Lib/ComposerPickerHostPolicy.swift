enum ComposerPickerControl: Equatable {
    case scope
    case property
    case `operator`
    case boolean
    case token
    case date
    case value
    case unit
}

enum ComposerPickerHost: Equatable {
    case customPanel
    case popover
    case inline
    case nativeMenu
    case anchoredDropdown
}

enum ComposerPickerPresentationOwner: Equatable {
    case fileManagerComposer
}

enum ComposerPickerHostPolicy {
    static func host(for control: ComposerPickerControl) -> ComposerPickerHost {
        switch control {
        case .scope:
            .customPanel
        case .property:
            .nativeMenu
        case .token:
            .anchoredDropdown
        case .date:
            .anchoredDropdown
        case .value:
            .inline
        case .operator, .boolean, .unit:
            .nativeMenu
        }
    }

    static func presentationOwner(for _: ComposerPickerControl) -> ComposerPickerPresentationOwner {
        .fileManagerComposer
    }
}
