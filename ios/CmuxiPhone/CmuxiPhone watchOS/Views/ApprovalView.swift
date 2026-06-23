import SwiftUI

struct ApprovalView: View {
    @Environment(\.dismiss) private var dismiss

    let request: ApprovalRequest

    // BETA SCOPE: the Watch shows the approval for awareness but does NOT answer
    // it. The bridge's codex approval path is fail-closed (requires a pinned
    // terminalId + live screen hash that only the iPhone sends), so answering
    // from the Watch would either be rejected or, worse, look successful while
    // the agent kept waiting. Until the Watch path is made transactional + pins
    // the terminal/hash, approvals are answered on the iPhone. No middle state.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let question = request.question {
                    Text(question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Do you want to \(request.toolName.lowercased())?")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }

                if !request.actionSummary.isEmpty && request.actionSummary != request.toolName {
                    Text(request.actionSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.Accent.approval)
                        .lineLimit(3)
                }

                // Read-only option list (what's being asked) — not tappable.
                ForEach(Array(request.options.enumerated()), id: \.element.id) { index, option in
                    HStack(spacing: 6) {
                        Text("\(index + 1).")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.Text.secondary)
                        Text(option.label)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Text.secondary)
                            .lineLimit(2)
                        Spacer()
                    }
                }

                Divider().background(Theme.Text.dimmed)

                // The actual call to action for this beta.
                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Accent.approval)
                    Text("iPhone에서 승인하세요")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Accent.approval.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.Accent.approval.opacity(0.4), lineWidth: 1)
                )

                Button("닫기") { dismiss() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.Text.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
        .background(Theme.Background.primary)
    }
}

#Preview {
    ApprovalView(
        request: ApprovalRequest(
            toolName: "AskUserQuestion",
            actionSummary: "Goal",
            question: "Before we dig in — what's your goal with this?",
            options: [
                .init(label: "Building a startup", description: "You're building a company"),
                .init(label: "Hackathon / fun", description: "Time-boxed project"),
                .init(label: "Open source", description: "Building for a community"),
            ]
        )
    )
    .environmentObject(WatchViewState.shared)
}
