import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

extension AccountAccessFeature {
    func sessionSyncEffect(
        intent: SessionSyncIntent,
        reason _: SyncReason,
        generation: UInt64,
    ) -> Effect<Action> {
        let retryDelays = intent == .refresh ? [Duration.seconds(5)] : Self.sessionSyncRetryDelays
        return .run { [authNetwork, continuousClock, deviceIdentityClient, retryDelays] send in
            let device: DeviceBindingRequest
            do {
                device = try DeviceBindingRequest(
                    deviceId: deviceIdentityClient.deviceId(),
                    deviceName: Host.current().localizedName,
                    appVersion: AppVersionInfo.shortVersion,
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                )
            } catch {
                await send(._sessionSyncCompleted(generation: generation, result: .failure(.upstream(0))))
                return
            }

            let requestID = UUID().uuidString
            var retryIndex = 0
            while true {
                do {
                    let result = try await authNetwork.syncSession(
                        intent: intent,
                        device: device,
                        requestID: requestID,
                    )
                    await send(._sessionSyncCompleted(generation: generation, result: .success(result)))
                    return
                } catch let error as SessionSyncError {
                    guard case .upstream = error, retryIndex < retryDelays.count else {
                        await send(._sessionSyncCompleted(generation: generation, result: .failure(error)))
                        return
                    }
                } catch {
                    guard retryIndex < retryDelays.count else {
                        await send(._sessionSyncCompleted(generation: generation, result: .failure(.upstream(0))))
                        return
                    }
                }

                do {
                    try await continuousClock.sleep(for: retryDelays[retryIndex])
                } catch {
                    return
                }
                retryIndex += 1
            }
        }
        .cancellable(id: CancelID.sessionSync, cancelInFlight: true)
    }

    func invalidateSessionSync(_ state: inout State) {
        state.syncGeneration += 1
        state.inFlightSyncReason = nil
    }

    func handleRefreshAccessTapped(_ state: inout State) -> Effect<Action> {
        guard state.hasAccountSession, !state.isSignInInProgress, state.deviceBindingFailure == nil else {
            return .none
        }
        return .send(.sessionSyncRequested(intent: .validate, reason: .manual))
    }

    func requestSessionSync(
        _ state: inout State,
        intent: SessionSyncIntent,
        reason: SyncReason,
    ) -> Effect<Action> {
        guard state.hasAccountSession, !state.isSessionExpired else {
            return .none
        }

        if !reason.bypassesFreshness,
           isFreshCompleteSessionSync(state)
        {
            return .none
        }

        if let inFlightReason = state.inFlightSyncReason,
           reason.priority <= inFlightReason.priority
        {
            return .none
        }

        state.syncGeneration += 1
        state.inFlightSyncReason = reason
        state.isSubmitting = true
        state.errorMessage = nil
        return sessionSyncEffect(intent: intent, reason: reason, generation: state.syncGeneration)
    }

    func handleSessionSyncCompleted(
        _ state: inout State,
        generation: UInt64,
        result: Result<SessionSyncResult, SessionSyncError>,
    ) -> Effect<Action> {
        guard generation == state.syncGeneration else {
            return .none
        }

        state.inFlightSyncReason = nil

        switch result {
        case let .success(result):
            return handleSessionSyncSuccess(&state, result: result)

        case let .failure(error):
            return handleSessionSyncFailure(&state, error: error)
        }
    }

    private func isFreshCompleteSessionSync(_ state: State) -> Bool {
        guard let lastCompleteSyncAt = state.lastCompleteSyncAt else {
            return false
        }

        let isRefreshDue = state.sessionExpiresAt.map { $0.timeIntervalSince(date()) <= 360 } ?? false
        return date().timeIntervalSince(lastCompleteSyncAt) < Self.sessionSyncFreshness && !isRefreshDue
    }

    private func handleSessionSyncSuccess(
        _ state: inout State,
        result: SessionSyncResult,
    ) -> Effect<Action> {
        if let sessionExpiresAt = result.sessionExpiresAt {
            state.sessionExpiresAt = sessionExpiresAt
            state.ttlTimerActive = true
        }
        let refreshDeadline: Effect<Action> = if result.sessionExpiresAt != nil {
            scheduleRefreshDeadline(&state)
        } else {
            .none
        }
        let accessStatus = result.accessStatus.toAccessStatus()
        let syncedAt = date()
        let snapshot = AccessStatusSnapshot.fetchResult(
            status: accessStatus,
            currentPeriodEnd: result.accessStatus.currentPeriodEnd,
            sessionExpiresAt: state.sessionExpiresAt,
            fetchedAt: syncedAt,
        )

        state.isSubmitting = false
        state.status = accessStatus
        state.trialExpiresAt = result.accessStatus.currentPeriodEnd
        state.fetchRetryCount = 0
        state.deviceBindingFailure = nil

        guard result.syncStatus == .complete else {
            state.isComplete = false
            state.snapshot = nil
            state.errorMessage = "Account verification could not be completed. Please try again."

            if accessStatus.isActive {
                return .merge(
                    handleDeviceBindingFailure(&state, snapshot: snapshot, error: .serverFailure),
                    refreshDeadline,
                )
            }

            return .merge(
                .send(.delegate(.recoveryRequired(.accessFailure(
                    error: .networkFailure,
                    sessionExpiresAt: state.sessionExpiresAt,
                )))),
                refreshDeadline,
            )
        }

        let completion = handleCompleteSessionSync(
            &state,
            accessStatus: accessStatus,
            snapshot: snapshot,
            syncedAt: syncedAt,
            deviceBindingOutcome: result.deviceBindingOutcome,
        )
        return .merge(completion, refreshDeadline)
    }

