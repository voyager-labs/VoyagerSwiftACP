import AppKit
import Combine
import Foundation
import SwiftUI

private enum ComposerHostSmokeMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["COMPOSER_HOST_SMOKE"] == "1"
    }

    @MainActor
    static func run() -> Never {
        let report = ComposerHostSmokeContract.validate()
        for line in report.lines {
            Swift.print(line)
        }

        if report.isValid {
            print("exitReason=smoke_complete")
            exit(0)
        }

        print("failureReason=\(report.failureReason ?? "unknown")")
        print("exitReason=smoke_failed")
        exit(1)
    }
}

@main
@MainActor
struct ComposerHostApp: App {
    @NSApplicationDelegateAdaptor(ComposerHostAppDelegate.self)
    private var appDelegate

    init() {
        if ComposerHostSmokeMode.isEnabled {
            ComposerHostSmokeMode.run()
        }
    }

    var body: some Scene {
        WindowGroup("Composer") {
            ComposerHostWindowContent(container: appDelegate.storeContainer)
        }
    }
}

@MainActor
private final class ComposerHostAppDelegate: NSObject, NSApplicationDelegate {
    let storeContainer: ComposerHostStoreContainer

    override init() {
        storeContainer = .init(preset: .resolve(ProcessInfo.processInfo.environment["COMPOSER_HOST_PRESET"]))
        super.init()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

private struct ComposerHostWindowContent: View {
    @ObservedObject var container: ComposerHostStoreContainer

    var body: some View {
        VStack(spacing: 0) {
            ComposerHostScenarioBar(container: container)
            ComposerHostRootView(container: container)
                .id(container.scenarioID)
        }
    }
}

private struct ComposerHostScenarioBar: View {
    @ObservedObject var container: ComposerHostStoreContainer

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Scenario")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.secondary)
            Picker("Preset", selection: Binding(
                get: { container.preset },
                set: { container.select($0) },
            )) {
                ForEach(ComposerHostPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220)
            Picker("Collection", selection: Binding(
                get: { container.selectedCollection?.id },
                set: { container.selectCollection(id: $0) },
            )) {
                Text("Saved Collection").tag(String?.none)
                ForEach(container.collections) { definition in
                    Text(definition.name).tag(Optional(definition.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220)
            .disabled(!container.canSelectCollections)
            .accessibilityLabel("Saved Collection selector")
            Spacer(minLength: 0)
            Text(container.preset.scenario.id)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Composer host scenario selector")
    }
}
