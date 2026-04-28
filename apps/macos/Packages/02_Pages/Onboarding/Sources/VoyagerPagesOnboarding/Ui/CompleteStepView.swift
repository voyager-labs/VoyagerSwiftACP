import ComposableArchitecture
import SwiftUI

struct CompleteStepView: View {
    let store: StoreOf<CompleteFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(alignment: .center, spacing: 12) {
                if viewStore.isOpeningWindow {
                    ProgressView()
                        .controlSize(.small)
                }

                if let error = viewStore.openWindowError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                    Button("Retry") {
                        viewStore.send(.retryTapped)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        })
    }
}