    private func handleCompleteSessionSync(
        _ state: inout State,
        accessStatus: AccessStatus,
        snapshot: AccessStatusSnapshot,
        syncedAt: Date,
        deviceBindingOutcome: SessionSyncDeviceBindingOutcome,
    ) -> Effect<Action> {
        state.lastCompleteSyncAt = syncedAt

        guard accessStatus.isActive else {
            state.snapshot = snapshot
            state.deviceBindingRetryCount = 0
            state.isComplete = false
            state.errorMessage = errorMessageForStatus(accessStatus)
            return saveRecoverySnapshot(snapshot)
        }

        switch deviceBindingOutcome {
        case .bound, .alreadyBound:
            let verifiedSnapshot = AccessStatusSnapshot.fetchResult(
                status: snapshot.status,
                currentPeriodEnd: snapshot.currentPeriodEnd,
                sessionExpiresAt: snapshot.sessionExpiresAt,
                fetchedAt: syncedAt,
                deviceBindingVerifiedAt: syncedAt,
            )
            state.snapshot = verifiedSnapshot
            state.deviceBindingRetryCount = 0
            state.isComplete = verifiedSnapshot.hasSession
            state.errorMessage = nil
            return saveVerifiedSnapshot(verifiedSnapshot)

        case .deviceLimitReached:
            return handleDeviceBindingFailure(&state, snapshot: snapshot, error: .seatCapacityExceeded)

        case .notAttempted:
            return handleDeviceBindingFailure(&state, snapshot: snapshot, error: .serverFailure)
        }
    }

    func handleDeviceBindingFailure(
        _ state: inout State,
        snapshot: AccessStatusSnapshot,
        error: DeviceBindingError,
    ) -> Effect<Action> {
        if error == .unauthorized {
            return .send(._sessionExpiredDetected)
        }

        state.isComplete = false
        state.snapshot = nil
        state.errorMessage = errorMessage(for: error)
        state.deviceBindingFailure = deviceBindingFailure(for: error)
        if state.deviceBindingFailure?.isRetryable == true {
            state.deviceBindingRetryCount += 1
        } else {
            state.deviceBindingRetryCount = 0
        }

        switch error {
        case .noActiveAccess:
            state.status = AccessStatus.none
            state.trialExpiresAt = nil
        case .networkFailure, .serverFailure:
            state.status = .networkFailure
        case .unauthorized, .seatCapacityExceeded, .invalidDevicePayload, .notConfigured, .decodingFailure,
             .unknownGatewayCode:
            break
        }

        return .send(.delegate(.recoveryRequired(.deviceBindingFailure(snapshot: snapshot, error: error))))
    }

    private func handleSessionSyncFailure(_ state: inout State, error: SessionSyncError) -> Effect<Action> {
        state.isSubmitting = false
        state.isComplete = false
        state.deviceBindingFailure = nil

        let accessError = accessError(for: error)
        state.errorMessage = errorMessage(for: accessError)

        if accessError == .unauthorized {
            return .send(._sessionExpiredDetected)
        }

        if accessError == .networkFailure {
            state.status = .networkFailure
        }

        switch accessError {
        case .notConfigured, .decodingFailure, .unknownGatewayCode:
            state.status = nil
            state.snapshot = nil
            state.trialExpiresAt = nil
            return .send(.delegate(.recoveryRequired(.accessFailure(
                error: accessError,
                sessionExpiresAt: state.sessionExpiresAt,
            ))))

        case .networkFailure, .unauthorized:
            break
        }

        return .send(.delegate(.recoveryRequired(.accessFailure(
            error: accessError,
            sessionExpiresAt: state.sessionExpiresAt,
        ))))
    }

    private func accessError(for error: SessionSyncError) -> AccessError {
        switch error {
        case .invalidCredential:
            .unauthorized
        case .storageFailure, .capabilityMiss:
            .notConfigured
        case .upstream:
            .networkFailure
        }
    }

    private func saveRecoverySnapshot(_ snapshot: AccessStatusSnapshot) -> Effect<Action> {
        .run { [snapshotClient] send in
            await snapshotClient.save(snapshot)
            try Task.checkCancellation()
            await send(.delegate(.recoveryRequired(.snapshot(snapshot))))
        }
        .cancellable(id: CancelID.sessionSync, cancelInFlight: true)
    }

