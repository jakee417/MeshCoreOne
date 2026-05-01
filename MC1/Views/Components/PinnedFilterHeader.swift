import SwiftUI

/// Wraps a picker as a sticky list section header for `.listStyle(.plain)` lists.
/// Use inside a `List { … }` body so the picker scrolls with surrounding rows
/// and pins to the top during pull-to-refresh.
struct PinnedFilterHeader<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section {
            EmptyView()
        } header: {
            content()
                .textCase(nil)
                .listRowInsets(EdgeInsets())
        }
    }
}
