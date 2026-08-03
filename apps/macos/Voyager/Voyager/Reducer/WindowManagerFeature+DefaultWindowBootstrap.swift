import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerShared

enum DefaultWindowBootstrap {
    struct Dependencies {
        let builtInClient: FileManagerBuiltInCollectionClient
        let pinnedRecordClient: ContentTabPinnedRecordClient
        let favoritesClient: FileManagerFavoritesClient
        let managerClient: FileManagerClient
        let locationsClient: FileManagerLocationsClient
        let loadingClient: EntryLoadingClient
        let defaultsClient: UserDefaultsClient
        let metricsClient: MetricsClient
        let workspaceClient: WorkspaceClient
        let now: @Sendable () -> Date
    }

    struct RestoreResult {
        let state: ContentTabState
        let store: ContentTabPinnedRecordStore
        let didCompact: Bool
    }

    static func run(_ dependencies: Dependencies) async -> DefaultWindowBootstrapResult? {
        guard !Task.isCancelled else { return nil }
        let fixedLocationItems = FileManagerHomeDashboardProjection.makeFixedLocations(
            from: dependencies.locationsClient.loadLocations(dependencies.loadingClient),
        )
        guard await dependencies.workspaceClient.prepareFileIcons(fixedLocationItems.map(\.path)) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        let discoveredLocationIDs = fixedLocationItems.map(\.id)
        guard let initialOutcome = loadStoreOutcome(
            discoveredLocationIDs: discoveredLocationIDs,
            dependencies: dependencies,
        ) else { return nil }
        if let unavailableResult = unavailableResult(
            for: initialOutcome,
            fixedLocationItems: fixedLocationItems,
        ) {
            return unavailableResult
        }
        guard let initialStore = initialOutcome.writableStore else { return nil }
        guard await prepareWritableStore(
            initialStore: initialStore,
            discoveredLocationIDs: discoveredLocationIDs,
            dependencies: dependencies,
        ) else { return nil }
        return finishWritableBootstrap(
            fixedLocationItems: fixedLocationItems,
            discoveredLocationIDs: discoveredLocationIDs,
            dependencies: dependencies,
        )
    }

    private static func loadStoreOutcome(
        discoveredLocationIDs: [String],
        dependencies: Dependencies,
    ) -> ContentTabPinnedRecordStoreLoadOutcome? {
        try? dependencies.pinnedRecordClient.loadStoreOutcome(
            dependencies.defaultsClient,
            discoveredLocationIDs: discoveredLocationIDs,
        )
    }

    private static func prepareWritableStore(
        initialStore: ContentTabPinnedRecordStore,
        discoveredLocationIDs: [String],
        dependencies: Dependencies,
    ) async -> Bool {
        if !dependencies.defaultsClient.bool(SettingsKeys.defaultPinnedTabsSeedCompleted) {
            dependencies.defaultsClient.setBool(true, SettingsKeys.defaultPinnedTabsSeedCompleted)
        }
        seedFinderFavoritesIfNeeded(
            initialStore: initialStore,
            discoveredLocationIDs: discoveredLocationIDs,
            dependencies: dependencies,
        )
        guard !Task.isCancelled else { return false }
        let ensureReport = await dependencies.builtInClient.ensureAll()
        guard !Task.isCancelled else { return false }
        dependencies.metricsClient.logMetric("built_in_pinned_seed_started", 1, nil)
        seedBuiltInCollectionIfNeeded(
            identity: .recents,
            ensureResult: ensureReport.recents,
            completionKey: SettingsKeys.recentsPinnedSeedCompleted,
            discoveredLocationIDs: discoveredLocationIDs,
            dependencies: dependencies,
        )
        guard !Task.isCancelled else { return false }
        seedBuiltInCollectionIfNeeded(
            identity: .allTags,
            ensureResult: ensureReport.allTags,
            completionKey: SettingsKeys.allTagsPinnedSeedCompleted,
            discoveredLocationIDs: discoveredLocationIDs,
            dependencies: dependencies,
        )
        return !Task.isCancelled
    }

