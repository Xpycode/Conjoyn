import SwiftUI

// MARK: - Shared controls (design handoff atoms)

// SwiftUI counterparts of the handoff's `conjoyn/ui.jsx` atoms + `styles.css` control rules.
// Per the handoff, real `Button`/`Toggle`/`ProgressView` are preferred over hand-built
// lookalikes; these styles only re-skin them.

// MARK: Buttons

/// Flat macOS dark-mode button per `styles.css .btn` (+ `.btn-primary` / `.btn-lg` / `.btn-stop`).
struct CJButtonStyle: ButtonStyle {
    enum Kind {
        case standard       // rgba(255,255,255,0.12) fill
        case primary        // solid --acc2, white text
        case stop           // red-tinted fill, light-red text
        case ghost          // transparent, hover only
    }

    var kind: Kind = .standard
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13 : 13, weight: kind == .primary ? .medium : .regular))
            .foregroundStyle(labelColor)
            .padding(.horizontal, large ? 16 : 11)
            .frame(height: large ? 28 : 22)
            .background(fill, in: RoundedRectangle(cornerRadius: large ? 6 : 5))
            .overlay(
                // Hairline top inner highlight.
                RoundedRectangle(cornerRadius: large ? 6 : 5)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(kind == .ghost ? 0 : 0.18), .clear],
                            startPoint: .top, endPoint: .center
                        ),
                        lineWidth: 0.5
                    )
            )
            .opacity(isEnabled ? 1 : 0.4)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(RoundedRectangle(cornerRadius: large ? 6 : 5))
    }

    private var fill: Color {
        switch kind {
        case .standard: return Theme.raised(0.12)
        case .primary:  return Theme.acc2
        case .stop:     return Color(hex: 0xFF6B6B).opacity(0.22)
        case .ghost:    return .clear
        }
    }

    private var labelColor: Color {
        switch kind {
        case .standard: return Theme.txt
        case .primary:  return .white
        case .stop:     return Color(light: 0xB23A3A, dark: 0xFFB3B3)
        case .ghost:    return Theme.txt2
        }
    }
}

extension ButtonStyle where Self == CJButtonStyle {
    static var cjStandard: CJButtonStyle { CJButtonStyle() }
    static var cjPrimary: CJButtonStyle { CJButtonStyle(kind: .primary) }
    static var cjPrimaryLarge: CJButtonStyle { CJButtonStyle(kind: .primary, large: true) }
    static var cjStopLarge: CJButtonStyle { CJButtonStyle(kind: .stop, large: true) }
    static var cjGhost: CJButtonStyle { CJButtonStyle(kind: .ghost) }
}

/// 22 × 22 hover-highlight icon button per `styles.css .icon-btn`.
struct CJIconButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hovered ? Theme.txt : Theme.txt3)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovered ? Theme.raised(0.08) : .clear)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { hovered = $0 }
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == CJIconButtonStyle {
    static var cjIcon: CJIconButtonStyle { CJIconButtonStyle() }
}

// MARK: Segmented action group

/// Inset segmented group of *action* buttons (All | None | Splits) per `styles.css .seg-group`.
/// These are one-shot actions, not a persistent selection, so it's a button row in a dark well.
struct CJSegGroup: View {
    let actions: [(label: String, action: () -> Void)]
    /// The label of the currently-active filter button. `nil` = no active state shown (e.g. "None").
    var activeLabel: String? = nil

    var body: some View {
        HStack(spacing: 1) {
            ForEach(actions.indices, id: \.self) { i in
                SegButton(
                    label: actions[i].label,
                    action: actions[i].action,
                    isActive: actions[i].label == activeLabel
                )
            }
        }
        .padding(1)
        .background(Theme.recessed(0.28), in: RoundedRectangle(cornerRadius: 6))
    }

    private struct SegButton: View {
        let label: String
        let action: () -> Void
        let isActive: Bool
        @State private var hovered = false

        var body: some View {
            Button(action: action) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Theme.acc2 : (hovered ? Theme.txt : Theme.txt2))
                    .padding(.horizontal, 10)
                    .frame(height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isActive
                                  ? Theme.acc2.opacity(0.15)
                                  : (hovered ? Theme.raised(0.16) : .clear))
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
        }
    }
}

// MARK: Checkbox

