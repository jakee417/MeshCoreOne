import SwiftUI
import MC1Services
import CoreLocation

struct ContactsSplitList<FilterHeader: View, EmptyContent: View>: View {
    @Environment(\.appState) private var appState

    let filteredContacts: [ContactDTO]
    let isSearching: Bool
    let viewModel: ContactsViewModel
    @Binding var selectedContact: ContactDTO?
    @ViewBuilder let filterHeader: () -> FilterHeader
    @ViewBuilder let emptyContent: () -> EmptyContent

    var body: some View {
        List(selection: $selectedContact) {
            filterHeader()

            if filteredContacts.isEmpty {
                emptyContent()
            } else {
                ForEach(Array(filteredContacts.enumerated()), id: \.element.id) { index, contact in
                    ContactRowView(
                        contact: contact,
                        showTypeLabel: isSearching,
                        userLocation: appState.bestAvailableLocation,
                        index: index,
                        isTogglingFavorite: viewModel.togglingFavoriteID == contact.id
                    )
                    .contactSwipeActions(contact: contact, viewModel: viewModel)
                    .tag(contact)
                }
            }
        }
        .listStyle(.plain)
    }
}
