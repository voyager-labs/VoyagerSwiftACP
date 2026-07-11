import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

extension AccountAccessFeature {
    func handleRefreshAccessTapped(_ state: inout State) -> Effect<Action> {
        guard state.canRefreshAccess else {
            return .none
        }
        state.fetchGeneration += 1
        return fetchAccessStatusEffect(generation: state.fetchGeneration)
    }

    func handleAccessStatusResponse(
        _ state: inout State,
        generation: Int,
        result: Result<AccessStatusResponse, AccessError>,
    ) -> Effect<Action> {
        guard generation == state.fetchGeneration else {
            return .none
        }

        switch result {
        case let .success(response):
            return handleAccessStatusSuccess(&state, response: response)

        case let .failure(error):
            return handleAccessStatusFailure(&state, error: error)
        }
    }

    func handleAccessStatusSuccess(_ state: inout State, response: AccessStatusResponse) -> Effect<Action> {
        let accessStatus = response.toAccessStatus()
        state.status = accessStatus
        state.trialExpiresAt = response.currentPeriodEnd
        state.fetchRetryCount = 0
        state.deviceBindingFailure = nil

        let snapshot = AccessStatusSnapshot.fetchResult(
            status: accessStatus,
            currentPeriodEnd: response.currentPeriodEnd,
            sessionExpiresAt: state.sessionExpiresAt,
            fetchedAt: date(),
        )

        if accessStatus.isActive {
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.snapshot = nil
            return bindCurrentDeviceEffect(generation: state.fetchGeneration, snapshot: snapshot)
        }

        state.isSubmitting = false
        state.snapshot = snapshot
        state.deviceBindingRetryCount = 0
        state.isComplete = false
        state.errorMessage = errorMessageForStatus(accessStatus)
        return .run { [snapshotClient] send in
            await snapshotClient.save(snapshot)
            await send(.delegate(.recoveryRequired(.snapshot(snapshot))))
        }
        .cancellable(id: CancelID.fetchStatus, cancelInFlight: true)
    }

    func bindCurrentDeviceEffect(generation: Int, snapshot: AccessStatusSnapshot) -> Effect<Action> {
        .run { [authNetwork, deviceIdentityClient] send in
            let result: Result<DeviceBindingResponse, DeviceBindingError>
            do {
                let request = try DeviceBindingRequest(
                    deviceId: deviceIdentityClient.deviceId(),
                    deviceName: Host.current().localizedName,
                    appVersion: AppVersionInfo.shortVersion,
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                )
                let response = try await authNetwork.bindDevice(request)
                result = .success(response)
            } catch let error as DeviceBindingError {
                result = .failure(error)
            } catch {
                result = .failure(.invalidDevicePayload)
            }
            await send(.deviceBindingResponse(generation: generation, snapshot: snapshot, result: result))
        }
        .cancellable(id: CancelID.fetchStatus, cancelInFlight: true)
    }

