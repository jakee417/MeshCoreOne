import MC1Services
import MapKit
import SwiftUI

private let rangeTestSheetDetentCollapsed: PresentationDetent = .fraction(0.25)
private let rangeTestSheetDetentExpanded: PresentationDetent = .large

enum RangeTestLayoutMode {
    case panel
    case map
    case mapWithSheet
}

// MARK: - Main View

struct RangeTestView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isShowingSettings = false
    @State private var isShowingHistory = false
    @State private var sheetDetent: PresentationDetent = rangeTestSheetDetentCollapsed
    @State private var showControlSheet = true
    @State private var isNavigatingBack = false
    @State private var sheetBottomInset: CGFloat = 220

    private let layoutMode: RangeTestLayoutMode

    init(layoutMode: RangeTestLayoutMode = .mapWithSheet) {
        self.layoutMode = layoutMode
    }

    private var isConnected: Bool { appState.services?.session != nil }
    private var usesCompactNavigation: Bool { horizontalSizeClass != .regular }
    private var usesBottomSheet: Bool { layoutMode == .mapWithSheet }
    private var showsOwnToolbar: Bool { layoutMode != .panel }
    private var expandedPanelDetent: Binding<PresentationDetent> {
        .constant(rangeTestSheetDetentExpanded)
    }
    private var mapOverlayBottomPadding: CGFloat {
        usesBottomSheet && showControlSheet ? sheetBottomInset : 0
    }

    private var viewModel: RangeTestViewModel {
        if appState.rangeTestViewModel == nil {
            appState.rangeTestViewModel = RangeTestViewModel()
        }
        return appState.rangeTestViewModel!
    }

    var body: some View {
        Group {
            if !isConnected {
                disconnectedState
            } else {
                connectedContent
            }
        }
        .toolbar {
            if showsOwnToolbar && usesCompactNavigation {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismissRangeTest()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Back")
                }
            }

            if showsOwnToolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentHistory()
                    } label: {
                        Image(systemName: "clock")
                    }
                    .accessibilityLabel("Range Test History")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Range Test Settings")
                }
            }
        }
        .sheet(
            isPresented: $isShowingHistory,
            onDismiss: {
                if usesBottomSheet && isConnected && !isNavigatingBack && !isShowingSettings {
                    showControlSheet = true
                }
            }
        ) {
            RangeTestHistorySheetView(viewModel: viewModel)
        }
        .sheet(
            isPresented: $isShowingSettings,
            onDismiss: {
                if usesBottomSheet && isConnected && !isNavigatingBack && !isShowingHistory {
                    showControlSheet = true
                }
            }
        ) {
            RangeTestSettingsView(viewModel: viewModel)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let msg = viewModel.errorMessage { Text(msg) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.startStopHapticTrigger)
        .sensoryFeedback(.success, trigger: viewModel.beaconSentHapticTrigger)
        .task(id: appState.servicesVersion) {
            viewModel.configure(appState: appState)
            if usesBottomSheet && !isShowingSettings {
                showControlSheet = isConnected
            }
        }
        .onChange(of: isConnected) { _, connected in
            if usesBottomSheet && !isShowingSettings {
                showControlSheet = connected
            }
        }
        .onDisappear {
            showControlSheet = false
            isShowingSettings = false
            isShowingHistory = false
            isNavigatingBack = false
        }
        .navigationBarBackButtonHidden(usesCompactNavigation)
        .liquidGlassToolbarBackground()
    }

    @ViewBuilder
    private var connectedContent: some View {
        switch layoutMode {
        case .panel:
            RangeTestSheetView(
                viewModel: viewModel,
                sheetDetent: expandedPanelDetent,
                onCenterBeacon: { beacon in
                    let region = MKCoordinateRegion(
                        center: beacon.coordinate,
                        latitudinalMeters: 250,
                        longitudinalMeters: 250
                    )
                    viewModel.setCameraRegion(region)
                },
                embedsNavigationStack: false
            )
        case .map:
            mapCanvas(useBottomSheet: false)
        case .mapWithSheet:
            mapCanvas(useBottomSheet: true)
        }
    }

    @MainActor
    private func dismissRangeTest() {
        guard !isNavigatingBack else { return }
        isNavigatingBack = true
        showControlSheet = false
        isShowingSettings = false

        Task { @MainActor in
            await Task.yield()
            dismiss()
        }
    }

    @MainActor
    private func presentSettings() {
        guard !isNavigatingBack else { return }

        if usesBottomSheet && showControlSheet {
            showControlSheet = false
            Task { @MainActor in
                await Task.yield()
                isShowingSettings = true
            }
        } else {
            isShowingSettings = true
        }
    }

    @MainActor
    private func presentHistory() {
        guard !isNavigatingBack else { return }

        if usesBottomSheet && showControlSheet {
            showControlSheet = false
            Task { @MainActor in
                await Task.yield()
                isShowingHistory = true
            }
        } else {
            isShowingHistory = true
        }
    }

    // MARK: - Disconnected

    private var disconnectedState: some View {
        ContentUnavailableView {
            Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text("Connect to a mesh radio to use Range Test.")
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func mapCanvas(useBottomSheet: Bool) -> some View {
        let map = RangeTestMapView(
            viewModel: viewModel,
            cameraBottomSheetFraction: useBottomSheet && showControlSheet ? 0.25 : 0,
            mapOverlayBottomPadding: mapOverlayBottomPadding
        )
        .onDisappear {
            showControlSheet = false
        }

        if useBottomSheet {
            map
                .sheet(isPresented: $showControlSheet) {
                    RangeTestSheetView(
                        viewModel: viewModel,
                        sheetDetent: $sheetDetent,
                        onCenterBeacon: { beacon in
                            let region = MKCoordinateRegion(
                                center: beacon.coordinate,
                                latitudinalMeters: 250,
                                longitudinalMeters: 250
                            )
                            viewModel.setCameraRegion(region)
                            sheetDetent = rangeTestSheetDetentCollapsed
                            showControlSheet = true
                        }
                    )
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height - proxy.safeAreaInsets.bottom + 15
                    } action: { inset in
                        if sheetDetent == rangeTestSheetDetentCollapsed {
                            sheetBottomInset = max(0, inset)
                        }
                    }
                    .presentationDetents(
                        [rangeTestSheetDetentCollapsed, rangeTestSheetDetentExpanded],
                        selection: $sheetDetent
                    )
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled)
                    .presentationBackground(.regularMaterial)
                    .interactiveDismissDisabled()
                }
        } else {
            map
        }
    }
}

#Preview {
    NavigationStack {
        RangeTestView()
            .environment(\.appState, AppState())
    }
}
