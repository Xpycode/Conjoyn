import Foundation

/// A single help topic rendered in the help window.
///
/// The markdown body can be supplied inline (programmatic builder) or loaded
/// from a bundled `.md` file (manifest loader). Once constructed, `markdown`
/// always holds the resolved string the detail view renders.
public struct HelpTopic: Identifiable, Hashable, Sendable {
    /// Stable identifier used for selection and deep-linking.
    public let id: String
    /// Human-readable title shown in the sidebar.
    public let title: String
    /// Resolved markdown body to render.
    public let markdown: String
    /// Optional group name; topics sharing a group are sectioned together.
    public let group: String?

    public init(id: String, title: String, markdown: String, group: String? = nil) {
        self.id = id
        self.title = title
        self.markdown = markdown
        self.group = group
    }
}

/// A named section of topics in the sidebar, preserving authoring order.
public struct HelpTopicGroup: Identifiable, Hashable, Sendable {
    /// Group name doubles as its identity (groups are unique by name).
    public var id: String { name }
    public let name: String
    public let topics: [HelpTopic]

    public init(name: String, topics: [HelpTopic]) {
        self.name = name
        self.topics = topics
    }
}
