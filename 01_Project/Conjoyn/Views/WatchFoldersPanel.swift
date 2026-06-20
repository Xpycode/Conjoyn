import SwiftUI
import AppKit

// MARK: - Watch Folders Panel (Wave 5D)

/// The secondary "Watch Folders" window: a list of user-configured ingest folders, each with an
/// enable switch, its chosen output destination, per-folder settings, and a live status readout.
/// Mirrors the app's existing surfaces — `CJSectionHead`, `CJPathWell`, `CJButtonStyle`, and the
/// `Theme` tokens — so it reads as native to Conjoyn.
struct WatchFoldersPanel: View {
    @EnvironmentObject private var manager: WatchFolderManager

    /// Non-nil while a rejected add (overlap / unreadable folder) is being surfaced.
    @State private var rejectionReason: String?

    var body: some View {
        VStack(spacing: 0) {
            CJSectionHead(title: "Watch Folders", count: "\(manager.entries.count)") {
                Button {
                    addFolder()
                } label: {
                    Label("Add Folder…", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.cjPrimary)
            }
            Theme.line.frame(height: 1)

            if manager.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.entries) { entry in
                            WatchFolderRow(entry: entry)
                                .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 320)
        .background(Theme.bg)
        .alert(
            "Can’t add that folder",
            isPresented: Binding(get: { rejectionReason != nil }, set: { if !$0 { rejectionReason = nil } })
        ) {
            Button("OK", role: .cancel) { rejectionReason = nil }
        } message: {
            Text(rejectionReason ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.txt3)
            Text("No watch folders yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.txt)
            Text("Add a folder and Conjoyn will auto-stitch DJI footage the moment a complete set lands in it.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.txt3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Add Folder…") { addFolder() }
                .buttonStyle(.cjStandard)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    /// Prompts for a directory and hands it to the manager; surfaces a rejection if the overlap
    /// policy (or an unreadable folder) forbids it.
    private func addFolder() {
        guard let url = Self.chooseDirectory(prompt: "Watch") else { return }
        if case .rejected(let reason) = manager.addFolder(rootURL: url) {
            rejectionReason = reason
        }
    }

    /// A directory picker shared by "Add Folder" and per-row "Choose output". Directories only.
    static func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Row

private struct WatchFolderRow: View {
    let entry: WatchFolderEntry
    @EnvironmentObject private var manager: WatchFolderManager
    @State private var showingSettings = false

    private var status: WatchFolderCoordinator.Status {
        manager.statuses[entry.id] ?? .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Line 1: enable + name + status + remove.
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { entry.enabled },
                    set: { manager.setEnabled(entry.id, $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.acc2)
                .labelsHidden()

                Text(entry.rootDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.txt)
                    .lineLimit(1)

                Spacer(minLength: 8)

                WatchStatusPill(status: status, enabled: entry.enabled)

                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.cjIcon)
                    .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                        WatchFolderSettingsForm(
                            settings: entry.settings,
                            commit: { manager.updateSettings(entry.id, $0) }
                        )
                    }

                Button { manager.remove(entry.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.cjIcon)
            }

            // Line 2: root path (read-only) + output picker.
            HStack(spacing: 8) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.txt3)
                Text(entry.rootPath)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.txt2)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            CJPathWell(
                icon: "folder",
                path: entry.outputPath,
                placeholder: "Output: next to source",
                height: 26,
                minWidth: 300
            ) {
                let url = WatchFoldersPanel.chooseDirectory(prompt: "Output")
                manager.setOutputFolder(entry.id, url: url)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(entry.enabled ? 1 : 0.6)
    }
}

// MARK: - Status pill

private struct WatchStatusPill: View {
    let status: WatchFolderCoordinator.Status
    let enabled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.3)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
    }

    private var label: String {
        guard enabled else { return "OFF" }
        switch status {
        case .idle:                         return "WAITING"
        case .watching(let n) where n > 0:  return "SETTLING \(n)"
        case .watching:                     return "WATCHING"
        case .queued(let n):                return "QUEUED \(n)"
        }
    }

    private var color: Color {
        guard enabled else { return Theme.txt3 }
        switch status {
        case .idle:                         return Theme.txt3
        case .watching(let n) where n > 0:  return Theme.acc1
        case .watching:                     return Theme.ok
        case .queued:                       return Theme.acc2
        }
    }
}

// MARK: - Settings popover

/// Per-folder tunables editor. Edits a draft and commits on dismiss (so a coordinator rebuild
/// happens once, not on every stepper tick).
private struct WatchFolderSettingsForm: View {
    @State private var draft: WatchFolderSettings
    let commit: (WatchFolderSettings) -> Void
    private let original: WatchFolderSettings

    init(settings: WatchFolderSettings, commit: @escaping (WatchFolderSettings) -> Void) {
        _draft = State(initialValue: settings)
        self.original = settings
        self.commit = commit
    }

    /// Split threshold expressed in GB for the stepper (stored as bytes).
    private var thresholdGB: Double { Double(draft.splitThreshold) / 1_000_000_000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folder settings")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.txt3)

            Stepper(value: $draft.quietWindow, in: 5...300, step: 5) {
                row("Quiet window", "\(Int(draft.quietWindow)) s")
            }
            Stepper(value: $draft.requiredStablePolls, in: 1...10) {
                row("Stable polls", "\(draft.requiredStablePolls)")
            }
            Stepper(value: $draft.pollInterval, in: 0.25...5, step: 0.25) {
                row("Poll interval", String(format: "%.2f s", draft.pollInterval))
            }
            Stepper(
                value: Binding(
                    get: { thresholdGB },
                    set: { draft.splitThreshold = Int64($0 * 1_000_000_000) }
                ),
                in: 0.5...5, step: 0.1
            ) {
                row("Split threshold", String(format: "%.1f GB", thresholdGB))
            }
        }
        .padding(16)
        .frame(width: 280)
        .onDisappear { if draft != original { commit(draft) } }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.txt)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.txt2)
        }
    }
}
