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
            TitleBar()

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
        .background(WindowConfigurator())
    }
}

// MARK: - Titlebar / source bar

/// Unified custom titlebar (Final Cut-style): traffic lights · app title + tagline · (flex) ·
/// source well · Scan. The window uses `.hiddenTitleBar`, so the system buttons overlay our
/// leading inset.
private struct TitleBar: View {
    @EnvironmentObject private var vm: ConversionViewModel

    var body: some View {
        HStack(spacing: 14) {
            // Traffic-light inset (the system buttons render on top of this gap).
            Spacer().frame(width: 64)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("conjoyn")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.txt)
                Text("Split recordings, made whole")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.txt3)
            }
            .fixedSize()

            Spacer()

            CJPathWell(
                icon: "sdcard",
                path: vm.sourceFolderURL?.path,
                placeholder: "No source selected",
                choose: vm.chooseSourceFolder
            )

            Button {
                Task { await vm.scan() }
            } label: {
                Label(vm.isScanning ? "Scanning…" : "Scan", systemImage: "viewfinder")
            }
            .buttonStyle(.cjStandard)
            .disabled(vm.sourceFolderURL == nil || vm.isScanning)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.titlebar)
        .overlay(alignment: .bottom) { Color.black.opacity(0.5).frame(height: 1) }
    }
}

// MARK: - Window configuration

/// Applies NSWindow settings SwiftUI can't express: background dragging (the custom titlebar
/// area has no system drag region below the top strip) and a transparent system titlebar so
/// only the traffic lights show over our chrome.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
