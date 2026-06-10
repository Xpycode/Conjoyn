import SwiftUI
import AppKit

// MARK: - Main window

// Single-window vertical flow per the 2026-06-10 design handoff
// (`02_Design/design_handoff_conjoyn/README.md`): titlebar/source bar → discovered recordings
// (hero) → output settings bar → job queue → collapsible console → footer. The five states
// (Empty → Scanning → Loaded → Running → Done) all live here; Running/Done are queue/footer
// states, not separate layouts.

struct ContentView: View {
    @EnvironmentObject private var vm: ConversionViewModel
    @EnvironmentObject private var queue: QueueManager

    var body: some View {
        VStack(spacing: 0) {
            // Recordings and the queue share a draggable boundary: the hero + output bar form the
            // top pane (selection/setup), the queue + its console the bottom pane. The divider sits
            // just above the queue, so the user can grow the queue when many jobs are running.
            VSplitView {
                VStack(spacing: 0) {
                    // Hero region: empty / scanning / loaded recordings.
                    Group {
                        if vm.isScanning {
                            ScanningStateView()
                        } else if vm.groups.isEmpty {
                            EmptyStateView()
                        } else {
                            RecordingsList()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    OutputBar()
                }
                .frame(minHeight: 220)

                VStack(spacing: 0) {
                    QueueSection()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ConsoleSection()
                }
                .frame(minHeight: 150)
            }

            FooterBar()
        }
        .frame(minWidth: 1000, minHeight: 640)
        .background(Theme.bg)
        // Native titlebar toolbar (App Shell Standard, matching Penumbra/CropBatch): the source path
        // well sits centered, Scan trailing. Replaces the old custom 52 pt TitleBar HStack — the
        // system traffic lights and the window drag region come for free with `.toolbarRole(.editor)`
        // + `.hiddenTitleBar`, so no NSWindow configurator is needed. App name/tagline dropped (the
        // window itself identifies the app).
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                CJPathWell(
                    icon: "sdcard",
                    path: vm.sourceFolderURL?.path,
                    placeholder: "No source selected",
                    choose: vm.chooseSourceFolder
                )
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await vm.scan() }
                } label: {
                    Label(vm.isScanning ? "Scanning…" : "Scan", systemImage: "viewfinder")
                }
                .buttonStyle(.cjStandard)
                .disabled(vm.sourceFolderURL == nil || vm.isScanning)
            }
        }
        .toolbarRole(.editor)
    }
}
