import SwiftUI

struct BrandMark: View {
  var size: CGFloat = 32

  var body: some View {
    ZStack {
      Circle().fill(.primary)
      ForEach([0.0, 60.0, 120.0], id: \.self) { angle in
        Capsule()
          .fill(Color(nsColor: .windowBackgroundColor))
          .frame(width: size * 0.13, height: size * 0.55)
          .rotationEffect(.degrees(angle))
      }
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("EnvStore")
  }
}