    private static func finishWritableBootstrap(
        fixedLocationItems: [FileManagerFixedLocationItem],
        discoveredLocationIDs: [String],
        dependencies: Dependencies,
    ) -> DefaultWindowBootstrapResult? {
        guard let reloadedOutcome = loadStoreOutcome(
            discoveredLocationIDs: discoveredLocationIDs,
            dependencies: dependencies,
        ) else { return nil }
        if let unavailableResult = unavailableResult(
            for: reloadedOutcome,
            fixedLocationItems: fixedLocationItems,
        ) {
            return unavailableResult
        }
        guard let reloadedStore = reloadedOutcome.writableStore else { return nil }
        let restoreResult = restorePinnedRecords(from: reloadedStore, dependencies: dependencies)
        let finalRestoreResult = compactIfNeeded(
            restoreResult,
            discoveredLocationIDs: discoveredLocationIDs,
            dependencies: dependencies,
        )
        return availableResult(
            from: finalRestoreResult,
            fixedLocationItems: fixedLocationItems,
            discoveredLocationIDs: discoveredLocationIDs,
        )
    }

    private static func availableResult(
        from restoreResult: RestoreResult,
        fixedLocationItems: [FileManagerFixedLocationItem],
        discoveredLocationIDs: [String],
    ) -> DefaultWindowBootstrapResult {
        let arrangementStore = ContentTabPinnedRecordStore(
            schemaVersion: restoreResult.store.schemaVersion,
            records: restoreResult.state.tabs.compactMap { tab in
                restoreResult.state.pinnedRecords[tab.id]
            },
            topNavigationOrder: restoreResult.store.topNavigationOrder,
        )
        let durableOrder = FileManagerTopNavigationOrderPolicy.normalize(
            store: arrangementStore,
            discoveredLocationIDs: discoveredLocationIDs,
        ).durableOrder
        return DefaultWindowBootstrapResult(
            contentTabs: restoreResult.state,
            fixedLocationItems: fixedLocationItems,
            topNavigationOrder: durableOrder,
            arrangementAvailability: .available,
        )
    }

    private static func unavailableResult(
        for outcome: ContentTabPinnedRecordStoreLoadOutcome,
        fixedLocationItems: [FileManagerFixedLocationItem],
    ) -> DefaultWindowBootstrapResult? {
        let failure: FileManagerTopNavigationArrangementLoadFailure
        switch outcome {
        case .missing, .migratedV1, .migratedLegacyV2, .currentV2:
            return nil
        case .corruptUnavailable:
            failure = .corrupt
        case let .futureSchemaUnavailable(schemaVersion, _):
            failure = .unsupportedSchema(schemaVersion)
        }
        return DefaultWindowBootstrapResult(
            contentTabs: .init(),
            fixedLocationItems: fixedLocationItems,
            topNavigationOrder: .init(),
            arrangementAvailability: .unavailable(failure),
        )
    }

