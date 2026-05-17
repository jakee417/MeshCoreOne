import MapKit
import SwiftUI
import UIKit

struct RangeTestHistorySheetView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: RangeTestViewModel
    @State private var editMode: EditMode = .inactive
    @State private var selectedEntryIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.history.isEmpty {
                    ContentUnavailableView {
                        Label("No History", systemImage: "clock")
                    } description: {
                        Text("Complete a range test to see it here.")
                    }
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if isEditing {
                        Button(allSelected ? "Deselect All" : "Select All") {
                            toggleSelectAll()
                        }
                        Spacer()
                        Button("Delete Selected", role: .destructive) {
                            deleteSelected()
                        }
                        .disabled(selectedEntryIDs.isEmpty)
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .onChange(of: viewModel.history.map(\.id)) { _, currentIDs in
                selectedEntryIDs = selectedEntryIDs.intersection(Set(currentIDs))
            }
        }
    }

    private var historyList: some View {
        Group {
            if isEditing {
                List(selection: $selectedEntryIDs) {
                    historySection(isSelectable: true)
                }
            } else {
                List {
                    historySection(isSelectable: false)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func historySection(isSelectable: Bool) -> some View {
        Section {
            ForEach(viewModel.history) { entry in
                if isSelectable {
                    RangeTestHistoryRow(
                        entry: entry,
                        onLoad: {
                            viewModel.loadHistoryEntry(entry)
                            dismiss()
                        },
                        onDelete: { viewModel.deleteHistoryEntry(entry.id) },
                        shareCSV: csvExport(for: entry.beacons),
                        shareFilename: "range_test_\(entry.testID).csv",
                        isEditing: isEditing
                    )
                    .tag(entry.id)
                } else {
                    RangeTestHistoryRow(
                        entry: entry,
                        onLoad: {
                            viewModel.loadHistoryEntry(entry)
                            dismiss()
                        },
                        onDelete: { viewModel.deleteHistoryEntry(entry.id) },
                        shareCSV: csvExport(for: entry.beacons),
                        shareFilename: "range_test_\(entry.testID).csv",
                        isEditing: isEditing
                    )
                }
            }
        } header: {
            historyStatusHeader
                .textCase(nil)
        }
    }

    private var historyStatusHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Stored")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())

            Text("\(viewModel.history.count) test\(viewModel.history.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var isEditing: Bool {
        editMode == .active
    }

    private var allSelected: Bool {
        !viewModel.history.isEmpty && selectedEntryIDs.count == viewModel.history.count
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedEntryIDs.removeAll()
        } else {
            selectedEntryIDs = Set(viewModel.history.map(\.id))
        }
    }

    private func deleteSelected() {
        guard !selectedEntryIDs.isEmpty else { return }
        let ids = selectedEntryIDs
        selectedEntryIDs.removeAll()
        for id in ids {
            viewModel.deleteHistoryEntry(id)
        }
    }

    private func csvExport(for beacons: [RangeTestBeacon]) -> String {
        let header = "sequence,timestamp,latitude,longitude,altitude_m,speed_m_s,accuracy_m,bearing_deg,rtt_ms,ack_code,ack_snr_db,ack_rssi_dbm,test_id"
        let rows = beacons.map { b in
            let ts = ISO8601DateFormatter().string(from: b.timestamp)
            let rtt = b.messageRoundTripMs.map { "\($0)" } ?? ""
            let code = b.messageAckCode.map { String(format: "0x%08X", $0) } ?? ""
            let snr = b.messageAckSnrDb.map { String(format: "%.1f", $0) } ?? ""
            let rssi = b.messageAckRssiDbm.map { "\($0)" } ?? ""
            let speed = b.speed >= 0 ? String(format: "%.2f", b.speed) : ""
            let acc = b.accuracy >= 0 ? String(format: "%.1f", b.accuracy) : ""
            let bear = b.bearing >= 0 ? String(format: "%.1f", b.bearing) : ""
            return "\(b.sequenceNumber),\(ts),\(String(format: "%.6f", b.coordinate.latitude)),\(String(format: "%.6f", b.coordinate.longitude)),\(String(format: "%.1f", b.altitude)),\(speed),\(acc),\(bear),\(rtt),\(code),\(snr),\(rssi),\(b.testID)"
        }
        return ([header] + rows).joined(separator: "\n")
    }
}

private struct RangeTestHistoryRow: View {
    let entry: RangeTestHistoryEntry
    let onLoad: () -> Void
    let onDelete: () -> Void
    let shareCSV: String
    let shareFilename: String
    let isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                HistoryTestIDBadge(testID: entry.testID)
                Text(beaconCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            RecipientBadgeStrip(recipients: recipientBadges)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .contentShape(.rect)
        .onTapGesture {
            guard !isEditing else { return }
            onLoad()
        }
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditing {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                ShareLink(
                    item: shareCSV,
                    preview: SharePreview(shareFilename, image: Image(systemName: "tablecells"))
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if !isEditing {
                Button {
                    onLoad()
                } label: {
                    Label("Load", systemImage: "arrow.down.circle")
                }

                ShareLink(
                    item: shareCSV,
                    preview: SharePreview(shareFilename, image: Image(systemName: "tablecells"))
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } preview: {
            HistoryEntryContextMapPreview(entry: entry)
        }
    }

    private var beaconCountText: String {
        let count = entry.beacons.count
        return "\(count) beacon\(count == 1 ? "" : "s")"
    }

    private var uniqueRecipients: [String] {
        var seen = Set<String>()
        return entry.beacons
            .compactMap(\.recipientName)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private var recipientBadges: [String] {
        uniqueRecipients.isEmpty ? ["Unknown"] : uniqueRecipients
    }
}

private struct RecipientBadgeStrip: View {
    let recipients: [String]

    private let spacing: CGFloat = 6
    private let horizontalPadding: CGFloat = 8
    private let verticalPadding: CGFloat = 3
    private let badgeFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .medium)

    var body: some View {
        GeometryReader { proxy in
            let layout = visibleRecipients(for: proxy.size.width)

            HStack(spacing: spacing) {
                ForEach(layout.visible, id: \.self) { recipient in
                    RecipientBadgeView(text: recipient)
                }

                if layout.hiddenCount > 0 {
                    RecipientBadgeView(text: "+\(layout.hiddenCount)", isOverflow: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: badgeHeight)
    }

    private var badgeHeight: CGFloat {
        badgeFont.lineHeight + (verticalPadding * 2)
    }

    private func visibleRecipients(for totalWidth: CGFloat) -> (visible: [String], hiddenCount: Int) {
        guard totalWidth > 0 else {
            return (recipients, 0)
        }

        let normalized = recipients.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let candidates = normalized.filter { !$0.isEmpty }
        let list = candidates.isEmpty ? ["Unknown"] : candidates

        for visibleCount in stride(from: list.count, through: 0, by: -1) {
            let hiddenCount = list.count - visibleCount
            let visible = Array(list.prefix(visibleCount))

            var requiredWidth: CGFloat = visible.reduce(0) { partial, recipient in
                partial + badgeWidth(for: recipient)
            }

            var badgeCount = visible.count
            if hiddenCount > 0 {
                requiredWidth += badgeWidth(for: "+\(hiddenCount)")
                badgeCount += 1
            }

            if badgeCount > 1 {
                requiredWidth += CGFloat(badgeCount - 1) * spacing
            }

            if requiredWidth <= totalWidth {
                return (visible, hiddenCount)
            }
        }

        return ([], recipients.count)
    }

    private func badgeWidth(for text: String) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: badgeFont]).width
        return ceil(textWidth) + (horizontalPadding * 2)
    }
}

private struct RecipientBadgeView: View {
    let text: String
    var isOverflow: Bool = false

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(isOverflow ? Color.accentColor : Color.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .allowsTightening(true)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    isOverflow
                        ? Color.accentColor.opacity(0.18)
                        : Color.secondary.opacity(0.14)
                )
            )
    }
}

private struct HistoryEntryContextMapPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appState) private var appState
    @AppStorage("mapStyleSelection") private var mapStyleSelection: MapStyleSelection = .standard
    @AppStorage("mapShowLabels") private var showLabels = false

    let entry: RangeTestHistoryEntry

    private var mapPoints: [MapPoint] {
        entry.beacons.enumerated().map { index, beacon in
            MapPoint(
                id: beacon.id,
                coordinate: beacon.coordinate,
                pinStyle: .badge,
                label: showLabels ? mapLabel(for: beacon, index: index + 1) : nil,
                isClusterable: true,
                hopIndex: nil,
                badgeText: "\(index + 1)"
            )
        }
    }
                
    private var region: MKCoordinateRegion? {
        entry.beacons.map(\.coordinate).boundingRegion(paddingMultiplier: 2.0)
    }

    private func mapLabel(for beacon: RangeTestBeacon, index _: Int) -> String? {
        guard let rssi = beacon.messageAckRssiDbm else { return nil }
        return "\(rssi) dBm"
    }

    var body: some View {
        if let region {
            MC1MapView(
                points: mapPoints,
                lines: [],
                mapStyle: mapStyleSelection,
                isDarkMode: colorScheme == .dark,
                isOffline: !appState.offlineMapService.isNetworkAvailable,
                showLabels: showLabels,
                showsUserLocation: false,
                isInteractive: false,
                showsScale: false,
                cameraRegion: .constant(region),
                cameraRegionVersion: 1,
                onPointTap: nil,
                onMapTap: nil,
                onCameraRegionChange: nil
            )
            .frame(width: 260, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ContentUnavailableView {
                Label("No Points", systemImage: "mappin.slash")
            } description: {
                Text("No beacon coordinates are stored for this test.")
            }
            .frame(width: 260, height: 180)
        }
    }
}

private struct HistoryTestIDBadge: View {
    let testID: Int

    var body: some View {
        Text(verbatim: String(testID))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.tint.opacity(0.16)))
    }
}

