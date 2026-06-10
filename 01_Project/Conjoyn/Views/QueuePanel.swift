import SwiftUI
import AppKit

// MARK: - Output bar, job queue, console, footer

// SwiftUI port of the handoff's `conjoyn/queue.jsx` against `styles.css` metrics.

// MARK: Output settings bar

struct OutputBar: View {
    @EnvironmentObject private var vm: ConversionViewModel
    @State private var showMoreOptions = false
    @State private var showRename = false

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Text("Output")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.txt3)
                    .fixedSize()
                CJPathWell(
                    icon: "folder",
                    path: vm.outputFolderURL?.path,
                    placeholder: "No destination",
                    height: 26,
                    minWidth: 230,
                    choose: vm.chooseOutputFolder
                )
            }
            .popover(isPresented: $vm.showApplyFolderPrompt, arrowEdge: .bottom) {
                ApplyFolderPopover().environmentObject(vm)
            }

            Spacer()

            OptionSwitch(label: "Fix recording date", isOn: $vm.settings.fixCreationDate)
            OptionSwitch(label: "Timecode from recording time", isOn: $vm.settings.preserveTimecode)
            OptionSwitch(label: "Stitch telemetry", isOn: $vm.settings.stitchSRT)

            // Fourth switch: turning it ON opens the rename popover; the popover's ✕ turns it OFF
            // (which closes the popover via the onChange below). Clicking away just dismisses the
            // panel — renaming stays on with the last pattern intact (re-toggle to edit again).
            OptionSwitch(label: "Rename files", isOn: $vm.renameEnabled)
                .popover(isPresented: $showRename, arrowEdge: .top) {
                    RenamePopover { vm.renameEnabled = false }
                        .environmentObject(vm)
                }
                .onChange(of: vm.renameEnabled) { _, on in showRename = on }

            // The handoff bar carries only the three core switches; the engine's remaining knobs
            // (container, filename, re-encode, delete-after-verify) live behind this gear.
            Button { showMoreOptions.toggle() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.cjIcon)
            .help("More output options")
            .popover(isPresented: $showMoreOptions, arrowEdge: .bottom) {
                MoreOptionsPopover()
                    .environmentObject(vm)
            }

            Button(vm.selectedCount > 0 ? "Add \(vm.selectedCount) to Queue" : "Add to Queue") {
                vm.addToQueue()
            }
            .buttonStyle(.cjPrimary)
            .disabled(!vm.canAddToQueue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.panel)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}

/// Labeled 30 × 18-style switch per `styles.css .out-opt` — a real `Toggle` re-tinted, per the
/// handoff's "prefer native controls" guidance.
private struct OptionSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.txt2)
                // Refuse to wrap/truncate: each switch label must report its full intrinsic width so
                // the Output bar's true minimum drives `.windowResizability(.contentMinSize)` (the
                // window floor = the point where the Spacer hits zero), instead of silently
                // compressing ("Output"→"utput", "Timecode…" wrapping) at too-narrow widths.
                .fixedSize()
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Theme.acc2)
    }
}

/// Engine knobs that didn't make the design bar — unchanged functionality, relocated.
private struct MoreOptionsPopover: View {
    @EnvironmentObject private var vm: ConversionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Output Options")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.txt2)

            Picker("Container", selection: $vm.settings.outputContainer) {
                ForEach(ConversionSettings.OutputContainer.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Filename")
                    .frame(width: 64, alignment: .leading)
                TextField("From clip name", text: $vm.settings.outputFilename)
                    .textFieldStyle(.roundedBorder)
            }
            .font(.system(size: 12))

            Toggle("Use source folder name", isOn: $vm.settings.useFolderNameAsFilename)
            Toggle("Re-encode if segments mismatch", isOn: $vm.settings.reEncodeOnMismatch)
            Toggle("Delete originals after verify", isOn: $vm.settings.deleteOriginalsAfterVerify)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Theme.acc2)
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 300)
    }
}

