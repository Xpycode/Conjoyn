import SwiftUI

/// The topics sidebar: a selectable list, grouped into sections when the
/// content defines groups. Handles the empty and no-search-results states.
struct HelpSidebarView: View {
    @Bindable var model: HelpViewModel

    var body: some View {
        Group {
            if model.isEmpty {
                ContentUnavailableView(
                    "No Help Topics",
                    systemImage: "questionmark.circle",
                    description: Text("This app hasn't provided any help content yet.")
                )
            } else if model.hasNoSearchResults {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                topicList
            }
        }
        .frame(minWidth: 200)
    }

    private var topicList: some View {
        // Build the hit lookup once per render rather than per row.
        let hits = Dictionary(uniqueKeysWithValues: model.searchHits.map { ($0.topic.id, $0) })
        return List(selection: $model.selection) {
            ForEach(model.filteredGroups) { group in
                if group.name.isEmpty {
                    ForEach(group.topics) { topic in
                        row(for: topic, hit: hits[topic.id]).tag(topic.id)
                    }
                } else {
                    Section(group.name) {
                        ForEach(group.topics) { topic in
                            row(for: topic, hit: hits[topic.id]).tag(topic.id)
                        }
                    }
                }
            }
        }
    }

    /// A sidebar row: the highlighted title plus an optional match snippet while
    /// searching; the plain title (resting state) otherwise.
    @ViewBuilder
    private func row(for topic: HelpTopic, hit: HelpSearchHit?) -> some View {
        if model.isSearching, let hit {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.highlightedTitle)
                if let snippet = hit.snippet {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
        } else {
            Text(topic.title)
        }
    }
}
