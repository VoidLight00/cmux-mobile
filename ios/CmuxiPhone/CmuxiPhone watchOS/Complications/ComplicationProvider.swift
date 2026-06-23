import WidgetKit
import SwiftUI

// MARK: - Cmux iPhone Complication (WidgetKit)

/// Timeline entry representing the current state of the Claude session.
struct CmuxiPhoneEntry: TimelineEntry {
    let date: Date
    let lastOutputLine: String
    let status: Status

    enum Status: String {
        case idle = "Idle"
        case running = "Running"
        case offline = "Offline"

        var color: Color {
            switch self {
            case .idle: return Theme.Text.secondary
            case .running: return Theme.Accent.success
            case .offline: return Theme.Accent.error
            }
        }
    }

    static var placeholder: CmuxiPhoneEntry {
        CmuxiPhoneEntry(
            date: Date(),
            lastOutputLine: "Ready",
            status: .idle
        )
    }
}

// MARK: - Timeline Provider

struct CmuxiPhoneTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CmuxiPhoneEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CmuxiPhoneEntry) -> Void) {
        let entry = currentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CmuxiPhoneEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh every 5 minutes when idle, every 30 seconds when running
        let refreshInterval: TimeInterval = entry.status == .running ? 30 : 300
        let nextUpdate = Date().addingTimeInterval(refreshInterval)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func currentEntry() -> CmuxiPhoneEntry {
        let session = WatchViewState.shared

        let status: CmuxiPhoneEntry.Status
        switch session.sessionState.connection {
        case .disconnected:
            status = .offline
        case .connected where session.sessionState.activity == .running:
            status = .running
        default:
            status = .idle
        }

        let lastLine = session.terminalLines.last?.text ?? "No output"

        return CmuxiPhoneEntry(
            date: Date(),
            lastOutputLine: String(lastLine.prefix(50)),
            status: status
        )
    }
}

// MARK: - Rectangular Complication View

struct CmuxiPhoneRectangularView: View {
    let entry: CmuxiPhoneEntry

    var body: some View {
        HStack(spacing: 6) {
            // Mini mascot
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.Text.primary)
                .frame(width: 16, height: 16)
                .overlay(
                    Text("C")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                )

            VStack(alignment: .leading, spacing: 2) {
                // Status line
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.status.color)
                        .frame(width: 6, height: 6)

                    Text(entry.status.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(entry.status.color)
                }

                // Last output line
                Text(entry.lastOutputLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .widgetURL(URL(string: "cmuxiphone://session"))
    }
}

// MARK: - Widget Definition
// Note: @main belongs on this struct when it lives in its own Widget Extension target.
// If sharing the same target as the app, remove @main and register via WidgetBundle.

struct CmuxiPhoneComplication: Widget {
    let kind = "CmuxiPhoneComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CmuxiPhoneTimelineProvider()) { entry in
            CmuxiPhoneRectangularView(entry: entry)
                .containerBackground(Theme.Background.primary, for: .widget)
        }
        .configurationDisplayName("Cmux iPhone")
        .description("Shows Claude session status and latest output.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Preview

#Preview(as: .accessoryRectangular) {
    CmuxiPhoneComplication()
} timeline: {
    CmuxiPhoneEntry(date: Date(), lastOutputLine: "Build succeeded", status: .idle)
    CmuxiPhoneEntry(date: Date(), lastOutputLine: "Installing deps...", status: .running)
    CmuxiPhoneEntry(date: Date(), lastOutputLine: "---", status: .offline)
}
