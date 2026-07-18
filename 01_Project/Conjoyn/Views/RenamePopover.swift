import SwiftUI
import AppKit

// MARK: - Rename Joined Files popover

// SwiftUI port of the handoff's `rename.jsx` / `rename-popover.css`. Anchored to the output bar's
// "Rename files" switch; edits `vm.renameOptions` (session-only) and shows a live before→after
// preview of the currently-selected recordings. Native controls re-skinned to the CSS tokens, per
// the handoff's "prefer native controls" guidance. User-saved templates (`RenameTemplates`) persist
// across launches and render as a "Saved:" chip row; the ＋ chip stores the current pattern,
// right-click deletes.

struct RenamePopover: View {
    @EnvironmentObject private var vm: ConversionViewModel
    /// Invoked by the ✕ button — the caller turns the switch (and renaming) off.
    let onClose: () -> Void

    @StateObject private var caret = CaretFieldController()
    // Loaded when the popover is created (it is instantiated fresh on each presentation).
    @State private var templates = RenameTemplates.load()

    private var usesCounter: Bool { RenamePatternEngine.usesCounter(vm.renameOptions.pattern) }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Theme.line.frame(height: 1)
            VStack(spacing: 11) {
                formRow("Preset:") { presetChips }
                if !templates.patterns.isEmpty {
                    formRow("Saved:") { savedChips }
                }
                formRow("Pattern:") { patternField }
                formRow("Counter:", dim: !usesCounter) { counterRow }
                formRow("Preview:") { previewWell }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 13)
        }
        .frame(width: 430)
        .background(Theme.panel2)
    }

    // MARK: Title bar

    private var titleBar: some View {
        ZStack {
            Text("Rename Joined Files")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.txt)
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.cjIcon)
                .help("Close (turns renaming off)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
    }

    // MARK: Form scaffolding (62 pt right-aligned label column + control column)

    private func formRow<Content: View>(
        _ label: String, dim: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.txt2)
                .frame(width: 62, alignment: .trailing)
                .padding(.top, 3)
            content()
            Spacer(minLength: 0)
        }
        .opacity(dim ? 0.45 : 1)
    }

    // MARK: Row 1 — presets

    private var presetChips: some View {
        HStack(spacing: 5) {
            ForEach(RenamePatternEngine.presets, id: \.pattern) { preset in
                chip(preset.label, selected: vm.renameOptions.pattern == preset.pattern) {
                    vm.renameOptions.pattern = preset.pattern
                }
            }
            // While no templates exist the "Saved:" row is hidden, so the ＋ lives here.
            if templates.patterns.isEmpty { saveChip }
        }
    }

    // MARK: Row 1b — saved templates (hidden until the first save)

    private var savedChips: some View {
        ChipFlowLayout(hSpacing: 5, vSpacing: 5) {
            ForEach(templates.patterns, id: \.self) { pattern in
                chip(pattern, selected: vm.renameOptions.pattern == pattern, mono: true) {
                    vm.renameOptions.pattern = pattern
                }
                .contextMenu {
                    Button("Delete Template", role: .destructive) {
                        templates.remove(pattern)
                        templates.save()
                    }
                }
            }
            saveChip
        }
    }

    /// Shown only when the current pattern is savable (non-empty, not a preset, not saved yet) —
    /// a visible ＋ always does something.
    @ViewBuilder private var saveChip: some View {
        if templates.canSave(vm.renameOptions.pattern) {
            chip("＋", selected: false) {
                templates.add(vm.renameOptions.pattern)
                templates.save()
            }
            .help("Save current pattern as a template")
        }
    }

    // MARK: Row 2 — pattern field + token pills

    private var patternField: some View {
        VStack(alignment: .leading, spacing: 7) {
            CaretTextField(
                text: $vm.renameOptions.pattern,
                controller: caret,
                font: .monospacedSystemFont(ofSize: 12, weight: .regular)
            )
            .frame(height: 24)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.recessed(0.30)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lineStrong, lineWidth: 1))

            HStack(spacing: 5) {
                ForEach(RenamePatternEngine.tokens, id: \.token) { tok in
                    chip(tok.token, selected: false, mono: true) {
                        caret.insert(tok.token, currentText: vm.renameOptions.pattern) {
                            vm.renameOptions.pattern = $0
                        }
                    }
                    .help(tok.label)
                }
            }
        }
    }

    // MARK: Row 3 — counter

    private var counterRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Text("Start at")
                    .font(.system(size: 11)).foregroundStyle(Theme.txt2).fixedSize()
                TextField("", value: $vm.renameOptions.start, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: $vm.renameOptions.start, in: 0...999).labelsHidden()
            }
            HStack(spacing: 7) {
                Text("Digits")
                    .font(.system(size: 11)).foregroundStyle(Theme.txt2).fixedSize()
                digitsPicker
            }
        }
        .disabled(!usesCounter)
    }

    private var digitsPicker: some View {
        HStack(spacing: 1) {
            ForEach([2, 3, 4], id: \.self) { n in
                Button { vm.renameOptions.digits = n } label: {
                    Text("\(n)")
                        .font(.system(size: 11))
                        .foregroundStyle(vm.renameOptions.digits == n ? .white : Theme.txt2)
                        .frame(width: 24, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(vm.renameOptions.digits == n ? Theme.acc2 : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(1)
        .background(Theme.recessed(0.28), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Row 4 — live preview

    private var previewWell: some View {
        let rows = vm.renamePreview(limit: 3)
        return VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text("Select recordings to preview")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.txt3)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(row.original) →")
                            .foregroundStyle(Theme.txt3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(row.result)
                            .foregroundStyle(Theme.acc1)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.leading, 12)
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.recessed(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line, lineWidth: 1))
    }

    // MARK: Chip atom (preset chip + mono token pill)

    private func chip(
        _ label: String, selected: Bool, mono: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: mono ? 10.5 : 11, design: mono ? .monospaced : .default))
                .foregroundStyle(selected ? .white : (mono ? Theme.acc1 : Theme.txt))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: mono ? 9 : 5)
                        .fill(chipFill(selected: selected, mono: mono))
                )
        }
        .buttonStyle(.plain)
    }

    private func chipFill(selected: Bool, mono: Bool) -> Color {
        if selected { return Theme.acc2 }
        return mono ? Theme.acc2.opacity(0.20) : Theme.raised(0.10)
    }
}

