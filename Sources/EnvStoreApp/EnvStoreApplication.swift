import EnvStoreAppCore
import AppKit
import SwiftUI

final class EnvStoreApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct EnvStoreApplication: App {
    @NSApplicationDelegateAdaptor(EnvStoreApplicationDelegate.self) private var appDelegate
    @StateObject private var model = VaultViewModel()
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            AppShellView(model: model)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 720)
        .windowStyle(.automatic)

        Settings {
            SettingsView()
                .frame(width: 520, height: 360)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        }
    }
}
