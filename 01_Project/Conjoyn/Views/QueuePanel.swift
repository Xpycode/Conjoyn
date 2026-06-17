import SwiftUI
import AppKit
import SwiftTimecodeCore
import SwiftTimecodeUI

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
    @State private var bannerDismissed = false

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
                if queue.restoredJobCount > 0 && !bannerDismissed {
                    RestoreBanner(count: queue.restoredJobCount,
                                  onDismiss: { bannerDismissed = true },
                                  onClearPending: {
                                      queue.clearPendingJobs()
                                      bannerDismissed = true
                                  })
                }
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

                // No bar for a not-yet-started job — an empty track reads as a heavy black rectangle.
                // A clear filler of the same footprint keeps the status column aligned.
                if job.status == .pending {
                    Color.clear.frame(height: 5)
                } else {
                    CJProgressBar(fraction: barFraction, fill: barFill)
                }

                Text(statusText)
                    .font(.system(size: 11, weight: statusBold ? .semibold : .regular))
                    .foregroundStyle(statusColor)
                    .frame(width: 84, alignment: .leading)

                liveMetrics
                    .frame(width: 140, alignment: .leading)

                HStack(spacing: 4) {
                    if job.status == .completed {
                        VerificationSeal(status: job.verificationStatus, isDeep: job.isDeepVerifying)
                    }
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
                TimecodeDisclosurePanel(disclosure: disclosure, job: job)
                    .padding(.leading, 26)   // align under the name, clear of the caret
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        // Recompute whenever the job identity or its manual TC override changes. The compound key
        // fires a new task when the user types a timecode override into the row, so the disclosure
        // rebuilds reactively without requiring a full job replacement.
        .task(id: "\(job.id)-\(job.timecodeStringOverride ?? "")") {
            disclosure = await TimecodeDisclosure.build(
                clips: job.clips, settings: job.settings, tcOverride: job.timecodeStringOverride
            )
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

    /// While verifying, distinguish the fast structural check from the escalated byte-exact hash
    /// (which takes far longer) so a deep-checking job doesn't read as stuck.
    private var verifyingLabel: String {
        job.isDeepVerifying ? "Verifying (byte-exact)…" : "Verifying…"
    }

    private var statusText: String {
        switch job.status {
        case .pending:   return "Queued"
        case .preparing: return "Preparing…"
        case .active:
            if job.verificationStatus == .verifying { return verifyingLabel }
            return job.clips.count == 1 ? "Processing…" : "Joining…"
        case .completed:
            return job.verificationStatus == .verifying ? verifyingLabel : "Done"
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

    /// Live speed + time-remaining for the active job, ticking once a second so the countdown advances
    /// smoothly between ffmpeg progress callbacks. Speed comes from ffmpeg's `speed=` (`activeMetrics`);
    /// the ETA is the history-independent `elapsed / progress` extrapolation off the job's own
    /// `progress`/`startedAt`, falling back to the pre-job historical estimate before 5% progress so
    /// the row never shows a blank while preparing. For inactive rows, shows a static summary of
    /// clip count, duration, and source size.
    @ViewBuilder
    private var liveMetrics: some View {
        if isActive, job.id == queue.currentJobId {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let metrics = ProgressMetrics(progress: job.progress, startTime: job.startedAt)
                HStack(spacing: 6) {
                    if let speed = queue.activeMetrics?.formattedSpeed {
                        Text(speed.replacingOccurrences(of: "x", with: "×"))
                    }
                    if let remaining = metrics.formattedRemaining(at: context.date) {
                        Text("~\(remaining) left")
                    } else if let estimate = queue.currentJobEstimate {
                        Text("\(estimate.formattedEstimate) left")
                    }
                }
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Theme.txt2)
                .lineLimit(1)
            }
        } else if !isActive {
            HStack(spacing: 6) {
                Text(job.clips.count == 1 ? "SINGLE" : "\(job.clips.count) files")
                    .font(.system(size: 10, weight: .semibold))
                Text("·")
                Text(CJFormat.duration(job.totalContentDurationSeconds))
                Text("·")
                Text(CJFormat.size(job.totalSourceBytes))
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.txt3)
            .lineLimit(1)
        }
    }
}

/// The per-row timecode disclosure (rename-and-tc-disclosure, Part 2). Shows DJI's inert source
/// `tmcd` beside the timecode Conjoyn actually applies (with its origin + the fps used for the frame
/// component), plus the slow-mo caption when relevant. `nil` while the async build is in flight.
private struct TimecodeDisclosurePanel: View {
    let disclosure: TimecodeDisclosure?
    /// The whole job — drives the always-on "Output" row plus the source↔target verification detail
    /// (chip row of non-pass checks, the thorough-verify button, and its progress).
    let job: ConversionJob
    @EnvironmentObject private var queue: QueueManager

    @State private var tcComponents: SwiftTimecodeCore.Timecode.Components = .zero
    @State private var overrideActive: Bool = false
    @State private var showOverridePopover: Bool = false

    /// The job's frozen output path — its parent folder is shown as the always-on "Output" row
    /// (the transparency half of the Hybrid: every expanded row reveals where the file will land).
    private var destination: URL { job.destinationURL }

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
                    // Applied TC row — pencil button at the end opens the override popover.
                    HStack(spacing: 8) {
                        label("Applied TC")
                        if let applied = d.appliedTimecode {
                            Text(applied)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.acc1)
                            Text("· \(d.originTag) · \(d.frameRateLabel) fps")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.txt2)
                        } else {
                            Text("no signal")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.txt3)
                        }
                        Button {
                            showOverridePopover.toggle()
                        } label: {
                            Image(systemName: overrideActive ? "pencil.circle.fill" : "pencil.circle")
                                .foregroundStyle(overrideActive ? Theme.acc2 : Theme.txt2)
                        }
                        .buttonStyle(.plain)
                        .help(overrideActive ? "Edit or revert TC override" : "Override timecode")
                        .popover(isPresented: $showOverridePopover, arrowEdge: .trailing) {
                            overridePopover(rate: tcFrameRate(from: d.frameRate))
                        }
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

            // Source↔target verification — only meaningful once the join has finished.
            if job.status == .completed {
                verificationSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { loadOverrideFromJob() }
        .onChange(of: job.timecodeStringOverride) { _, _ in loadOverrideFromJob() }
    }

    // MARK: - TC override helpers

    private func tcFrameRate(from fps: Double) -> TimecodeFrameRate {
        TimecodeFrameRate(stringValue: String(format: "%.3g", fps)) ?? .fps25
    }

    @ViewBuilder
    private func overridePopover(rate: TimecodeFrameRate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Override timecode")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            TimecodeField(components: $tcComponents, at: rate)
                .timecodeValidationStyle(.orange)
                .timecodeFieldInputStyle(.autoAdvance)
            HStack(spacing: 12) {
                Button("Set") {
                    applyOverride()
                    showOverridePopover = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.acc2)
                .font(.system(size: 11, weight: .medium))
                .keyboardShortcut(.defaultAction)
                if overrideActive {
                    Button("Revert") {
                        clearOverride()
                        showOverridePopover = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.txt3)
                    .font(.system(size: 11))
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(14)
    }

    private func applyOverride() {
        let s = String(format: "%02d:%02d:%02d:%02d",
                       tcComponents.hours, tcComponents.minutes,
                       tcComponents.seconds, tcComponents.frames)
        queue.updateTimecodeOverride(for: job.id, timecode: s)
        overrideActive = true
    }

    private func clearOverride() {
        queue.updateTimecodeOverride(for: job.id, timecode: nil)
        tcComponents = .zero
        overrideActive = false
    }

    private func loadOverrideFromJob() {
        let rate = tcFrameRate(from: disclosure?.frameRate ?? 30)
        if let s = job.timecodeStringOverride,
           let tc = try? SwiftTimecodeCore.Timecode(.string(s), at: rate, by: .allowingInvalid) {
            tcComponents = tc.components
            overrideActive = true
        } else {
            tcComponents = .zero
            overrideActive = false
        }
    }

    /// The verify detail: non-pass check chips (a green seal = nothing to show), the manual
    /// byte-exact button + its caption, and the hash progress bar while a thorough pass runs.
    @ViewBuilder
    private var verificationSection: some View {
        // Only the checks worth flagging — an all-pass result correctly renders an empty row,
        // because the green seal already says everything matched.
        let flagged = (job.sourceTargetResult?.checks ?? []).filter { $0.severity >= .warning }

        Divider()
            .overlay(Theme.line)
            .padding(.vertical, 4)

        HStack(spacing: 8) {
            label("Verify")
            if flagged.isEmpty {
                Text(job.verificationStatus == .verifying
                     ? (job.isDeepVerifying
                        ? "Byte-exact hashing output against sources…"
                        : "Checking output against sources…")
                     : "No issues flagged.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.txt3)
            } else {
                HStack(spacing: 4) {
                    ForEach(flagged, id: \.kind) { check in
                        VerificationChip(check: check)
                    }
                }
            }
        }

        if job.verificationStatus == .verifying {
            CJProgressBar(fraction: job.verificationProgress)
                .frame(maxWidth: 220)
                .padding(.leading, 80)
        }

        VStack(alignment: .leading, spacing: 2) {
            Button("Thorough verify (byte-exact)") {
                queue.verifyJobThorough(jobId: job.id)
            }
            .buttonStyle(.cjGhost)
            .font(.system(size: 11))
            .disabled(job.verificationStatus == .verifying)

            Text("Hashes kept streams (v:0/a:0) end-to-end.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.txt3)
        }
        .padding(.leading, 80)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.txt3)
            .frame(width: 72, alignment: .leading)
    }
}

// MARK: - Verification seal + chip

/// The green/orange/red/spinner seal shown on a completed queue row — the cheap visual proof that
/// the joined output matched (or didn't match) its sources. Mirrors the `IntegrityChip`/folder-mismatch
/// language: a single SF Symbol in a Theme tint, with the reason in its `.help()` tooltip.
private struct VerificationSeal: View {
    let status: VerificationStatus
    var isDeep: Bool = false

    @State private var spin = false

    var body: some View {
        let s = style
        Image(systemName: s.icon)
            .font(.system(size: 13))
            .foregroundStyle(s.color)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .help(s.help)
            .onAppear {
                spin = (status == .verifying)
            }
            .onChange(of: status) { _, new in
                if new == .verifying {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
                } else {
                    withAnimation(nil) { spin = false }
                }
            }
    }

    /// One place that turns the status enum (with its associated reasons) into icon + tint + tooltip,
    /// so the view stays a flat declaration.
    private var style: (icon: String, color: Color, help: String) {
        switch status {
        case .verified:
            return ("checkmark.seal.fill", Theme.ok, "Verified — output matches its sources.")
        case .warning(let reason):
            return ("exclamationmark.seal.fill", Theme.acc1, reason)
        case .failed(let reason):
            return ("xmark.seal.fill", Theme.bad, reason)
        case .verifying:
            return ("arrow.triangle.2.circlepath", Theme.acc1,
                    isDeep ? "Verifying (byte-exact hash) output against sources…"
                           : "Verifying output against sources…")
        case .unverified:
            return ("questionmark.circle", Theme.txt3, "Not yet verified.")
        }
    }
}

/// One inline source↔target check flag — a near-sibling of `IntegrityChip`. Warnings borrow the
/// established orange ⚠ treatment; failures escalate to red. The full explanation is in the tooltip.
private struct VerificationChip: View {
    let check: VerificationCheck

    private var isFail: Bool { check.severity == .fail }
    private var tint: Color { isFail ? Theme.bad : Theme.acc1 }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isFail ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text(check.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1))
        .fixedSize()
        .help(check.detail)
    }
}

