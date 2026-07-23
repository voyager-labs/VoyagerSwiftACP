@preconcurrency import AppKit
import AudioToolbox
import ComposableArchitecture
import Foundation

// MARK: - EntryOperationSound

public enum EntryOperationSound: String, CaseIterable, Sendable {
    case moveToTrash
    case emptyTrash
    case operationCompleted
    case error
}

// MARK: - EntryOperationSoundClient

public struct EntryOperationSoundClient: Sendable {
    public var play: @Sendable (EntryOperationSound) async -> Void

    public init(play: @escaping @Sendable (EntryOperationSound) async -> Void) {
        self.play = play
    }
}

// MARK: - Live Value (AudioToolbox)

private actor SoundPlayer {
    private var soundIDs: [EntryOperationSound: SystemSoundID] = [:]
    private var lastPlayed: Date = .distantPast
    private var loggedMissingResource: Set<String> = []
    private let throttleInterval: TimeInterval = 0.5

    func play(_ sound: EntryOperationSound, isAppActive: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastPlayed) >= throttleInterval else { return }
        guard isAppActive else { return }

        // kSystemSoundID_UserPreferredAlert is a special ID that does not need loading
        if sound == .error {
            AudioServicesPlayAlertSoundWithCompletion(kSystemSoundID_UserPreferredAlert, nil)
            lastPlayed = now
            return
        }

        let soundID: SystemSoundID
        if let cached = soundIDs[sound] {
            soundID = cached
        } else {
            guard let url = url(for: sound) else {
                if !loggedMissingResource.contains(sound.rawValue) {
                    loggedMissingResource.insert(sound.rawValue)
                    #if DEBUG
                    print("[EntryOperationSoundClient] Missing resource for \(sound.rawValue)")
                    #endif
                }
                return
            }
            var newID: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(url as CFURL, &newID)
            guard status == noErr else {
                if !loggedMissingResource.contains(sound.rawValue) {
                    loggedMissingResource.insert(sound.rawValue)
                    #if DEBUG
                    print("[EntryOperationSoundClient] Failed to create sound ID for \(sound.rawValue): \(status)")
                    #endif
                }
                return
            }
            soundIDs[sound] = newID
            soundID = newID
        }

        AudioServicesPlaySystemSoundWithCompletion(soundID, nil)
        lastPlayed = now
    }

    deinit {
        for (_, id) in soundIDs {
            AudioServicesDisposeSystemSoundID(id)
        }
    }

    private func url(for sound: EntryOperationSound) -> URL? {
        let resourceName: String
        switch sound {
        case .moveToTrash:
            resourceName = "drag to trash"
        case .emptyTrash:
            resourceName = "empty trash"
        case .operationCompleted:
            resourceName = "Volume Mount"
        case .error:
            return nil // error uses kSystemSoundID_UserPreferredAlert, not a bundled resource
        }
        return Bundle.module.url(forResource: resourceName, withExtension: "aif", subdirectory: "Sounds")
    }
}

extension EntryOperationSoundClient: DependencyKey {
    nonisolated public static var liveValue: EntryOperationSoundClient {
        let player = SoundPlayer()
        return EntryOperationSoundClient(
            play: { sound in
                let isActive = await MainActor.run { NSApplication.shared.isActive }
                await player.play(sound, isAppActive: isActive)
            },
        )
    }

    nonisolated public static var testValue: EntryOperationSoundClient {
        EntryOperationSoundClient(
            play: { _ in },
        )
    }

    nonisolated public static var previewValue: EntryOperationSoundClient {
        EntryOperationSoundClient(
            play: { _ in },
        )
    }
}

public extension DependencyValues {
    nonisolated var entryOperationSoundClient: EntryOperationSoundClient {
        get { self[EntryOperationSoundClient.self] }
        set { self[EntryOperationSoundClient.self] = newValue }
    }
}