    func handleDeviceBindingResponse(
        _ state: inout State,
        generation: Int,
        snapshot: AccessStatusSnapshot,
        result: Result<DeviceBindingResponse, DeviceBindingError>,
    ) -> Effect<Action> {
        guard generation == state.fetchGeneration else {
            return .none
        }

        state.isSubmitting = false

        switch result {
        case let .success(response):
            guard response.ok else {
                return handleDeviceBindingFailure(&state, snapshot: snapshot, error: .decodingFailure)
            }
            let verifiedSnapshot = AccessStatusSnapshot.fetchResult(
                status: snapshot.status,
                currentPeriodEnd: snapshot.currentPeriodEnd,
                sessionExpiresAt: snapshot.sessionExpiresAt,
                fetchedAt: snapshot.fetchedAt,
                deviceBindingVerifiedAt: date(),
            )
            state.status = verifiedSnapshot.status
            state.trialExpiresAt = verifiedSnapshot.currentPeriodEnd
            state.snapshot = verifiedSnapshot
            state.deviceBindingFailure = nil
            state.deviceBindingRetryCount = 0
            state.isComplete = verifiedSnapshot.hasSession
            state.errorMessage = nil
            guard verifiedSnapshot.hasSession else {
                return .run { [snapshotClient] _ in
                    await snapshotClient.save(verifiedSnapshot)
                }
            }
            return .run { [snapshotClient] send in
                do {
                    try Task.checkCancellation()
                    await snapshotClient.save(verifiedSnapshot)
                    try Task.checkCancellation()
                    await send(.delegate(.unlocked(verifiedSnapshot)))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
            .cancellable(id: CancelID.fetchStatus, cancelInFlight: true)

        case let .failure(error):
            return handleDeviceBindingFailure(&state, snapshot: snapshot, error: error)
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

    func handleAccessStatusFailure(_ state: inout State, error: AccessError) -> Effect<Action> {
        state.isSubmitting = false
        state.isComplete = false
        state.errorMessage = errorMessage(for: error)
        state.deviceBindingFailure = nil

        if error == .unauthorized {
            // 401 → 즉시 session_expired 전환 (canonical: entitlement_check.md error table)
            return .send(._sessionExpiredDetected)
        }

        // networkFailure는 source fact로 status에 기록 (error/retry projection의 source).
        // retry budget과 무관하게 항상 기록하여 access_status가 pending/nil로 잘못 해석되지 않는다.
        if error == .networkFailure {
            state.status = .networkFailure
        }

        if error == .notConfigured || error == .decodingFailure {
            return .send(.delegate(.recoveryRequired(.accessFailure(
                error: error,
                sessionExpiresAt: state.sessionExpiresAt,
            ))))
        }

        if case .unknownGatewayCode = error {
            return .send(.delegate(.recoveryRequired(.accessFailure(
                error: error,
                sessionExpiresAt: state.sessionExpiresAt,
            ))))
        }

        guard error == .networkFailure else { return .none }

        if state.fetchRetryCount >= 3 {
            state.fetchRetryCount = 0
            return .run { [sessionClient, snapshotClient] send in
                let snapshot = await snapshotClient.load()
                let session = try? await sessionClient.read()
                let restoredSnapshot = snapshot.map {
                    AccessStatusSnapshot.fetchResult(
                        status: $0.status,
                        currentPeriodEnd: $0.currentPeriodEnd,
                        sessionExpiresAt: session?.expiresAt,
                        fetchedAt: $0.fetchedAt,
                        deviceBindingVerifiedAt: $0.deviceBindingVerifiedAt,
                    )
                }
                await send(._cachedSnapshotRestored(restoredSnapshot))
            }
            .cancellable(id: CancelID.fetchStatus, cancelInFlight: true)
        }

        let retryStep = state.fetchRetryCount
        state.fetchRetryCount += 1
        return .send(._fetchRetryScheduled(retryStep))
    }

    func handleFetchRetryScheduled(_ state: inout State, retryStep: Int) -> Effect<Action> {
        // fetchRetryCount는 handleAccessStatusResponse에서 이미 증가함
        let delay = Duration.seconds(1 << retryStep) // 1s, 2s, 4s
        let generation = state.fetchGeneration
        return .run { [continuousClock, authNetwork] send in
            do {
                try await continuousClock.sleep(for: delay)

                let result: Result<AccessStatusResponse, AccessError>
                do {
                    let response = try await authNetwork.fetchAccessStatus()
                    result = .success(response)
                } catch let error as AccessError {
                    result = .failure(error)
                } catch {
                    result = .failure(.networkFailure)
                }

                await send(.accessStatusResponse(generation: generation, result: result))
            } catch {
                // retry effect cancelled
            }
        }
        .cancellable(id: CancelID.fetchRetry, cancelInFlight: true)
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
        // networkFailure fallback 경로이므로 fetchAccessStatusEffect는 호출하지 않는다.
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
