import SwiftUI

/// Root view of the help window: a `NavigationSplitView` pairing the topics
/// sidebar with the markdown detail pane, plus the in-window search field.
public struct HelpWindowView: View {
    @State private var model: HelpViewModel

    public init(content: HelpContent) {
        _model = State(initialValue: HelpViewModel(content: content))
    }

    public var body: some View {
        NavigationSplitView {
            HelpSidebarView(model: model)
        } detail: {
            HelpDetailView(topic: model.selectedTopic, imageBaseURL: model.content.imageBaseURL)
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search Help")
        .onChange(of: model.searchText) {
            model.reconcileSelectionWithFilter()
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}