/// Part B of output-folder ↔ queue clarity: shown when the Output folder changes while pending jobs
/// exist. **Apply** re-points the pending jobs to the new folder; **Keep** (and click-away) is the
/// safe no-op that leaves each job at the destination frozen when it was queued.
private struct ApplyFolderPopover: View {
    @EnvironmentObject private var vm: ConversionViewModel

    private var count: Int { vm.pendingJobCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apply new output folder to \(count) pending job\(count == 1 ? "" : "s")?")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.txt2)
                .fixedSize(horizontal: false, vertical: true)

            if let name = vm.outputFolderURL?.lastPathComponent {
                Text("Queued jobs keep the folder they were added with. Apply moves the pending "
                     + "ones to “\(name)”. Started and finished jobs are never changed.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.txt3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Keep") { vm.showApplyFolderPrompt = false }
                    .buttonStyle(.cjGhost)
                Button("Apply") { vm.applyOutputFolderToPendingJobs() }
                    .buttonStyle(.cjPrimary)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

// MARK: Queue

struct QueueSection: View {
    @EnvironmentObject private var queue: QueueManager

    var body: some View {
        VStack(spacing: 0) {
            CJSectionHead(
                title: "Queue",
                count: queue.jobs.isEmpty ? nil
                    : "\(queue.jobs.count) \(queue.jobs.count == 1 ? "job" : "jobs")"
            ) {
                HStack(spacing: 8) {
                    if queue.completedCount + queue.failedCount > 0 {
                        Button("Clear Finished") { queue.clearFinishedJobs() }
                            .buttonStyle(.cjGhost)
                            .font(.system(size: 11))
                    }
                    if !queue.jobs.isEmpty {
                        Button("Clear Queue") { queue.clearAllJobs() }
                            .buttonStyle(.cjGhost)
                            .font(.system(size: 11))
                            .help("Remove all jobs (a running job keeps going — press Stop first to abandon it)")
                    }
                }
            }
            .overlay(alignment: .top) { Theme.line.frame(height: 1) }

            if queue.jobs.isEmpty {
                Text("No jobs yet — select recordings above and press “Add to Queue”.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.txt3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(queue.jobs) { job in
                            QueueRow(job: job)
                        }
                    }
                }
            }
        }
    }
}

private struct QueueRow: View {
    let job: ConversionJob
    @EnvironmentObject private var queue: QueueManager
    // Observed so the badge/sub-line clear or appear reactively when the Output folder changes.
    @EnvironmentObject private var vm: ConversionViewModel

    // Per-row, session-only: the disclosure expand state and its lazily-built timecode readout.
    @State private var expanded = false
    @State private var disclosure: TimecodeDisclosure?

    /// A pending job whose frozen destination folder no longer matches the current Output setting —
    /// the stale case the user can fix via *Choose…* → Apply. Only `.pending` jobs are re-pointable.
    private var folderMismatch: Bool {
        job.status == .pending &&
        QueueManager.directoriesDiffer(job.destinationURL.deletingLastPathComponent(), vm.outputFolderURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.cjIcon)
                .frame(width: 14)
                .help(expanded ? "Hide timecode detail" : "Show timecode detail")

                Text(job.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.txt)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 220, alignment: .leading)
                    .help(job.destinationURL.path)

                if folderMismatch {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.acc1)
                        .help("This job targets a different folder than the current Output setting")
                }

                CJProgressBar(fraction: barFraction, fill: barFill)

                Text(statusText)
                    .font(.system(size: 11, weight: statusBold ? .semibold : .regular))
                    .foregroundStyle(statusColor)
                    .frame(width: 84, alignment: .leading)

