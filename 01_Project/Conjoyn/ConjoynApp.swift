import SwiftUI

@main
struct ConjoynApp: App {
    /// Owns the front-end state and the shared `QueueManager`. Both are injected into the view tree
    /// so any view can observe queue/console/progress changes.
    @StateObject private var viewModel = ConversionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.queue)
                .preferredColorScheme(.dark)
        }
        // Unified custom titlebar per the design handoff — the 52 pt source bar IS the titlebar,
        // with the system traffic lights overlaying its leading inset (Penumbra app-shell pattern).
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 800)
    }
}