    private static func seedFinderFavoritesIfNeeded(
        initialStore: ContentTabPinnedRecordStore,
        discoveredLocationIDs: [String],
        dependencies: Dependencies,
    ) {
        guard !dependencies.defaultsClient.bool(SettingsKeys.finderFavoritesPinnedSeedCompleted) else { return }
        let applicationSupportURL = dependencies.managerClient.urlsForDirectory(
            .applicationSupportDirectory,
            .userDomainMask,
        ).first
        guard nonBuiltInRecords(
            in: initialStore,
            applicationSupportURL: applicationSupportURL,
        ).isEmpty else {
            dependencies.defaultsClient.setBool(true, SettingsKeys.finderFavoritesPinnedSeedCompleted)
            return
        }
        let favorites = dependencies.favoritesClient.loadFavorites(
            dependencies.loadingClient,
            dependencies.defaultsClient,
        )
        let mappedRecords = uniqueRecordsByID(FileManagerFavoritesPinnedRecordMapper.pinnedRecords(
            from: favorites,
            pinnedAt: dependencies.now(),
            fileExistsWithIsDirectory: { path, isDirectory in
                dependencies.managerClient.fileExistsWithIsDirectory(path, isDirectory)
            },
        ))
        do {
            _ = try dependencies.pinnedRecordClient.updateStoreAndLoad(
                dependencies.defaultsClient,
            ) { latestStore in
                try Task.checkCancellation()
                guard nonBuiltInRecords(
                    in: latestStore,
                    applicationSupportURL: applicationSupportURL,
                ).isEmpty else {
                    return latestStore
                }

                let mergedStore = mergingFinderRecords(
                    mappedRecords,
                    into: latestStore,
                    applicationSupportURL: applicationSupportURL,
                )
                return FileManagerTopNavigationOrderPolicy.normalize(
                    store: mergedStore,
                    discoveredLocationIDs: discoveredLocationIDs,
                ).normalizedStore
            }
            guard !Task.isCancelled else { return }
            dependencies.defaultsClient.setBool(true, SettingsKeys.finderFavoritesPinnedSeedCompleted)
        } catch {
            // Finder 저장 실패 시 완료 플래그를 남기지 않아 다음 부트스트랩에서 재시도한다.
        }
    }

