import SwiftUI

@main
@MainActor
struct GT2SpotifyApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            TabView {
                DashboardView(viewModel: container.dashboardViewModel)
                    .tabItem { Label("Spotify", systemImage: "music.note") }
                BluetoothDashboardView(controller: container.bluetoothController)
                    .tabItem { Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right") }
            }
            .onOpenURL { url in
                container.dashboardViewModel.handleOAuthCallback(url)
            }
        }
    }
}
