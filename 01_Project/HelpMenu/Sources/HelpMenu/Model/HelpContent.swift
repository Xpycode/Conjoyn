import Foundation

/// The full set of help topics a host app supplies to the package.
///
/// Build it programmatically from `[HelpTopic]`, or load it from a bundled
/// JSON manifest that points at `.md` files (`init(manifest:in:)`). Content is
/// always host-owned; the package only renders it.
public struct HelpContent: Sendable {
    /// All topics in authoring order.
    public let topics: [HelpTopic]

    /// The window title (e.g. "MyApp Help"). Defaults to "Help".
    public let windowTitle: String

    /// Base directory used to resolve **relative image paths** in markdown
    /// (e.g. `![](shot.jpg)`). The manifest loader sets this to the bundle's
    /// `resourceURL`, so images bundled alongside the `.md` files render.
    /// Leave `nil` (programmatic builder) to fall back to asset-catalog lookup
    /// by name and the default network image loader.
    public let imageBaseURL: URL?

    public init(topics: [HelpTopic], windowTitle: String = "Help", imageBaseURL: URL? = nil) {
        self.topics = topics
        self.windowTitle = windowTitle
        self.imageBaseURL = imageBaseURL
    }

    /// True when there are no topics to show (drives the empty state).
    public var isEmpty: Bool { topics.isEmpty }

    /// Topics grouped for sidebar display, preserving first-seen order of both
    /// groups and topics. Ungrouped topics fall under `nil`.
    public var groups: [HelpTopicGroup] {
        var order: [String] = []
        var buckets: [String: [HelpTopic]] = [:]
        let ungroupedKey = "\u{0}__ungrouped__"
        for topic in topics {
            let key = topic.group ?? ungroupedKey
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(topic)
        }
        return order.map { key in
            HelpTopicGroup(name: key == ungroupedKey ? "" : key, topics: buckets[key] ?? [])
        }
    }
}

// MARK: - Manifest loading

/// Errors surfaced while loading a help manifest. Missing markdown files do not
/// throw — they degrade to an inline error topic so the window stays usable.
public enum HelpContentError: Error, LocalizedError {
    case manifestNotFound(name: String)
    case manifestUnreadable(name: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .manifestNotFound(let name):
            return "Help manifest '\(name)' was not found in the bundle."
        case .manifestUnreadable(let name, let underlying):
            return "Help manifest '\(name)' could not be read: \(underlying.localizedDescription)"
        }
    }
}

/// One topic entry in the JSON manifest.
struct HelpManifestEntry: Decodable {
    let id: String
    let title: String
    let markdownFile: String
    let group: String?
}

/// Top-level JSON manifest shape.
///
/// ```json
/// {
///   "windowTitle": "MyApp Help",
///   "topics": [
///     { "id": "getting-started", "title": "Getting Started",
///       "markdownFile": "getting-started.md", "group": "Basics" }
///   ]
/// }
/// ```
struct HelpManifest: Decodable {
    let windowTitle: String?
    let topics: [HelpManifestEntry]
}

extension HelpContent {
    /// Load help content from a bundled JSON manifest plus its referenced
    /// markdown files.
    ///
    /// - Parameters:
    ///   - manifest: The manifest resource name (with or without `.json`).
    ///   - bundle: The bundle that contains the manifest and `.md` files.
    /// - Throws: `HelpContentError` only when the manifest itself is missing or
    ///   unparseable. Individual missing markdown files become error topics
    ///   rather than throwing.
    public init(manifest: String, in bundle: Bundle) throws {
        let base = (manifest as NSString).deletingPathExtension
        let ext = (manifest as NSString).pathExtension.isEmpty ? "json" : (manifest as NSString).pathExtension

        guard let url = bundle.url(forResource: base, withExtension: ext) else {
            throw HelpContentError.manifestNotFound(name: manifest)
        }

        let decoded: HelpManifest
        do {
            let data = try Data(contentsOf: url)
            decoded = try JSONDecoder().decode(HelpManifest.self, from: data)
        } catch {
            throw HelpContentError.manifestUnreadable(name: manifest, underlying: error)
        }

        let topics = decoded.topics.map { entry -> HelpTopic in
            let markdown = Self.loadMarkdown(named: entry.markdownFile, in: bundle, title: entry.title)
            return HelpTopic(id: entry.id, title: entry.title, markdown: markdown, group: entry.group)
        }

        self.init(
            topics: topics,
            windowTitle: decoded.windowTitle ?? "Help",
            imageBaseURL: bundle.resourceURL
        )
    }

    /// Load a markdown file from the bundle, falling back to a visible error
    /// topic body when the file is missing or unreadable.
    static func loadMarkdown(named file: String, in bundle: Bundle, title: String) -> String {
        let base = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension.isEmpty ? "md" : (file as NSString).pathExtension

        guard let url = bundle.url(forResource: base, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return """
            # \(title)

            *This help topic could not be loaded.*

            The file **\(file)** is missing from the app bundle. \
            Please report this to the app developer.
            """
        }
        return text
    }
}