    private func saveVerifiedSnapshot(_ snapshot: AccessStatusSnapshot) -> Effect<Action> {
        .run { [snapshotClient] send in
            do {
                try Task.checkCancellation()
                await snapshotClient.save(snapshot)
                try Task.checkCancellation()
                await send(.delegate(.unlocked(snapshot)))
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .cancellable(id: CancelID.sessionSync, cancelInFlight: true)
    }

    /// 캐시된 snapshot의 최대 허용 보관 기간.
    /// 네트워크 장애 시 이 기간을 초과한 snapshot은 만료되지 않았더라도 신뢰하지 않는다 (entitlement bypass 방지).
    private static let cachedSnapshotMaxAge: TimeInterval = 7 * 24 * 60 * 60 // 7일

    func handleCachedSnapshotRestored(_ state: inout State, snapshot: AccessStatusSnapshot?) -> Effect<Action> {
        // 계약 (entitlement_access_flow.md): 조회 실패는 error 축에서 처리.
        // failure handler가 이미 status=.networkFailure + errorMessage를 기록했으므로
        // 캐시가 없거나 만료된 snapshot은 거부하고 state를 그대로 둔다.
        guard let snapshot else {
            return .send(.delegate(.recoveryRequired(.accessFailure(
                error: .networkFailure,
                sessionExpiresAt: state.sessionExpiresAt,
            ))))
        }

        let now = date.now
        let isStale = snapshot.isExpired(now: now)
            || now.timeIntervalSince(snapshot.fetchedAt) > Self.cachedSnapshotMaxAge
        if isStale {
            return .send(.delegate(.recoveryRequired(.snapshot(snapshot))))
        }

        // entitlement 축: 캐시된 access status로 복원. 기존 정책 미변경.
        state.status = snapshot.status
        state.snapshot = snapshot
        state.isComplete = snapshot.isActive && snapshot.isDeviceBindingVerified && snapshot.hasSession
        state.errorMessage = "일시적인 네트워크 오류"
        state.deviceBindingFailure = snapshot.isActive && !snapshot.isDeviceBindingVerified ? .retryable : nil

        // session 축: snapshot 기반으로 signed-in semantics 설정.
        // handleHydrateLaunchSnapshot와 동일한 ownership path를 따르되,
        // networkFailure fallback 경로이므로 새로운 session sync는 시작하지 않는다.
        // sessionExpiresAt == nil이면 hasAccountSession=false (가짜 세션 주입 금지).
        state.hasAccountSession = snapshot.hasSession
        state.sessionExpiresAt = snapshot.sessionExpiresAt

        // bootstrap 완료 표시: 캐시 복원으로 초기 상태가 확정되었으므로
        // 이후 handleOnAppear가 중복 session read/fetch를 수행하지 않도록 차단.
        state.didBootstrap = true

        if state.isComplete {
            return .send(.delegate(.unlocked(snapshot)))
        }

        return .send(.delegate(.recoveryRequired(.snapshot(snapshot))))
    }

    func errorMessage(for error: AccessError) -> String {
        switch error {
        case .networkFailure: "Network error. Please check your connection and try again."
        case .notConfigured: "Access service is not configured."
        case .decodingFailure: "Failed to process the response."
        case .unauthorized: "Session expired. Please sign in again."
        case .unknownGatewayCode: "An unexpected error occurred."
        }
    }

    func errorMessage(for error: DeviceBindingError) -> String {
        switch error {
        case .unauthorized:
            "Session expired. Please sign in again."
        case .noActiveAccess:
            "No active license was found for this account. Check your account and try again."
        case .seatCapacityExceeded:
            "This license has reached its device limit. Manage devices or contact support."
        case .invalidDevicePayload:
            "Could not identify this Mac. Please try again or contact support."
        case .serverFailure, .networkFailure:
            "Could not bind this Mac. Please try again."
        case .notConfigured:
            "Access service is not configured."
        case .decodingFailure:
            "Failed to process the device binding response."
        case .unknownGatewayCode:
            "An unexpected device binding error occurred."
        }
    }

    func deviceBindingFailure(for error: DeviceBindingError) -> DeviceBindingFailure {
        switch error {
        case .noActiveAccess:
            .noActiveAccess
        case .seatCapacityExceeded:
            .seatCapacityExceeded
        case .networkFailure, .serverFailure:
            .retryable
        case .invalidDevicePayload:
            .invalidDevicePayload
        case .notConfigured, .decodingFailure, .unknownGatewayCode:
            .unknown
        case .unauthorized:
            .retryable
        }
    }

    func errorMessageForStatus(_ status: AccessStatus) -> String {
        switch status {
        case .trialExpired: "This trial has expired."
        case .revoked: "This license has been revoked."
        case .refunded: "This license has been refunded."
        case .networkFailure: "Network error. Please check your connection and try again."
        case .none: "Access denied."
        default: "An unexpected status was returned."
        }
    }
}
