import AppKit
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
  static let largeCornerRadius: CGFloat = 12
  static let controlHeight: CGFloat = 34
  static let sidebarWidth: CGFloat = 224
  static let pageHeaderHeight: CGFloat = 76
  static let pageHorizontalPadding: CGFloat = 28
  static let hairline: CGFloat = 1
}

enum AppColor {
  static let canvas = adaptive("Canvas", light: 0xFAFAFA, dark: 0x0A0A0A)
  static let surface = adaptive("Surface", light: 0xFFFFFF, dark: 0x111111)
  static let raisedSurface = adaptive("RaisedSurface", light: 0xFFFFFF, dark: 0x171717)
  static let sidebar = adaptive("Sidebar", light: 0xF5F5F5, dark: 0x0D0D0D)
  static let subtle = adaptive("Subtle", light: 0xF4F4F5, dark: 0x1C1C1C)
  static let border = adaptive("Border", light: 0xE5E5E5, dark: 0x2A2A2A)
  static let strongBorder = adaptive("StrongBorder", light: 0xD4D4D4, dark: 0x404040)
  static let success = adaptive("Success", light: 0x16803C, dark: 0x45D483)
  static let warning = adaptive("Warning", light: 0xB45309, dark: 0xF5A623)
  static let danger = adaptive("Danger", light: 0xC62828, dark: 0xFF6868)

  private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: NSColor.Name("EnvStore\(name)")) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return nsColor(hex: match == .darkAqua ? dark : light)
      })
  }

  private static func nsColor(hex: UInt32) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}

extension View {
  func envStorePanel() -> some View {
    modifier(EnvStorePanelModifier(background: AppColor.surface))
  }

  func envStoreRaisedPanel() -> some View {
    modifier(EnvStorePanelModifier(background: AppColor.raisedSurface))
  }

  func envStoreField() -> some View {
    textFieldStyle(.plain)
      .modifier(EnvStoreControlModifier())
  }

  func envStoreControl() -> some View {
    modifier(EnvStoreControlModifier())
  }
}

private struct EnvStoreControlModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 10)
      .frame(minHeight: AppMetrics.controlHeight)
      .background(AppColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: AppMetrics.cornerRadius)
          .stroke(AppColor.border, lineWidth: AppMetrics.hairline)
      }
  }
}

private struct EnvStorePanelModifier: ViewModifier {
  let background: Color

  func body(content: Content) -> some View {
    content
      .background(background)
      .clipShape(RoundedRectangle(cornerRadius: AppMetrics.largeCornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: AppMetrics.largeCornerRadius)
          .stroke(AppColor.border, lineWidth: AppMetrics.hairline)
      }
  }
}

struct EnvPrimaryButtonStyle: ButtonStyle {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
      .padding(.horizontal, 14)
      .frame(minHeight: AppMetrics.controlHeight)
      .background(colorScheme == .dark ? Color.white : Color.black)
      .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cornerRadius))
      .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
  }
}

struct EnvSecondaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.primary)
      .padding(.horizontal, 12)
      .frame(minHeight: AppMetrics.controlHeight)
      .background(configuration.isPressed ? AppColor.subtle : AppColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: AppMetrics.cornerRadius)
          .stroke(AppColor.border, lineWidth: AppMetrics.hairline)
      }
      .opacity(isEnabled ? 1 : 0.42)
  }
}

struct EnvIconButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.secondary)
      .frame(width: AppMetrics.controlHeight, height: AppMetrics.controlHeight)
      .background(configuration.isPressed ? AppColor.subtle : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cornerRadius))
      .contentShape(Rectangle())
      .opacity(isEnabled ? 1 : 0.42)
  }
}

extension ButtonStyle where Self == EnvPrimaryButtonStyle {
  static var envPrimary: EnvPrimaryButtonStyle { EnvPrimaryButtonStyle() }
}

extension ButtonStyle where Self == EnvSecondaryButtonStyle {
  static var envSecondary: EnvSecondaryButtonStyle { EnvSecondaryButtonStyle() }
}

extension ButtonStyle where Self == EnvIconButtonStyle {
  static var envIcon: EnvIconButtonStyle { EnvIconButtonStyle() }
}