private struct RestoreBanner: View {
    let count: Int
    let onDismiss: () -> Void
    let onClearPending: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 11))
                .foregroundStyle(Theme.txt3)
            Text("Restored \(count) job\(count == 1 ? "" : "s") from last session")
                .font(.system(size: 11))
                .foregroundStyle(Theme.txt2)
            Spacer()
            Button("Clear pending") {
                onClearPending()
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.acc1)
            Button("Dismiss") {
                onDismiss()
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.txt3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.panel2)
    }
}

// MARK: Console

struct ConsoleSection: View {
    @EnvironmentObject private var queue: QueueManager
    @State private var isOpen = false

    private var lines: [Substring] {
        queue.consoleLog.isEmpty ? [] : queue.consoleLog.split(separator: "\n")
    }

    private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(queue.consoleLog, forType: .string)
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
                    Button("Copy All") { copyAll() }
                        .buttonStyle(.cjGhost)
                        .font(.system(size: 11))
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
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                // One Text per line: lazy layout means only the visible
                                // rows are measured, so the full (uncapped) log scrolls
                                // without pegging the main thread. Selection is per-line
                                // (siblings can't cross-select); use Copy All for the lot.
                                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .foregroundStyle(lineColor(line))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                            Color.clear.frame(height: 1).id("console-bottom")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .lineSpacing(4)
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
    private var cancelled: Int { queue.cancelledCount }
    private var allFinished: Bool {
        total > 0 && queue.jobs.allSatisfy(\.status.isFinished) && !queue.isProcessing
    }

