import ComposableArchitecture
import VoyagerFeaturesUpdateVersion

enum MenuCommandsAction: ViewAction, Sendable {
    case view(View)
    case delegate(Delegate)

    enum View: Sendable {
        case app(MenuCommandItem.AppCommand)
        case viewCommand(MenuCommandItem.ViewCommand)
        case edit(MenuCommandItem.EditCommand)
    }

    enum Delegate: Sendable {
        case windowManager(WindowManagerAction)
        case updater(UpdaterAction)
    }
}
