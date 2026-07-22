import Combine
import SwiftUI

@MainActor
final class AppShellModel: ObservableObject {
  @Published private(set) var isSidebarVisible = true

  func toggleSidebar() {
    isSidebarVisible.toggle()
  }
}

struct AppSidebarCommands: Commands {
  @ObservedObject var model: AppShellModel

  var body: some Commands {
    CommandGroup(replacing: .sidebar) {
      Button(model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
        model.toggleSidebar()
      }
      .keyboardShortcut("s", modifiers: [.command, .control])
    }
  }
}
