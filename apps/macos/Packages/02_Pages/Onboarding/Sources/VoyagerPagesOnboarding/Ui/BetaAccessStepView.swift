import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesAccess

// Legacy BetaAccessStepView — Task 8 에서 삭제 예정
// UnlockAccessStepView 로 교체됨
struct BetaAccessStepView: View {
    let store: StoreOf<UnlockAccessFeature>

    var body: some View {
        UnlockAccessStepView(store: store)
    }
}
