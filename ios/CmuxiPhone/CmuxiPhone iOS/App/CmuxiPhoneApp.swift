import SwiftUI

@main
struct CmuxiPhoneApp: App {

    @StateObject private var sessionManager = WatchSessionManager.shared
    @StateObject private var relayService = RelayService.shared

    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if relayService.isPaired && !relayService.isAddingMac {
                    ConnectionStatusView()
                } else {
                    PairingView()
                }
            }
            .environmentObject(sessionManager)
            .environmentObject(relayService)
            .preferredColorScheme(.dark)
        }
    }
}
