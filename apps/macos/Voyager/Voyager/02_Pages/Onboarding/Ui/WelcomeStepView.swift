import ComposableArchitecture
import SwiftUI

struct WelcomeStepView: View {
    let store: StoreOf<WelcomeFeature>
    var isCentered: Bool = false

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { _ in
            EmptyView()
                .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
        })
    }
}
