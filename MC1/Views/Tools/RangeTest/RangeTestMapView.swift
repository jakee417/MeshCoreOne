import MapKit
import SwiftUI

/// Embedded map showing the beacon locations captured during a range test.
struct RangeTestMapView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appState) private var appState
    @Bindable var viewModel: RangeTestViewModel
    @AppStorage("mapStyleSelection") private var mapStyleSelection: MapStyleSelection = .standard
    @AppStorage("mapShowLabels") private var showLabels = true
    @State private var showingLayersMenu = false
    var cameraBottomSheetFraction: CGFloat? = nil
    var mapOverlayBottomPadding: CGFloat = 0

    private var canStartRangeTest: Bool {
        viewModel.isReadyToStart && viewModel.recipients.contains(where: \.isEnabled) && viewModel.hasActiveTest
    }

    private var startStopColor: Color {
        if viewModel.isRunning {
            return .red
        }
        return canStartRangeTest ? .green : .secondary
    }

    var body: some View {
        ZStack {
            MC1MapView(
                points: viewModel.mapPoints,
                lines: viewModel.mapLines,
                mapStyle: mapStyleSelection,
                isDarkMode: colorScheme == .dark,
                isOffline: !appState.offlineMapService.isNetworkAvailable,
                showLabels: showLabels,
                showsUserLocation: true,
                isInteractive: true,
                showsScale: false,
                isNorthLocked: viewModel.isNorthLocked,
                cameraRegion: $viewModel.cameraRegion,
                cameraRegionVersion: viewModel.cameraRegionVersion,
                cameraBottomSheetFraction: cameraBottomSheetFraction,
                onPointTap: nil,
                onMapTap: nil,
                onCameraRegionChange: { region in
                    viewModel.cameraRegion = region
                }
            )
            .ignoresSafeArea()
            .onAppear {
                viewModel.showLabels = showLabels
            }
            .onChange(of: showLabels) { _, newValue in
                viewModel.showLabels = newValue
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    MapControlsToolbar(
                        onLocationTap: {
                            Task {
                                if let location = try? await appState.locationService.requestCurrentLocation() {
                                    viewModel.setCameraRegion(MKCoordinateRegion(
                                        center: location.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    ))
                                }
                            }
                        },
                        showingLayersMenu: $showingLayersMenu,
                        topContent: {
                            NorthLockButton(isNorthLocked: $viewModel.isNorthLocked)
                        }
                    ) {
                        LabelsToggleButton(showLabels: $showLabels)

                        Button {
                            if viewModel.isRunning {
                                viewModel.stop()
                            } else {
                                viewModel.start()
                            }
                        } label: {
                            Label(
                                viewModel.isRunning ? "Stop" : "Start",
                                systemImage: viewModel.isRunning ? "record.circle.fill" : "play.fill"
                            )
                            .font(.body.weight(.medium))
                            .foregroundStyle(startStopColor)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                            .buttonStyle(.plain)
                            .labelStyle(.iconOnly)
                        }
                        .disabled(!viewModel.isRunning && !canStartRangeTest)

                        Button {
                            viewModel.addManualBeacon()
                        } label: {
                            Label("Manual Beacon", systemImage: "plus.circle.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(viewModel.isRunning ? Color.accentColor : .secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                                .buttonStyle(.plain)
                                .labelStyle(.iconOnly)
                        }
                        .disabled(!viewModel.isRunning)
                        .accessibilityLabel("Add Manual Beacon")
                    }
                }
            }
            .padding(.bottom, mapOverlayBottomPadding)

            if showingLayersMenu {
                Button {
                    withAnimation { showingLayersMenu = false }
                } label: {
                    Color.black.opacity(0.3).ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Map.Map.Common.dismissOverlay)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        LayersMenu(
                            selection: $mapStyleSelection,
                            isPresented: $showingLayersMenu,
                            viewportBounds: viewModel.cameraRegion?.toMLNCoordinateBounds()
                        )
                        .padding(.trailing)
                    }
                }
                .padding(.bottom, mapOverlayBottomPadding)
            }
        }
    }
}

#Preview("Range Test Map - Sample Points") {
    RangeTestMapPreview()
}

private struct RangeTestMapPreview: View {
    @State private var viewModel = RangeTestViewModel()

    var body: some View {
        RangeTestMapView(viewModel: viewModel)
            .environment(\.appState, AppState())
            .task {
                guard viewModel.beacons.isEmpty else { return }

                let entry = RangeTestHistoryEntry(testID: 456789, beacons: sampleBeacons())
                viewModel.history = [entry]
                viewModel.loadHistoryEntry(entry)
            }
    }

    private func sampleBeacons() -> [RangeTestBeacon] {
        let now = Date()
        let locations: [(lat: Double, lon: Double, altitude: Double, speed: Double, course: Double)] = [
            (37.3348, -122.0090, 14, 1.0, 25),
            (37.3353, -122.0084, 15, 1.6, 52),
            (37.3360, -122.0077, 18, 2.1, 88),
            (37.3366, -122.0069, 21, 1.3, 130),
            (37.3372, -122.0062, 23, 0.8, 165),
        ]

        var beacons = locations.enumerated().map { index, point in
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon),
                altitude: point.altitude,
                horizontalAccuracy: 4 + Double(index),
                verticalAccuracy: 6 + Double(index),
                course: point.course,
                speed: point.speed,
                timestamp: now.addingTimeInterval(TimeInterval(-(locations.count - index) * 20))
            )

            return RangeTestBeacon(
                location: location,
                testID: 456789,
                sequenceNumber: index + 1,
                recipientName: index.isMultiple(of: 2) ? "Team Alpha" : "Team Bravo"
            )
        }

        // Mix ACK states so label rendering and badge values are easy to verify visually.
        beacons[0].messageRoundTripMs = 420
        beacons[0].messageAckCode = 0x0000A1B2
        beacons[0].messageAckSnrDb = 9.1
        beacons[0].messageAckRssiDbm = -88

        beacons[1].messageRoundTripMs = 610
        beacons[1].messageAckCode = 0x0000A1B3

        beacons[2].messageRoundTripMs = 510
        beacons[2].messageAckCode = 0x0000A1B4
        beacons[2].messageAckSnrDb = 7.3
        beacons[2].messageAckRssiDbm = -96

        // Beacon 3 intentionally has no ACK fields.

        beacons[4].messageRoundTripMs = 730
        beacons[4].messageAckCode = 0x0000A1B6
        beacons[4].messageAckRssiDbm = -104

        return beacons
    }
}
