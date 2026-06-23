import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var relayService: RelayService
    @ObservedObject private var store = ConnectionStore.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage("connectionMode") private var connectionMode: ConnectionMode = .auto

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                superviseSection
                macsSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .task { relayService.refreshSupervise() }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.connections.isEmpty {
                        EditButton()
                            .foregroundStyle(Color.claudeOrange)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                    .foregroundStyle(Color.claudeOrange)
                }
            }
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            HStack {
                Text("검색")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Picker("검색", selection: $connectionMode) {
                    Text("자동").tag(ConnectionMode.auto)
                    Text("LAN").tag(ConnectionMode.lanOnly)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .listRowBackground(Color.cardBackground)
        } header: {
            Text("연결")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mutedText)
        } footer: {
            Text("자동은 로컬 네트워크에서 Bonjour로 브리지를 검색합니다.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.subtleText)
        }
    }

    private var superviseSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { relayService.superviseMode },
                set: { relayService.setSupervise($0) }
            )) {
                Text("감독 모드")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.claudeOrange)
            .listRowBackground(Color.cardBackground)
        } header: {
            Text("승인")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mutedText)
        } footer: {
            Text("켜면 모든 모드에서 Bash·Edit·Write 등 변경 도구가 실행 전 폰 승인을 거칩니다(승인 큐에 표시). 끄면 평소대로 자동 진행됩니다.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.subtleText)
        }
    }

    private var macsSection: some View {
        Section {
            ForEach(store.connections) { conn in
                Button {
                    relayService.switchTo(conn)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conn.name)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(conn.host):\(conn.port)")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Color.subtleText)
                        }
                        Spacer()
                        if conn.id == store.activeID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.claudeOrange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(Color.cardBackground)
            }
            .onDelete { offsets in
                for i in offsets {
                    let conn = store.connections[i]
                    if conn.id == store.activeID {
                        relayService.forgetActive()
                    } else {
                        store.remove(conn.id)
                    }
                }
            }

            Button {
                relayService.beginAddMac()
                dismiss()
            } label: {
                Label("다른 Mac 추가", systemImage: "plus")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.claudeOrange)
            }
            .listRowBackground(Color.cardBackground)
        } header: {
            Text("MAC")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mutedText)
        } footer: {
            Text("탭하여 전환 · 스와이프하여 삭제")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.subtleText)
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("버전")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.subtleText)
            }
            .listRowBackground(Color.cardBackground)

            Link(destination: URL(string: "https://claude.com/claude-code")!) {
                HStack {
                    Text("Claude Code")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.subtleText)
                }
                .contentShape(Rectangle())
            }
            .listRowBackground(Color.cardBackground)
        } header: {
            Text("정보")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mutedText)
        }
    }
}

// MARK: - Connection Mode

enum ConnectionMode: String {
    case auto
    case lanOnly
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(RelayService.shared)
}
