import AppKit
import SwiftUI

struct WindowChromeConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowChromeHostView {
    WindowChromeHostView()
  }

  func updateNSView(_ view: WindowChromeHostView, context: Context) {
    view.applyConfiguration()
  }
}

@MainActor
final class WindowChromeHostView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyConfiguration()
  }

  func applyConfiguration() {
    guard let window else { return }
    window.title = ""
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.toolbarStyle = .unifiedCompact
    DispatchQueue.main.async { [weak window] in
      window?.title = ""
      window?.titleVisibility = .hidden
    }
  }
}