#Preview("History Sheet - Populated") {
    RangeTestHistorySheetPreview(populated: true)
}

#Preview("History Sheet - Empty") {
    RangeTestHistorySheetPreview(populated: false)
}

private struct RangeTestHistorySheetPreview: View {
    @State private var viewModel = RangeTestViewModel()
    let populated: Bool

    var body: some View {
        RangeTestHistorySheetView(viewModel: viewModel)
            .task {
                if populated {
                    viewModel.history = [
                        RangeTestHistoryEntry(
                            testID: 123456,
                            beacons: sampleBeacons(
                                testID: 123456,
                                origin: CLLocationCoordinate2D(latitude: 47.6206, longitude: -122.3493),
                                recipients: ["Alpha Team", "Bravo Team", "Alpha Team", "Charlie Team"]
                            )
                        ),
                        RangeTestHistoryEntry(
                            testID: 123455,
                            beacons: sampleBeacons(
                                testID: 123455,
                                origin: CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331),
                                recipients: ["Ops Channel", "Ops Channel", "Ops Channel", "Ops Channel"]
                            )
                        ),
                        RangeTestHistoryEntry(
                            testID: 123454,
                            beacons: sampleBeacons(
                                testID: 123454,
                                origin: CLLocationCoordinate2D(latitude: 47.6038, longitude: -122.3301),
                                recipients: [nil, nil, nil, nil]
                            )
                        ),
                    ]
                } else {
                    viewModel.history = []
                }
            }
    }

    private func sampleBeacons(
        testID: Int,
        origin: CLLocationCoordinate2D,
        recipients: [String?] = []
    ) -> [RangeTestBeacon] {
        let now = Date()
        let offsets: [(lat: Double, lon: Double, altitude: Double, speed: Double, course: Double)] = [
            (0.0000, 0.0000, 18.0, 1.2, 35.0),
            (0.0007, 0.0005, 21.0, 1.5, 48.0),
            (0.0012, 0.0009, 24.0, 1.8, 61.0),
            (0.0016, 0.0014, 27.0, 2.0, 78.0),
        ]

        return offsets.enumerated().map { index, offset in
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: origin.latitude + offset.lat,
                    longitude: origin.longitude + offset.lon
                ),
                altitude: offset.altitude,
                horizontalAccuracy: 4.5,
                verticalAccuracy: 7.5,
                course: offset.course,
                speed: offset.speed,
                timestamp: now.addingTimeInterval(TimeInterval(-(offsets.count - index) * 12))
            )

            let recipientName = recipients.indices.contains(index) ? recipients[index] : nil
            var beacon = RangeTestBeacon(
                location: location,
                testID: testID,
                sequenceNumber: index + 1,
                recipientName: recipientName
            )
            beacon.messageRoundTripMs = 180 + (index * 25)
            beacon.messageAckCode = UInt32(0xA1B2_0000 + index)
            beacon.messageAckSnrDb = 9.5 + (Double(index) * 1.2)
            beacon.messageAckRssiDbm = -102 + (index * 2)
            return beacon
        }
    }
}