/// 14 pt orange-fill checkbox per `styles.css .mac-check` (the system checkbox can't take the
/// `--acc2` fill on macOS, so this one is hand-drawn to the same metrics).
struct CJCheckbox: View {
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(isOn ? Theme.acc2 : Theme.recessed(0.25))
                RoundedRectangle(cornerRadius: 3.5)
                    .strokeBorder(isOn ? .clear : Theme.raised(0.28), lineWidth: 1)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Badge

/// SPLIT · N / SINGLE pill per `styles.css .badge`. A flagged single is tinted orange instead of
/// greyed, so a lone clip worth re-exporting (bad/missing date) reads as "live" and invites selection.
struct CJBadge: View {
    let isSplit: Bool
    let count: Int
    /// Highlights an otherwise-greyed SINGLE when its recording carries an integrity warning.
    var isFlagged: Bool = false

    private var accented: Bool { isSplit || isFlagged }

    var body: some View {
        Text(isSplit ? "SPLIT · \(count)" : "SINGLE")
            .font(.system(size: 10, weight: .bold))
            .kerning(0.4)
            .foregroundStyle(accented ? Theme.acc1 : Theme.txt3)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(accented ? Theme.acc1.opacity(0.12) : Theme.raised(0.04))
            )
            .overlay(
                Capsule().strokeBorder(
                    accented ? Theme.acc1.opacity(0.28) : Theme.line, lineWidth: 1
                )
            )
    }
}

// MARK: Progress bar

/// 5 pt rounded progress bar per `styles.css .pbar`. Width is driven directly from the progress
/// value — deliberately **no** width animation (the handoff hit a wedged-transition bug).
struct CJProgressBar: View {
    enum Fill { case running, done, failed }

    /// 0…1
    let fraction: Double
    var fill: Fill = .running

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.recessed(0.35))
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 5)
    }

    private var fillColor: Color {
        switch fill {
        case .running: return Theme.acc2
        case .done:    return Theme.ok
        case .failed:  return Theme.bad
        }
    }
}

// MARK: Wells

/// Dark inset "well" showing a path, per `styles.css .cj-sourcewell` — icon + path + trailing
/// Choose… button.
struct CJPathWell: View {
    let icon: String
    let path: String?
    let placeholder: String
    var height: CGFloat = 30
    var minWidth: CGFloat = 320
    let choose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.txt3)
            if let path {
                Text(path)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.txt)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.txt3)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Choose…", action: choose)
                .buttonStyle(.cjStandard)
                .scaleEffect(height < 30 ? 0.85 : 0.95)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: height)
        .frame(minWidth: minWidth, maxWidth: 460)
        .background(Theme.recessed(0.30), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line, lineWidth: 1))
    }
}

// MARK: Section header

/// Uppercase 11 pt section header per `styles.css .section-head`.
struct CJSectionHead<Trailing: View>: View {
    let title: String
    var count: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Theme.txt3)
            if let count {
                Text(count)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.txt2)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: Formatters

enum CJFormat {
    /// `h:mm:ss` / `m:ss`, matching the prototype's `fmtDur`.
    static func duration(_ totalSeconds: Double) -> String {
        let t = Int(totalSeconds.rounded())
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// `22.70 GB` / `412 MB`, matching the prototype's `fmtGB`.
    static func size(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb < 1 { return "\(Int((gb * 1024).rounded())) MB" }
        return String(format: "%.2f GB", gb)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func date(_ d: Date) -> String { dateFormatter.string(from: d) }
    static func time(_ d: Date) -> String { timeFormatter.string(from: d) }

    /// Prettifies an ffprobe codec name for display: `hevc` → `HEVC`, `h264` → `H.264`.
    /// Unknown codecs are uppercased verbatim.
    static func codec(_ name: String) -> String {
        switch name.lowercased() {
        case "hevc", "h265": return "HEVC"
        case "h264", "avc1": return "H.264"
        default: return name.uppercased()
        }
    }

    /// `3840×2160` (true × multiplication sign, not the letter x).
    static func resolution(width: Int, height: Int) -> String { "\(width)×\(height)" }

    /// `25 fps` / `29.97 fps`; `nil` (indeterminate rate) → empty string.
    static func fps(_ fps: Double?) -> String {
        guard let fps else { return "" }
        let rounded = (fps * 100).rounded() / 100
        return rounded == rounded.rounded()
            ? "\(Int(rounded)) fps"
            : String(format: "%.2f fps", rounded)
    }
}
