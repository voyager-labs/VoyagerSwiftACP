import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesAccess

struct UnlockSurfaceView: View {
    let store: StoreOf<UnlockSurfaceFeature>

    var body: some View {
        WithViewStore(store, observe: \.unlockAccess, content: { viewStore in
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Voyager")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Unlock Voyager")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Your access requires reactivation.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                UnlockAccessStepView(store: store.scope(state: \.unlockAccess, action: \.unlockAccess))
                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { viewStore.send(.onAppear) }
        })
    }
}