    private static func seedBuiltInCollectionIfNeeded(
        identity: BuiltInCollectionIdentity,
        ensureResult: BuiltInCollectionEnsureItemResult,
        completionKey: String,
        discoveredLocationIDs: [String],
        dependencies: Dependencies,
    ) {
        guard !Task.isCancelled else { return }
        if dependencies.defaultsClient.bool(completionKey) {
            logSeedMetric("built_in_pinned_item_suppressed", identity: identity, dependencies: dependencies)
            return
        }
        let descriptor: BuiltInCollectionDescriptor
        switch ensureResult {
        case let .ready(value): descriptor = value
        case .deferred:
            logSeedMetric("built_in_pinned_item_deferred", identity: identity, dependencies: dependencies)
            return
        case .failed:
            logSeedMetric("built_in_pinned_item_failed", identity: identity, dependencies: dependencies)
            return
        }
        let policyDescriptor = builtInSeedDescriptor(from: descriptor)
        do {
            let finalStore = try dependencies.pinnedRecordClient.updateStoreAndLoad(
                dependencies.defaultsClient,
            ) { latestStore in
                try Task.checkCancellation()
                let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
                    ensureResult: .ready(policyDescriptor),
                    completion: false,
                    store: latestStore,
                    now: dependencies.now(),
                    discoveredLocationIDs: discoveredLocationIDs,
                )
                return switch result {
                case let .seed(store), let .alreadyPresent(store):
                    store
                case .suppressed, .deferred, .failed:
                    latestStore
                }
            }
            guard BuiltInContentTabPinnedRecordSeedPolicy.containsCanonicalRecord(
                in: finalStore,
                descriptor: policyDescriptor,
            ) else {
                logSeedMetric("built_in_pinned_item_deferred", identity: identity, dependencies: dependencies)
                return
            }
            guard !Task.isCancelled else { return }
            dependencies.defaultsClient.setBool(true, completionKey)
            logSeedMetric("built_in_pinned_item_seeded", identity: identity, dependencies: dependencies)
        } catch {
            logSeedMetric("built_in_pinned_item_failed", identity: identity, dependencies: dependencies)
            // 항목별 저장 실패는 완료 플래그를 남기지 않아 독립적으로 재시도한다.
        }
    }

    private static func builtInSeedDescriptor(
        from descriptor: BuiltInCollectionDescriptor,
    ) -> BuiltInContentTabPinnedRecordSeedPolicy.VerifiedDescriptor {
        .init(identity: descriptor.identity, canonicalPackageURL: descriptor.packageURL)
    }

    private static func logSeedMetric(
        _ name: String,
        identity: BuiltInCollectionIdentity,
        dependencies: Dependencies,
    ) {
        let outcome = name.replacingOccurrences(of: "built_in_pinned_item_", with: "")
        dependencies.metricsClient.logMetric(
            name,
            1,
            ["identity": identity.rawValue, "outcome": outcome],
        )
    }

    private static func compactIfNeeded(
        _ restoreResult: RestoreResult,
        discoveredLocationIDs: [String],
        dependencies: Dependencies,
    ) -> RestoreResult {
        guard restoreResult.didCompact else { return restoreResult }

        do {
            let compactedStore = try dependencies.pinnedRecordClient.updateStoreAndLoad(
                dependencies.defaultsClient,
            ) { latestStore in
                try Task.checkCancellation()
                let latestRestoreResult = restorePinnedRecords(
                    from: latestStore,
                    dependencies: dependencies,
                )
                guard latestRestoreResult.didCompact else { return latestStore }

                let compactedStore = ContentTabPinnedRecordStore(
                    schemaVersion: latestStore.schemaVersion,
                    records: latestRestoreResult.state.tabs.compactMap { tab in
                        latestRestoreResult.state.pinnedRecords[tab.id]
                    },
                    topNavigationOrder: latestStore.topNavigationOrder,
                )
                return FileManagerTopNavigationOrderPolicy.normalize(
                    store: compactedStore,
                    discoveredLocationIDs: discoveredLocationIDs,
                ).normalizedStore
            }
            return restorePinnedRecords(from: compactedStore, dependencies: dependencies)
        } catch {
            return restoreResult
        }
    }

    nonisolated private static func mergingFinderRecords(
        _ records: [ContentTabPinnedRecord],
        into store: ContentTabPinnedRecordStore,
        applicationSupportURL: URL?,
    ) -> ContentTabPinnedRecordStore {
        let recentsResidue = BuiltInContentTabPinnedRecordSeedPolicy.records(
            classifiedAs: .recents,
            in: store,
            applicationSupportURL: applicationSupportURL,
        )
        let allTagsResidue = BuiltInContentTabPinnedRecordSeedPolicy.records(
            classifiedAs: .allTags,
            in: store,
            applicationSupportURL: applicationSupportURL,
        )
        return ContentTabPinnedRecordStore(
            schemaVersion: store.schemaVersion,
            records: recentsResidue + records + allTagsResidue,
            topNavigationOrder: store.topNavigationOrder,
        )
    }

    nonisolated private static func nonBuiltInRecords(
        in store: ContentTabPinnedRecordStore,
        applicationSupportURL: URL?,
    ) -> [ContentTabPinnedRecord] {
        store.records.filter {
            BuiltInContentTabPinnedRecordSeedPolicy.classify(
                $0,
                applicationSupportURL: applicationSupportURL,
            ) == nil
        }
    }

    private static func uniqueRecordsByID(
        _ records: [ContentTabPinnedRecord],
    ) -> [ContentTabPinnedRecord] {
        var seenIDs = Set<String>()
        return records.filter { seenIDs.insert($0.id).inserted }
    }

    nonisolated private static func restorePinnedRecords(
        from store: ContentTabPinnedRecordStore,
        dependencies: Dependencies,
    ) -> RestoreResult {
        let result = ContentTabState.restoringPinnedRecords(
            from: store,
            isRestorableAnchor: { anchor in
                switch anchor {
                case let .directory(path):
                    var isDirectory = ObjCBool(false)
                    return dependencies.managerClient.fileExistsWithIsDirectory(path, &isDirectory)
                        && isDirectory.boolValue
                case let .collectionFile(url):
                    return dependencies.managerClient.fileExistsWithIsDirectory(url.path, nil)
                case .homeDefault, .virtualCollection, .aiChat:
                    return true
                }
            },
        )
        return RestoreResult(state: result.state, store: store, didCompact: result.didCompact)
    }
}