                HStack(spacing: 4) {
                    if isFailedOrCancelled {
                        Button { queue.retryJob(job.id) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.cjIcon)
                        .help("Retry")
                    }
                    if job.status == .completed {
                        Button {
                            if let url = job.actualOutputURLs.first {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.cjIcon)
                        .help("Reveal in Finder")
                    }
                    if job.status == .pending || isFailedOrCancelled {
                        Button { queue.removeJob(job.id) } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.cjIcon)
                        .help("Remove from queue")
                    }
                }
                .frame(width: 52, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .help(failureMessage ?? "")

            // Always visible (not gated by the caret) when the destination is stale, so the user
            // sees where this job will actually land before pressing Start.
            if folderMismatch {
                Text("⚠ → \(job.destinationURL.deletingLastPathComponent().path)  (≠ current output)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.acc1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 26)
                    .padding(.bottom, 6)
            }

            if expanded {
                TimecodeDisclosurePanel(disclosure: disclosure, destination: job.destinationURL)
                    .padding(.leading, 26)   // align under the name, clear of the caret
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        // Recompute only when the row is bound to a different job. The build reads the job's frozen
        // clips + settings, so the values shown always match what the engine stamps for this job.
        .task(id: job.id) {
            disclosure = await TimecodeDisclosure.build(clips: job.clips, settings: job.settings)
        }
    }

    private var isActive: Bool { job.status == .active || job.status == .preparing }
    private var isFailedOrCancelled: Bool {
        if case .failed = job.status { return true }
        return job.status == .cancelled
    }

    private var failureMessage: String? {
        if case .failed(let msg) = job.status { return msg }
        return nil
    }

    private var barFraction: Double {
        switch job.status {
        case .completed: return 1
        case .pending:   return 0
        default:         return job.progress
        }
    }

    private var barFill: CJProgressBar.Fill {
        switch job.status {
        case .completed: return .done
        case .failed:    return .failed
        default:         return .running
        }
    }

    private var statusText: String {
        switch job.status {
        case .pending:   return "Queued"
        case .preparing: return "Preparing…"
        case .active:
            return job.verificationStatus == .verifying ? "Verifying…" : "Joining…"
        case .completed: return "Done"
        case .failed:    return "Failed"
        case .cancelled: return "Stopped"
        }
    }

    private var statusBold: Bool {
        isActive || job.status == .completed || isFailedOrCancelled
    }

    private var statusColor: Color {
        switch job.status {
        case .pending:   return Theme.txt2
        case .preparing, .active: return Theme.acc1
        case .completed: return Theme.ok
        case .failed:    return Theme.bad
        case .cancelled: return Theme.txt2
        }
    }
}

/// The per-row timecode disclosure (rename-and-tc-disclosure, Part 2). Shows DJI's inert source
/// `tmcd` beside the timecode Conjoyn actually applies (with its origin + the fps used for the frame
/// component), plus the slow-mo caption when relevant. `nil` while the async build is in flight.
private struct TimecodeDisclosurePanel: View {
    let disclosure: TimecodeDisclosure?
    /// The job's frozen output path — its parent folder is shown as the always-on "Output" row
    /// (the transparency half of the Hybrid: every expanded row reveals where the file will land).
    let destination: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let d = disclosure {
                // Source TC — the camera's original, visibly inert (DJI is almost always "—").
                HStack(spacing: 8) {
                    label("Source TC")
                    Text(d.sourceTimecode ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.txt3)
                }

                if d.timecodeEnabled {
                    if let applied = d.appliedTimecode {
                        HStack(spacing: 8) {
                            label("Applied TC")
                            Text(applied)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.acc1)
                            Text("· \(d.originTag) · \(d.frameRateLabel) fps")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.txt2)
                        }
                    } else {
                        Text("No recording-start signal — timecode not stamped.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.txt3)
                    }
                } else {
                    Text("Timecode from recording time is off — source timecode passed through.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.txt3)
                }

                if d.isSlowMotion {
                    Text("Slow-mo: timecode starts at the real recording time and advances at the "
                         + "file's playback rate (\(d.frameRateLabel) fps).")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Reading timecode…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.txt3)
            }

            // Always-on transparency: where this job's file will actually be written.
            HStack(spacing: 8) {
                label("Output")
                Text(destination.deletingLastPathComponent().path)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.txt2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.txt3)
            .frame(width: 72, alignment: .leading)
    }
}

// MARK: Console

struct ConsoleSection: View {
    @EnvironmentObject private var queue: QueueManager
    @State private var isOpen = false

