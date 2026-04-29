import SwiftUI
import MC1Services

/// Settings sub-page for editing the user's `RegionSelection`. Hosts the same
/// `RegionPickerView` used by onboarding step 4. The picker writes to the
/// binding inline, so changes persist immediately as the user picks; the back
/// chevron dismisses without losing state.
struct RegionSettingsView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        RegionPickerView(
            selection: Binding(
                get: { appState.regionSelection },
                set: { appState.regionSelection = $0 }
            )
        )
        .navigationTitle(L10n.Settings.Region.title)
    }
}
