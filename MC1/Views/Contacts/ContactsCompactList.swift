import SwiftUI
import MC1Services

struct ContactsCompactList: View {
    @Environment(\.appState) private var appState

    @Binding var selectedSegment: NodeSegment
    let isSearching: Bool
    let searchText: String
    let filteredContacts: [ContactDTO]
    let viewModel: ContactsViewModel

    var body: some View {
        List {
            PinnedFilterHeader {
                NodeSegmentPicker(selection: $selectedSegment, isSearching: isSearching)
            }

            if filteredContacts.isEmpty {
                emptyStateRow
            } else {
                ForEach(Array(filteredContacts.enumerated()), id: \.element.id) { index, contact in
                    NavigationLink(value: contact) {
                        ContactRowView(
                            contact: contact,
                            showTypeLabel: isSearching,
                            userLocation: appState.bestAvailableLocation,
                            index: index,
                            isTogglingFavorite: viewModel.togglingFavoriteID == contact.id
                        )
                    }
                    .contactSwipeActions(contact: contact, viewModel: viewModel)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var emptyStateRow: some View {
        Section {
            if isSearching {
                ContactsSearchEmptyView(searchText: searchText)
            } else {
                ContactsEmptyView(selectedSegment: selectedSegment)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
