import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Recordings list (hero region) + empty/scanning states

// SwiftUI port of the handoff's `conjoyn/rows.jsx` against `styles.css` metrics.

// MARK: Display helpers

extension RecordGroup {
    /// Row title: en-dash range for splits ("DJI_0042 – DJI_0047"), single stem otherwise.
    var displayTitle: String {
        guard clipCount > 1, let first = clips.first, let last = clips.last else {
            return clips.first?.stem ?? "Recording \(groupIndex)"
        }
        return "\(first.stem) – \(last.stem)"
    }

    var srtCount: Int { clips.filter(\.hasSRT).count }

    var totalBytes: Int64 { clips.reduce(0) { $0 + $1.totalFileSize } }

    /// Recording start for the sub-line (embedded creation time of the first segment).
    var displayStartDate: Date? { clips.first?.creationDate }
}

// MARK: List

struct RecordingsList: View {
    @EnvironmentObject private var vm: ConversionViewModel
    /// Disclosure state per group — session-only, reset on rescan.
    @State private var openRows: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            CJSectionHead(
                title: "Discovered recordings",
                count: countText
            ) {
                CJSegGroup(
                    actions: [
                        ("All",     { vm.setFilter(.all) }),
                        ("None",    { vm.selectNoGroups() }),
                        ("Splits",  { vm.setFilter(.splits) }),
                        ("Singles", { vm.setFilter(.singles) }),
                    ],
                    activeLabel: activeFilterLabel
                )
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.filteredGroups) { group in
                        RecordingRow(
                            group: group,
                            isOpen: openRows.contains(group.id),
                            toggleOpen: {
                                if openRows.contains(group.id) { openRows.remove(group.id) }
                                else { openRows.insert(group.id) }
                            }
                        )
                        if openRows.contains(group.id), group.groupType == .split {
                            SegmentSublist(group: group)
                        }
                    }
                }
            }
        }
    }

    private var countText: String {
        var text = "\(vm.selectedCount) of \(vm.groups.count) selected · \(vm.totalClips) clips on card"
        if !vm.skippedFiles.isEmpty { text += " · \(vm.skippedFiles.count) skipped" }
        if !vm.parseErrors.isEmpty { text += " · \(vm.parseErrors.count) unreadable" }
        return text
    }

    private var activeFilterLabel: String {
        switch vm.recordingFilter {
        case .all:     return "All"
        case .splits:  return "Splits"
        case .singles: return "Singles"
        }
    }
}

// MARK: Row

private struct RecordingRow: View {
    @EnvironmentObject private var vm: ConversionViewModel
    let group: RecordGroup
    let isOpen: Bool
    let toggleOpen: () -> Void
    @State private var hovered = false
    /// Per-row metadata-integrity readout — built lazily (`.task`), session-only, "pops in" like the
    /// thumbnail. `nil` until the first build completes.
    @State private var integrity: RecordingIntegrity?

    private var isSplit: Bool { group.groupType == .split }

    /// `HEVC · 3840×2160 · 25 fps` from the first segment's stream params. All clips in a group
    /// share these (the grouping gate refuses to chain mismatched codec/res/fps), so one segment
    /// speaks for the whole recording. `nil` when ffprobe couldn't read the stream.
    private var streamSummary: String? {
        guard let v = group.clips.first?.streamInfo?.video else { return nil }
        var parts = [CJFormat.codec(v.codecName),
                     CJFormat.resolution(width: v.width, height: v.height)]
        let fps = CJFormat.fps(v.framesPerSecond)
        if !fps.isEmpty { parts.append(fps) }
        return parts.joined(separator: " · ")
    }

    /// The date shown on the row: the resolver's corrected start once integrity has loaded, else the
    /// raw embedded date as a pre-load placeholder.
    private var displayDate: Date? {
        if let integrity { return integrity.resolvedDate }
        return group.displayStartDate
    }

    var body: some View {
        let checked = vm.isSelected(group)

        HStack(spacing: 12) {
            CJCheckbox(isOn: checked) { vm.toggleSelection(group) }

            // Disclosure chevron — splits only; singles reserve the slot so columns align.
            Button(action: toggleOpen) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.txt3)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isSplit ? 1 : 0)
            .disabled(!isSplit)

