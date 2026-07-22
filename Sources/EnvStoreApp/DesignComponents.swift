import SwiftUI

private struct AppSidebarControlVisibilityKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var showsAppSidebarControl: Bool {
    get { self[AppSidebarControlVisibilityKey.self] }
    set { self[AppSidebarControlVisibilityKey.self] = newValue }
  }
}

struct AppPageHeader<Actions: View>: View {
  @Environment(\.showsAppSidebarControl) private var showsSidebarControl
  @EnvironmentObject private var shellModel: AppShellModel
  let title: String
  let subtitle: String
  @ViewBuilder let actions: Actions

  init(
    _ title: String,
    subtitle: String,
    @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.subtitle = subtitle
    self.actions = actions()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 20) {
      if showsSidebarControl, !shellModel.isSidebarVisible {
        AppSidebarToggleButton()
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 20, weight: .semibold))
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 20)
      HStack(spacing: 8) { actions }
    }
    .padding(.horizontal, AppMetrics.pageHorizontalPadding)
    .appShellHeader(background: AppColor.surface)
  }
}

struct AppSidebarToggleButton: View {
  @EnvironmentObject private var shellModel: AppShellModel

  var body: some View {
    Button {
      shellModel.toggleSidebar()
    } label: {
      Image(systemName: "sidebar.left")
        .font(.system(size: 12, weight: .medium))
    }
    .buttonStyle(.envIcon)
    .help(shellModel.isSidebarVisible ? "Hide Sidebar (⌃⌘S)" : "Show Sidebar (⌃⌘S)")
    .accessibilityLabel(shellModel.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
  }
}

extension View {
  func appShellHeader(background: Color) -> some View {
    frame(height: AppMetrics.pageHeaderHeight)
      .background(background)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(AppColor.border)
          .frame(height: AppMetrics.hairline)
      }
  }
}

struct AppSectionHeader<Trailing: View>: View {
  let title: String
  let detail: String?
  @ViewBuilder let trailing: Trailing

  init(
    _ title: String,
    detail: String? = nil,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.detail = detail
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 12) {
      Text(title.uppercased())
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .tracking(0.4)
      if let detail {
        Text(detail)
          .font(.system(size: 11).monospacedDigit())
          .foregroundStyle(.tertiary)
      }
      Spacer()
      trailing
    }
  }
}

struct AppEmptyState: View {
  let title: String
  let message: String
  let symbol: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 22, weight: .regular))
        .foregroundStyle(.secondary)
        .frame(width: 44, height: 44)
        .background(AppColor.subtle)
        .clipShape(Circle())
      VStack(spacing: 5) {
        Text(title)
          .font(.system(size: 14, weight: .medium))
        Text(message)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: 340)
    .padding(32)
  }
}

struct AppStatusBadge: View {
  enum Tone {
    case neutral
    case success
    case warning
    case danger
  }

  let text: String
  var tone: Tone = .neutral

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: 10, weight: .semibold))
      .tracking(0.35)
      .foregroundStyle(foregroundColor)
      .padding(.horizontal, 7)
      .frame(height: 22)
      .background(backgroundColor)
      .clipShape(Capsule())
  }

  private var foregroundColor: Color {
    switch tone {
    case .neutral: .secondary
    case .success: AppColor.success
    case .warning: AppColor.warning
    case .danger: AppColor.danger
    }
  }

  private var backgroundColor: Color {
    foregroundColor.opacity(0.1)
  }
}

struct AppSheetHeader: View {
  let title: String
  let subtitle: String
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 18, weight: .semibold))
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: dismiss) {
        Image(systemName: "xmark")
      }
      .buttonStyle(.envIcon)
      .accessibilityLabel("Close")
    }
    .padding(.horizontal, 24)
    .frame(height: 76)
    .background(AppColor.surface)
  }
}

struct AppFieldLabel: View {
  let title: String
  let hint: String?

  init(_ title: String, hint: String? = nil) {
    self.title = title
    self.hint = hint
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
      if let hint {
        Text(hint)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct AppFormRow<Content: View>: View {
  let title: String
  let hint: String?
  @ViewBuilder let content: Content

  init(
    _ title: String,
    hint: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.hint = hint
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 20) {
      AppFieldLabel(title, hint: hint)
        .frame(width: 190, alignment: .leading)
      content
    }
    .padding(16)
  }
}

struct AppSettingsRow<Content: View>: View {
  let title: String
  let detail: String?
  @ViewBuilder let content: Content

  init(
    _ title: String,
    detail: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.detail = detail
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 20) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 12, weight: .medium))
        if let detail {
          Text(detail)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 20)
      content
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 58)
  }
}

struct AppDivider: View {
  let axis: Axis

  init(_ axis: Axis = .horizontal) {
    self.axis = axis
  }

  var body: some View {
    Rectangle()
      .fill(AppColor.border)
      .frame(
        width: axis == .vertical ? AppMetrics.hairline : nil,
        height: axis == .horizontal ? AppMetrics.hairline : nil
      )
  }
}
