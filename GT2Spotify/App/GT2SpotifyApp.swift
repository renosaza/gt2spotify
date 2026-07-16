import SwiftUI

@main
@MainActor
struct GT2SpotifyApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: container.dashboardViewModel)
                .onOpenURL { url in
                    container.dashboardViewModel.handleOAuthCallback(url)
                }
        }
    }
}
