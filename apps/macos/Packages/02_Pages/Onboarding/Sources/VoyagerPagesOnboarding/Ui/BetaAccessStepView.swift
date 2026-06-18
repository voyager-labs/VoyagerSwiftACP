import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesAccountAccess

// Legacy AccessStepView — Task 8 에서 삭제 예정
// UnlockAccessStepView 로 교체됨
struct AccessStepView: View {
    let store: StoreOf<AccountAccessFeature>

    var body: some View {
        UnlockAccessStepView(store: store)
    }
}
