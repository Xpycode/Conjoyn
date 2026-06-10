import Foundation

/// Centralized resolver for bundled command-line tools.
/// Provides consistent path resolution across FFmpegWrapper and VerificationService.
///
/// Ported from P2toMXF, trimmed to ffmpeg + ffprobe (DJI MP4s are self-contained — no BMX).
enum BundledTool: String, CaseIterable {
    case ffmpeg
    case ffprobe

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .ffmpeg: return "FFmpeg"
        case .ffprobe: return "FFprobe"
        }
    }
}

/// Resolves paths to bundled command-line tools used by the app
struct BundledToolResolver {

    // MARK: - Singleton

    static let shared = BundledToolResolver()

    private init() {}

    // MARK: - Path Resolution

    /// Resolves the path for a bundled tool.
    /// Looks in the app bundle's `Resources/Helpers/` first (where the build phase signs them in),
    /// then a flat `Resources/` location, then Homebrew as a development fallback.
    /// - Parameter tool: The tool to find
    /// - Returns: URL to the tool if found, nil otherwise
    func path(for tool: BundledTool) -> URL? {
        // Primary: Contents/Resources/Helpers/<tool> (see sign-bundled-binaries.sh)
        if let helpers = Bundle.main.resourceURL?.appendingPathComponent("Helpers", isDirectory: true) {
            let candidate = helpers.appendingPathComponent(tool.rawValue)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // Fallback: flat in Resources
        if let bundledPath = Bundle.main.url(forResource: tool.rawValue, withExtension: nil) {
            return bundledPath
        }

        // Development fallback: Homebrew locations
        return homebrewPath(for: tool)
    }

    /// Checks if a tool is available
    func isAvailable(_ tool: BundledTool) -> Bool {
        path(for: tool) != nil
    }

    /// Checks if all required tools are available
    var allRequiredToolsAvailable: Bool {
        isAvailable(.ffmpeg) && isAvailable(.ffprobe)
    }

    // MARK: - Private

    /// Homebrew fallback paths for FFmpeg tools
    private func homebrewPath(for tool: BundledTool) -> URL? {
        let homebrewPaths = [
            "/opt/homebrew/bin/\(tool.rawValue)",  // Apple Silicon
            "/usr/local/bin/\(tool.rawValue)"       // Intel
        ]

        for path in homebrewPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    // MARK: - Diagnostics

    /// Returns a diagnostic summary of tool availability
    func diagnosticSummary() -> String {
        var lines: [String] = ["Tool Availability:"]

        for tool in BundledTool.allCases {
            let status: String
            if let url = path(for: tool) {
                let isBundled = url.path.contains(".app/")
                status = "✓ \(url.path) (\(isBundled ? "bundled" : "system"))"
            } else {
                status = "✗ not found"
            }
            lines.append("  \(tool.displayName): \(status)")
        }

        return lines.joined(separator: "\n")
    }
}