    private var lines: [Substring] {
        queue.consoleLog.isEmpty ? [] : queue.consoleLog.split(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Text("Console")
                    .font(.system(size: 11, weight: .semibold))
                if !lines.isEmpty {
                    Text("\(lines.count) lines")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                Spacer()
                if isOpen, !lines.isEmpty {
                    Button("Clear") { queue.clearConsole() }
                        .buttonStyle(.cjGhost)
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(Theme.txt3)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { isOpen.toggle() }

            if isOpen {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if lines.isEmpty {
                                Text("— idle —")
                                    .foregroundStyle(Theme.txt3)
                            }
                            ForEach(lines.indices, id: \.self) { i in
                                Text(lines[i])
                                    .foregroundStyle(lineColor(lines[i]))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("console-bottom")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                    }
                    .frame(height: 130)
                    .onChange(of: queue.consoleLog) { _, _ in
                        proxy.scrollTo("console-bottom", anchor: .bottom)
                    }
                    .onAppear {
                        proxy.scrollTo("console-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Theme.consoleBG)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }

    /// Best-effort log-line tinting per the prototype's cmd/info/ok/bad kinds.
    private func lineColor(_ line: Substring) -> Color {
        if line.hasPrefix("$") { return Theme.txt2 }
        let lower = line.lowercased()
        if lower.contains("✓") || lower.hasPrefix("done") { return Theme.ok }
        if lower.contains("error") || lower.contains("failed") || lower.contains("✗") {
            return Theme.bad
        }
        return Theme.txt3
    }
}

// MARK: Footer

struct FooterBar: View {
    @EnvironmentObject private var queue: QueueManager

    private var total: Int { queue.jobs.count }
    private var done: Int { queue.completedCount }
    private var failed: Int { queue.failedCount }
    private var allFinished: Bool {
        total > 0 && queue.jobs.allSatisfy(\.status.isFinished) && !queue.isProcessing
    }

    var body: some View {
        VStack(spacing: 6) {
            if let warning = queue.slowSpeedWarning {
                noticeRow(
                    icon: "exclamationmark.triangle.fill", color: Theme.acc1,
                    text: "\(warning.message) • \(warning.formattedRemaining)"
                )
            }
            if let persistErr = queue.persistenceError {
                noticeRow(
                    icon: "externaldrive.badge.exclamationmark", color: Theme.bad,
                    text: persistErr
                )
            }

            HStack(spacing: 16) {
                if queue.isProcessing {
                    Button("Stop") { queue.stopAllProcessing() }
                        .buttonStyle(.cjStopLarge)
                } else {
                    Button("Start") { queue.startQueue() }
                        .buttonStyle(.cjPrimaryLarge)
                        .disabled(!queue.hasPendingJobs)
                }

                CJProgressBar(
                    fraction: queue.overallProgress,
                    fill: allFinished && failed == 0 ? .done : .running
                )

                Group {
                    if total == 0 {
                        Text("Queue empty")
                    } else if allFinished {
                        Text("✓ \(done) of \(total) joined, \(failed) failed")
                            .foregroundStyle(failed == 0 ? Theme.ok : Theme.bad)
                            .fontWeight(.semibold)
                    } else {
                        (Text("\(done)").bold().foregroundStyle(Theme.txt)
                            + Text(" of ")
                            + Text("\(total)").bold().foregroundStyle(Theme.txt)
                            + Text(" joined · \(failed) failed"))
                    }
                }
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.txt2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.panel)
        .overlay(alignment: .top) { Theme.lineStrong.frame(height: 1) }
    }

    private func noticeRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 11)).foregroundStyle(color)
            Spacer()
        }
    }
}