extension WindowManagerFeature {
    func handleDefaultWindowBootstrapRequested(
        _ windowID: State.WindowID,
        state: inout State,
    ) -> Effect<Action> {
        guard state.windows[id: windowID] != nil,
              state.pendingWindowOpenIDs.contains(windowID),
              !state.closingWindowIDs.contains(windowID),
              state.externalWindowBatchIDs[windowID] == nil
        else { return .none }
        return defaultWindowBootstrapEffectIfNeeded(for: windowID, state: &state)
    }

    func handlePinnedContentTabsStoreChanged(state: inout State) -> Effect<Action> {
        let syncEffect = syncPinnedContentTabsAcrossWindows(state: &state)
        let bootstrapLifecycle = invalidateAndRestartDefaultWindowBootstrapForTopNavigationChange(state: &state)
        return .concatenate(
            bootstrapLifecycle.cancel,
            syncEffect,
            bootstrapLifecycle.restart,
        )
    }

    func invalidateAndRestartDefaultWindowBootstrapForTopNavigationChange(
        state: inout State,
    ) -> (cancel: Effect<Action>, restart: Effect<Action>) {
        let pendingBootstrapWindowIDs = livePendingDefaultBootstrapWindowIDs(state)
        state.defaultWindowBootstrapRequestID = nil
        state.defaultWindowBootstrapWindowIDs.removeAll()
        let restartEffect: Effect<Action>
        if let firstWindowID = pendingBootstrapWindowIDs.first {
            state.defaultWindowBootstrapWindowIDs.formUnion(pendingBootstrapWindowIDs.dropFirst())
            restartEffect = defaultWindowBootstrapEffectIfNeeded(for: firstWindowID, state: &state)
        } else {
            restartEffect = .none
        }
        return (
            cancel: .cancel(id: CancelID.defaultWindowBootstrap),
            restart: restartEffect,
        )
    }

    func handleDefaultWindowBootstrapCompleted(
        _ requestID: UUID,
        result: DefaultWindowBootstrapResult,
        state: inout State,
    ) -> Effect<Action> {
        guard state.defaultWindowBootstrapRequestID == requestID else { return .none }
        state.defaultWindowBootstrapRequestID = nil
        let targetWindowIDs = livePendingDefaultBootstrapWindowIDs(state)
        state.defaultWindowBootstrapWindowIDs.removeAll()
        return .merge(
            targetWindowIDs.map { id in
                .concatenate(
                    applyDefaultWindowBootstrap(result, to: id),
                    .send(.windowReadyToOpen(id: id)),
                )
            },
        )
    }

    func handleDefaultWindowBootstrapFailed(
        _ requestID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        guard state.defaultWindowBootstrapRequestID == requestID else { return .none }
        state.defaultWindowBootstrapRequestID = nil
        let targetWindowIDs = livePendingDefaultBootstrapWindowIDs(state)
        state.defaultWindowBootstrapWindowIDs.removeAll()
        return .merge(
            targetWindowIDs.map { id in
                .send(.windowReadyToOpen(id: id))
            },
        )
    }

    func applyDefaultWindowBootstrap(
        _ result: DefaultWindowBootstrapResult,
        to windowID: State.WindowID,
    ) -> Effect<Action> {
        .send(.windows(.element(
            id: windowID,
            action: .window(.applyBootstrap(.init(
                arrangementAvailability: result.arrangementAvailability,
                committedTopNavigationOrder: result.topNavigationOrder,
                authoritativePinnedContentTabs: result.contentTabs,
                fixedLocationItems: result.fixedLocationItems,
            ))),
        )))
    }

    private func livePendingDefaultBootstrapWindowIDs(_ state: State) -> [State.WindowID] {
        state.windows.ids.filter { id in
            state.defaultWindowBootstrapWindowIDs.contains(id)
                && state.pendingWindowOpenIDs.contains(id)
                && !state.closingWindowIDs.contains(id)
                && state.externalWindowBatchIDs[id] == nil
                && state.retainedExternalOpenPlacementOwnership?.newWindowIDs.contains(id) != true
        }
    }
}
