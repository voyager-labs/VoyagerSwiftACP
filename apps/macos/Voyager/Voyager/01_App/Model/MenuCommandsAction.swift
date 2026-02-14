enum MenuCommandsAction: Equatable, Sendable {
    case perform(MenuCommandItem.Command)
    case delegate(MenuCommandsDelegateAction)
}

enum MenuCommandsDelegateAction: Equatable, Sendable {
    case dispatchToWindowManager(WindowManagerFeature.Action)
    case dispatchToUpdater(UpdaterFeature.Action)
}

extension MenuCommandsDelegateAction {
    static func == (lhs: MenuCommandsDelegateAction, rhs: MenuCommandsDelegateAction) -> Bool {
        switch (lhs, rhs) {
        case (.dispatchToWindowManager, .dispatchToWindowManager),
             (.dispatchToUpdater, .dispatchToUpdater):
            true
        default:
            false
        }
    }
}