    /// Composition of the footer outcome bar, laid left→right: completed (green), failed (red),
    /// cancelled/stopped (amber), then the active job's live partial (running orange) while
    /// processing. The pending remainder is the empty track. Widths are absolute fractions of total.
    private var outcomeSegments: [CJBarSegment] {
        guard total > 0 else { return [] }
        let t = Double(total)
        var segs: [CJBarSegment] = []
        if done > 0      { segs.append(CJBarSegment(fraction: Double(done) / t, color: Theme.ok)) }
        if failed > 0    { segs.append(CJBarSegment(fraction: Double(failed) / t, color: Theme.bad)) }
        if cancelled > 0 { segs.append(CJBarSegment(fraction: Double(cancelled) / t, color: Theme.acc1)) }
        if queue.isProcessing, let active = queue.activeJob {
            segs.append(CJBarSegment(fraction: active.progress / t, color: Theme.acc2))
        }
        return segs
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
                Group {
                    if total == 0 {
                        Text("Queue empty")
                    } else if allFinished {
                        if failed == 0 && cancelled == 0 {
                            // Clean finish: every job joined. Green success styling.
                            Text("✓ \(done) of \(total) joined, \(failed) failed")
                                .foregroundStyle(Theme.ok)
                                .fontWeight(.semibold)
                        } else {
                            // Stopped early and/or with failures — no green ✓ success styling.
                            // Amber if only stopped; red once anything actually failed.
                            (Text("\(done) of \(total) joined")
                                + (cancelled > 0 ? Text(" · \(cancelled) stopped") : Text(""))
                                + (failed > 0 ? Text(" · \(failed) failed") : Text("")))
                                .foregroundStyle(failed > 0 ? Theme.bad : Theme.acc1)
                                .fontWeight(.semibold)
                        }
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

                // Whole-queue time-remaining, ticking once a second. Only while processing and once
                // there's enough signal to estimate (active job's live remaining + pending history).
                if queue.isProcessing {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let remaining = queue.remainingQueueSeconds(at: context.date) {
                            Text("· \(formattedCoarseDuration(remaining)) left")
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(Theme.txt2)
                        }
                    }
                }

                CJQueueOutcomeBar(segments: outcomeSegments)

                if queue.isProcessing {
                    Button("Stop") { queue.stopAllProcessing() }
                        .buttonStyle(.cjStopLarge)
                } else {
                    Button("Start") { queue.startQueue() }
                        .buttonStyle(.cjPrimaryLarge)
                        .disabled(!queue.hasPendingJobs)
                }
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
