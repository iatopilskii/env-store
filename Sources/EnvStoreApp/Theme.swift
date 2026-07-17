import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

enum AppMetrics {
  static let cornerRadius: CGFloat = 8
  static let controlHeight: CGFloat = 32
  static let hairline: CGFloat = 0.5
}

extension View {
  func envStorePanel() -> some View {
    background(.background)
      .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: AppMetrics.cornerRadius)
          .stroke(.separator, lineWidth: AppMetrics.hairline)
      }
  }
}
