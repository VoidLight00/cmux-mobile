import SwiftUI

/// The app's own logo — a neutral SF Symbol (no bundled brand asset). Suggests
/// the phone↔agent bridge this app provides.
struct AppLogo: View {
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
    }
}

/// Neutral glyph for the Claude agent. Uses a generic SF Symbol (no Anthropic
/// brand asset) — "Claude" is shown only as a text label elsewhere.
struct ClaudeMascot: View {
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: "sparkles")
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        AppLogo(size: 32)
        ClaudeMascot(size: 24)
        ClaudeMascot(size: 32)
        ClaudeMascot(size: 48)
    }
    .padding()
    .background(Color.black)
}