// MARK: - Wrapping chip row

/// Minimal left-aligned wrapping layout for the saved-template chips. Their labels are whole
/// patterns (arbitrarily wide) and the popover is fixed at 430 pt, so a plain `HStack` would
/// overflow it; this wraps onto new lines instead.
struct ChipFlowLayout: Layout {
    var hSpacing: CGFloat = 5
    var vSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - hSpacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Caret-aware pattern field

/// Bridges a SwiftUI token-pill tap into an `NSTextField`'s live caret: SwiftUI's `TextField`
/// exposes neither the selection range nor the field editor, so the pattern field is an
/// `NSViewRepresentable` that registers its field here. `insert(_:)` replaces the current selection
/// with the token and restores focus + caret after it (the handoff's `insertToken` behavior); when
/// the field isn't focused it appends, matching the JS fallback.
final class CaretFieldController: ObservableObject {
    fileprivate weak var textField: NSTextField?

    func insert(_ token: String, currentText: String, set: (String) -> Void) {
        guard let textField else { set(currentText + token); return }

        let nsCurrent = currentText as NSString
        // Selection from the live field editor when focused; otherwise append at the end.
        let selection = textField.currentEditor()?.selectedRange
            ?? NSRange(location: nsCurrent.length, length: 0)
        let newText = nsCurrent.replacingCharacters(in: selection, with: token)
        let caret = selection.location + (token as NSString).length

        set(newText)
        // The binding update re-pushes `stringValue`, which parks the caret at the end; restore it
        // (and focus) on the next runloop tick once SwiftUI has applied the new text.
        DispatchQueue.main.async { [weak textField] in
            guard let textField else { return }
            textField.window?.makeFirstResponder(textField)
            textField.currentEditor()?.selectedRange = NSRange(location: caret, length: 0)
        }
    }
}

struct CaretTextField: NSViewRepresentable {
    @Binding var text: String
    let controller: CaretFieldController
    let font: NSFont

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.font = font
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = NSColor(Theme.txt)
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        controller.textField = field
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.font = font
        controller.textField = nsView
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: CaretTextField
        init(_ parent: CaretTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}