            ClipThumbnailView(clip: group.clips.first)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.txt)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    // Prefer the resolver's corrected start once integrity loads, so the row stops
                    // showing a wrong/garbage embedded date as authoritative. Pre-load, fall back to
                    // the embedded date as a placeholder.
                    if let displayDate {
                        Text(CJFormat.date(displayDate))
                            .foregroundStyle(Theme.txt2)
                        Text(CJFormat.time(displayDate))
                            .foregroundStyle(Theme.txt3)
                        if let tag = integrity?.originTag {
                            Text(tag)
                                .foregroundStyle(Theme.txt3)
                        }
                    } else {
                        Text(integrity == nil ? "no embedded date" : "—")
                            .foregroundStyle(Theme.txt3)
                    }
                    if isSplit, group.srtCount > 0 {
                        Text("+ \(group.srtCount) telemetry .SRT")
                            .foregroundStyle(Theme.txt3)
                    }
                }
                .font(.system(size: 11))
                .monospacedDigit()
                .lineLimit(1)

                // Inline integrity flags — only when there's something to say, so clean rows stay
                // clean and keep their original single-meta-line height.
                if let integrity, integrity.hasIssues {
                    HStack(spacing: 6) {
                        ForEach(Array(integrity.flags.enumerated()), id: \.offset) { _, flag in
                            IntegrityChip(flag: flag)
                        }
                    }
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Codec · resolution · fps, filling the gap before the badge. The name VStack above
            // takes the flexible space, so this keeps its intrinsic width and the title truncates
            // first when the row is cramped.
            if let streamSummary {
                Text(streamSummary)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.txt3)
                    .lineLimit(1)
            }

            CJBadge(
                isSplit: isSplit,
                count: group.clipCount,
                isFlagged: !isSplit && (integrity?.hasWarning ?? false)
            )

            // Fixed right-aligned meta columns, tabular numerals.
            HStack(spacing: 18) {
                (Text("\(group.clipCount)").bold().foregroundStyle(Theme.txt)
                    + Text(group.clipCount == 1 ? " file" : " files"))
                Text(CJFormat.duration(group.totalDurationSeconds))
                    .bold()
                    .foregroundStyle(Theme.txt)
                    .frame(width: 52, alignment: .trailing)
                Text(CJFormat.size(group.totalBytes))
                    .frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(Theme.txt2)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
        .background(rowBackground(checked: checked))
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { vm.toggleSelection(group) }
        .onHover { hovered = $0 }
        .task(id: group.id) {
            integrity = await RecordingIntegrity.build(group: group, settings: vm.settings)
        }
    }

    private func rowBackground(checked: Bool) -> Color {
        if checked { return Theme.acc2.opacity(0.12) }
        if hovered { return .white.opacity(0.025) }
        return .clear
    }
}

// MARK: Integrity chip

/// One inline metadata-integrity flag. Warnings borrow the established orange ⚠ treatment (matches
/// the queue's folder-mismatch badge); info flags are a quiet grey pill. Detail is in the tooltip.
private struct IntegrityChip: View {
    let flag: RecordingIntegrity.Flag

    private var isWarning: Bool { flag.severity == .warning }

    var body: some View {
        HStack(spacing: 3) {
            if isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
            }
            Text(flag.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(isWarning ? Theme.acc1 : Theme.txt3)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(isWarning ? Theme.acc1.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            Capsule().strokeBorder(isWarning ? Theme.acc1.opacity(0.28) : Theme.line, lineWidth: 1)
        )
        .fixedSize()
        .help(flag.detail)
    }
}

// MARK: Segment sublist

private struct SegmentSublist: View {
    let group: RecordGroup

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(group.clips.enumerated()), id: \.element.id) { i, clip in
                HStack(spacing: 10) {
                    Text(i == group.clipCount - 1 ? "└" : "├")
                        .foregroundStyle(Theme.txt3)
                        .frame(width: 14, alignment: .leading)
                    Text(clip.videoURL.lastPathComponent)
                        .foregroundStyle(Theme.txt)
                    if let srt = clip.srtURL {
                        Text("+ \(srt.lastPathComponent)")
                            .foregroundStyle(Theme.txt3)
                    }
                    Spacer()
                    HStack(spacing: 16) {
                        Text(CJFormat.duration(clip.durationInSeconds))
                        Text(CJFormat.size(clip.totalFileSize))
                            .frame(width: 60, alignment: .trailing)
                    }
                    .foregroundStyle(Theme.txt3)
                }
                .font(.system(size: 11))
                .monospacedDigit()
                .padding(.vertical, 4)
                .padding(.leading, 78)
                .padding(.trailing, 16)
            }
        }
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}

// MARK: Thumbnail

/// 16:9, 38 pt tall clip thumbnail. Shows the design's striped-placeholder treatment until the
/// real first-frame arrives from `ThumbnailManager`.
struct ClipThumbnailView: View {
    let clip: DJIClip?
    @EnvironmentObject private var vm: ConversionViewModel
    @State private var image: NSImage?

    private static let width: CGFloat = 38 * 16 / 9

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: Self.width, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
        .task(id: clip?.id) {
            guard image == nil, let clip else { return }
            let thumbs = await vm.thumbnails.getThumbnails(for: clip)
            image = thumbs.first ?? thumbs.last
        }
    }

    private var placeholder: some View {
        // Flat dark loading tile — no glyph, so it never reads as a clickable play button.
        Color(hex: 0x222222)
    }
}

// MARK: Empty state

struct EmptyStateView: View {
    @EnvironmentObject private var vm: ConversionViewModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                Image(systemName: "sdcard")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(Color(hex: 0x555555))
                Text("Choose a folder or drop a card to begin")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.txt)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.txt2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 300)
                Button("Choose Folder…", action: vm.chooseSourceFolder)
                    .buttonStyle(.cjPrimaryLarge)
                    .padding(.top, 6)
            }
            .padding(.vertical, 44)
            .padding(.horizontal, 30)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        dropTargeted ? Theme.acc2.opacity(0.7) : Color.white.opacity(0.16),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { return }
                Task { @MainActor in vm.setSourceFolder(url) }
            }
            return true
        }
    }

    private var subtitle: String {
        // After a scan that found nothing, say so instead of the generic pitch.
        if let status = vm.statusMessage, vm.sourceFolderURL != nil, vm.groups.isEmpty {
            return status
        }
        return "Conjoyn will scan it, find recordings that were split at the 4 GB card limit, "
            + "and join them back into whole files — losslessly."
    }
}

// MARK: Scanning state

struct ScanningStateView: View {
    @EnvironmentObject private var vm: ConversionViewModel

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.acc1)
            Text("Scanning card…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.txt)
            Text("grouping by recording time & metadata")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.txt2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
