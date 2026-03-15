import SwiftUI

@main
struct CoachMobileAppApp: App {
    @StateObject private var viewModel = VoiceSessionViewModel()

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: viewModel)
        }
    }
}
