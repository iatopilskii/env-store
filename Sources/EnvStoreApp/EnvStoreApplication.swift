import AppKit
import EnvStoreAppCore
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
  @StateObject private var setupModel = SetupViewModel()
  @StateObject private var shellModel = AppShellModel()
  @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

  var body: some Scene {
    WindowGroup {
      AppShellView(model: model, setupModel: setupModel, shellModel: shellModel)
        .environmentObject(shellModel)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .frame(minWidth: 1080, minHeight: 700)
    }
    .defaultSize(width: 1240, height: 800)
    .windowStyle(.automatic)

    Settings {
      SettingsView(setupModel: setupModel)
        .environmentObject(shellModel)
        .frame(width: 720, height: 650)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
    }
    .commands {
      AppSidebarCommands(model: shellModel)
    }
  }
}
