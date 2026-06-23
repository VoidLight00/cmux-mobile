import SwiftUI

/// Neutral glyph for the Codex agent. Uses a generic code SF Symbol (no OpenAI/
/// Codex brand asset) — "Codex" is shown only as a text label elsewhere.
struct CodexLogo: View {
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: "chevron.left.forwardslash.chevron.right")
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        CodexLogo(size: 24)
        CodexLogo(size: 32)
        CodexLogo(size: 48)
    }
    .padding()
    .background(Color.black)
}
