import CoreLocation
import MapKit
import SwiftUI

private let rangeTestSheetDetentExpandedContent: PresentationDetent = .large

// MARK: - Points Filter

private enum PointsFilter: String, CaseIterable {
    case all = "All"
    case hasTelemetry = "Has Telemetry"
    case noTelemetry = "No Telemetry"

    var systemImage: String {
        switch self {
        case .all:           return "list.bullet"
        case .hasTelemetry:  return "checkmark.circle"
        case .noTelemetry:   return "exclamationmark.triangle"
        }
    }

    func matches(_ beacon: RangeTestBeacon) -> Bool {
        switch self {
        case .all:           return true
        case .hasTelemetry:  return beacon.messageRoundTripMs != nil || beacon.messageAckRssiDbm != nil
        case .noTelemetry:   return beacon.messageRoundTripMs == nil && beacon.messageAckRssiDbm == nil
        }
    }
}


struct RangeTestSheetView: View {
    let viewModel: RangeTestViewModel
    @Binding var sheetDetent: PresentationDetent
    let onCenterBeacon: (RangeTestBeacon) -> Void
    let embedsNavigationStack: Bool

    @State private var pointsFilter: PointsFilter = .all
    @State private var showFilterPopover = false

    init(
        viewModel: RangeTestViewModel,
        sheetDetent: Binding<PresentationDetent>,
        onCenterBeacon: @escaping (RangeTestBeacon) -> Void,
        embedsNavigationStack: Bool = true
    ) {
        self.viewModel = viewModel
        _sheetDetent = sheetDetent
        self.onCenterBeacon = onCenterBeacon
        self.embedsNavigationStack = embedsNavigationStack
    }

    var body: some View {
        if embedsNavigationStack {
            NavigationStack {
                content
                    .toolbar(.hidden, for: .navigationBar)
            }
        } else {
            content
        }
    }

    private var content: some View {
            ScrollView {
                VStack(spacing: 16) {
                    recipientsSection
                    if sheetDetent == rangeTestSheetDetentExpandedContent {
                        resultsSection
                        addPointSection
                        pointsSection
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom)
            }
            .scrollDismissesKeyboard(.immediately)
    }

    private var recipientsSection: some View {
        GroupBox {
            if viewModel.recipients.isEmpty {
                Text("No active chats, channels, or favorite repeaters available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.subheadline)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.recipients, id: \.id) { recipient in
                            Button {
                                setRecipientEnabled(id: recipient.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: recipient.iconName)
                                        .font(.caption)
                                    Text(recipient.name)
                                        .lineLimit(1)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(
                                            recipient.isEnabled
                                                ? Color.accentColor.opacity(0.18)
                                                : Color.secondary.opacity(0.14)
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            recipient.isEnabled ? Color.accentColor : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()
                .padding(.vertical, 4)

            Button {
                viewModel.startNewTest()
            } label: {
                Label("Start New Test", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .liquidGlassSecondaryButtonStyle()
            .controlSize(.regular)
            .disabled(!canStartNewTest)
        } label: {
            Text("Recipient")
                .font(.headline)
        }
    }

    private var canStartNewTest: Bool {
        viewModel.isReadyToStart && viewModel.recipients.contains(where: \.isEnabled)
    }

    private var resultsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                Spacer()
                if viewModel.beacons.isEmpty {
                    emptySummaryState
                } else {
                    HStack {
                        Text(viewModel.beacons.averageMessageAckRssiDbm.map { "RSSI: \($0) dBm" } ?? "RSSI: -")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()
                        
                        Text(viewModel.beacons.averageMessageAckSnrDb.map { String(format: "SNR: %.1f dB", $0) } ?? "SNR: -")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.isSummaryExpanded && !viewModel.beacons.isEmpty {
                    Divider()
                        .padding(.vertical, 12)

                    VStack(alignment: .leading, spacing: 14) {
                        summaryRTTSubsection
                        Divider()
                        summaryAckSnrSubsection
                        Divider()
                        summaryAckRssiSubsection
                        Divider()
                        summaryLocationSubsection
                        Divider()
                        summaryTimingSubsection
                    }
                }
            }
        } label: {
            VStack {
                if !viewModel.beacons.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isSummaryExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Results")
                                .font(.headline)

                            TestIDBadge(testID: viewModel.currentTestID)

                            Spacer()
                            
                            Image(systemName: viewModel.isSummaryExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .contentShape(.rect)
                        }
                        
                    }
                    .buttonStyle(.plain)

                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Results")
                            .font(.headline)

                        Spacer()
                    }
                }
                
                if !viewModel.beacons.isEmpty {
                    Spacer()
                    HStack {
                        Text("\(viewModel.beacons.filter { $0.messageAckRssiDbm != nil }.count) of \(viewModel.beacons.count) beacon\(viewModel.beacons.count == 1 ? "" : "s") with acks")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private var addPointSection: some View {
        Button {
            viewModel.addManualBeacon()
        } label: {
            Label("Add Point", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .liquidGlassSecondaryButtonStyle()
        .controlSize(.regular)
        .disabled(!viewModel.canAddManualBeacon)
        .accessibilityLabel("Add Manual Beacon")
    }

    private var emptySummaryState: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to start")
                    .font(.subheadline.weight(.semibold))

                Text("Send a beacon to begin collecting RTT, ACK, and signal stats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var summaryCollapsedContent: some View {
        EmptyView()
    }

    private var summaryStatusSymbol: String {
        if viewModel.beacons.isEmpty {
            return "waveform"
        }
        if viewModel.beacons.messageRoundTripSampleCount == viewModel.beacons.count {
            return "checkmark.circle.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    private var summaryStatusDescription: String {
        if viewModel.beacons.isEmpty {
            return "Send beacons to start collecting RTT and ACK signal stats."
        }
        let responses = viewModel.beacons.messageRoundTripSampleCount
        return "\(responses) of \(viewModel.beacons.count) beacons have RTT/ACK telemetry."
    }

    private var summaryRTTSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Round-Trip Time")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                summaryRow(
                    label: "Average",
                    value: viewModel.beacons.averageMessageRoundTripMs.map { "\($0) ms" } ?? "Unknown"
                )
                if viewModel.beacons.messageRoundTripSampleCount > 1 {
                    Divider()
                    summaryRow(label: "Minimum", value: viewModel.beacons.minimumMessageRoundTripMs.map { "\($0) ms" } ?? "Unknown")
                    Divider()
                    summaryRow(label: "Maximum", value: viewModel.beacons.maximumMessageRoundTripMs.map { "\($0) ms" } ?? "Unknown")
                }
                Divider()
                summaryRow(label: "Samples", value: "\(viewModel.beacons.messageRoundTripSampleCount)")
            }
        }
    }

    private var summaryAckSnrSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACK SNR")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                summaryRow(
                    label: "Average",
                    value: viewModel.beacons.averageMessageAckSnrDb.map {
                        String(format: "%.1f dB", $0)
                    } ?? "Unknown"
                )
                if viewModel.beacons.messageAckSnrSampleCount > 1 {
                    Divider()
                    summaryRow(label: "Minimum", value: viewModel.beacons.minimumMessageAckSnrDb.map { String(format: "%.1f dB", $0) } ?? "Unknown")
                    Divider()
                    summaryRow(label: "Maximum", value: viewModel.beacons.maximumMessageAckSnrDb.map { String(format: "%.1f dB", $0) } ?? "Unknown")
                }
                Divider()
                summaryRow(label: "Samples", value: "\(viewModel.beacons.messageAckSnrSampleCount)")
            }
        }
    }

    private var summaryAckRssiSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACK RSSI")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                summaryRow(
                    label: "Average",
                    value: viewModel.beacons.averageMessageAckRssiDbm.map { "\($0) dBm" } ?? "Unknown"
                )
                if viewModel.beacons.messageAckRssiSampleCount > 1 {
                    Divider()
                    summaryRow(label: "Minimum", value: viewModel.beacons.minimumMessageAckRssiDbm.map { "\($0) dBm" } ?? "Unknown")
                    Divider()
                    summaryRow(label: "Maximum", value: viewModel.beacons.maximumMessageAckRssiDbm.map { "\($0) dBm" } ?? "Unknown")
                }
                Divider()
                summaryRow(label: "Samples", value: "\(viewModel.beacons.messageAckRssiSampleCount)")
                Divider()
                summaryRow(label: "Latest ACK Code", value: latestAckCodeValue)
            }
        }
    }

    private var latestAckCodeValue: String {
        viewModel.beacons.compactMap(\.messageAckCode).last.map { String(format: "0x%08X", $0) } ?? "Unknown"
    }

    private var summaryLocationSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let avg = viewModel.beacons.averageAltitude {
                    summaryRow(label: "Avg Altitude", value: String(format: "%.0f m", avg))
                    Divider()
                }
                if let avg = viewModel.beacons.averageSpeed {
                    summaryRow(label: "Avg Speed", value: String(format: "%.1f m/s", avg))
                    Divider()
                }
                if let avg = viewModel.beacons.averageAccuracy {
                    summaryRow(label: "Avg Accuracy", value: String(format: "+/-%.0f m", avg))
                    Divider()
                }
                summaryRow(
                    label: "Latest Bearing",
                    value: viewModel.beacons.latestBearing.map { String(format: "%.0f deg", $0) } ?? "Unknown"
                )
            }
        }
    }

    private var summaryTimingSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timing")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let first = viewModel.beacons.firstFix {
                    Divider()
                    summaryRow(label: "First Fix", value: first.formatted(date: .omitted, time: .shortened))
                }
                if let last = viewModel.beacons.lastFix {
                    Divider()
                    summaryRow(label: "Last Fix", value: last.formatted(date: .omitted, time: .shortened))
                }
            }
        }
    }

    private var pointsSection: some View {
        GroupBox {
            if viewModel.beacons.isEmpty {
                Text("No points captured yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let beaconsToShow = filteredBeacons
                let reversedBeacons = Array(beaconsToShow.reversed())
                VStack(spacing: 8) {
                    if beaconsToShow.isEmpty {
                        Text("No points match the current filter.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } else {
//                        Spacer().frame(height: 4)
                        LazyVStack(spacing: 6) {
                            ForEach(Array(reversedBeacons.enumerated()), id: \.element.id) { index, beacon in
                                RangeTestPointRow(
                                    beacon: beacon,
                                    color: beaconRTTColor(beacon),
                                    isExpanded: Binding(
                                        get: { viewModel.isBeaconExpanded(beacon.id) },
                                        set: { viewModel.setBeaconExpanded(beacon.id, isExpanded: $0) }
                                    ),
                                    onCenterTap: { onCenterBeacon(beacon) }
                                )

                                if index < reversedBeacons.count - 1 {
                                    Divider()
                              }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack {
                Label("Points", systemImage: "mappin.and.ellipse")
                    .font(.headline)

                Spacer()

                if !viewModel.beacons.isEmpty {
                    Button {
                        showFilterPopover = true
                    } label: {
                        Label(
                            pointsFilter == .all ? "Filter" : pointsFilter.rawValue,
                            systemImage: pointsFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                        )
                        .font(.caption.weight(.medium))
                        .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(pointsFilter == .all ? Color.secondary : Color.accentColor)
                    .popover(isPresented: $showFilterPopover, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        pointsFilterPopover
                    }
                }
            }
        }
    }

    private var pointsFilterPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filter Points")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(PointsFilter.allCases, id: \.self) { filter in
                Button {
                    pointsFilter = filter
                    showFilterPopover = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: filter.systemImage)
                            .frame(width: 18)
                        Text(filter.rawValue)
                        Spacer()
                        if pointsFilter == filter {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Spacer().frame(height: 8)
        }
        .frame(minWidth: 200)
        .presentationCompactAdaptation(.popover)
    }


    private func beaconCountSummary(for count: Int) -> String {
        "\(count) beacon\(count == 1 ? "" : "s")"
    }

    private func csvExport(for beacons: [RangeTestBeacon]) -> String {
        let header = "sequence,timestamp,latitude,longitude,altitude_m,speed_m_s,accuracy_m,bearing_deg,rtt_ms,ack_code,ack_snr_db,ack_rssi_dbm,test_id"
        let rows = beacons.map { b in
            let ts = ISO8601DateFormatter().string(from: b.timestamp)
            let rtt  = b.messageRoundTripMs.map { "\($0)" } ?? ""
            let code = b.messageAckCode.map { String(format: "0x%08X", $0) } ?? ""
            let snr  = b.messageAckSnrDb.map { String(format: "%.1f", $0) } ?? ""
            let rssi = b.messageAckRssiDbm.map { "\($0)" } ?? ""
            let speed = b.speed >= 0 ? String(format: "%.2f", b.speed) : ""
            let acc   = b.accuracy >= 0 ? String(format: "%.1f", b.accuracy) : ""
            let bear  = b.bearing >= 0 ? String(format: "%.1f", b.bearing) : ""
            return "\(b.sequenceNumber),\(ts),\(String(format: "%.6f", b.coordinate.latitude)),\(String(format: "%.6f", b.coordinate.longitude)),\(String(format: "%.1f", b.altitude)),\(speed),\(acc),\(bear),\(rtt),\(code),\(snr),\(rssi),\(b.testID)"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private var
    filteredBeacons: [RangeTestBeacon] {
        viewModel.beacons.filter { pointsFilter.matches($0) }
    }

    private func setRecipientEnabled(id: String) {
        guard let index = viewModel.recipients.firstIndex(where: { $0.id == id }) else { return }
        for recipientIndex in viewModel.recipients.indices {
            viewModel.recipients[recipientIndex].isEnabled = (recipientIndex == index)
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func beaconRTTColor(_ beacon: RangeTestBeacon) -> Color {
        if let rtt = beacon.messageRoundTripMs, rtt > 0 {
            return .green
        }
        return .red
    }
}

private struct TestIDBadge: View {
    let testID: Int

    var body: some View {
        Text(verbatim: String(testID))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.tint.opacity(0.16))
            )
    }
}

private struct HistoryEntryRow: View {
    let entry: RangeTestHistoryEntry
    let onSelect: () -> Void
    let onDelete: () -> Void
    let shareCSV: String
    let shareFilename: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onSelect) {
                TestIDBadge(testID: entry.testID)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Load Test ID \(entry.testID)")

            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
        }
        .contextMenu {
            Button {
                onSelect()
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
        .accessibilityLabel("History row for Test ID \(entry.testID)")
    }
}

private struct RangeTestPointRow: View {
    let beacon: RangeTestBeacon
    let color: Color
    @Binding var isExpanded: Bool
    let onCenterTap: () -> Void

    private let iconButtonSize: CGFloat = 22
    @State private var copyHapticTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .animation(.easeInOut(duration: 0.2), value: isExpanded)
                            Text("Beacon \(beacon.sequenceNumber)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(color)
                        }
                    }
                    .buttonStyle(.plain)

                    if let rssi = beacon.messageAckRssiDbm {
                        Text("RSSI: \(rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Menu {
                    let coord = beacon.coordinate
                    Button("Open in Maps", systemImage: "map") {
                        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                        mapItem.name = "Beacon \(beacon.sequenceNumber)"
                        mapItem.openInMaps()
                    }
                    Button("Copy Coordinates", systemImage: "doc.on.doc") {
                        copyHapticTrigger += 1
                        UIPasteboard.general.string = coord.formattedString
                    }
                    ShareLink(item: coord.formattedString) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                        .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .liquidGlassSecondaryButtonStyle()
                .sensoryFeedback(.success, trigger: copyHapticTrigger)
                .controlSize(.small)

                Button {
                    onCenterTap()
                } label: {
                    Label("Center", systemImage: "mappin")
                        .labelStyle(.iconOnly)
                        .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .liquidGlassSecondaryButtonStyle()
                .controlSize(.small)
            }
            
            if isExpanded {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    pointRow(label: "Captured", value: beacon.timestamp.formatted(date: .omitted, time: .standard))
                    pointRow(label: "Latitude", value: String(format: "%.6f", beacon.coordinate.latitude))
                    pointRow(label: "Longitude", value: String(format: "%.6f", beacon.coordinate.longitude))
                    pointRow(label: "Altitude", value: String(format: "%.0f m", beacon.altitude))
                    pointRow(
                        label: "Speed",
                        value: beacon.speed >= 0 ? String(format: "%.1f m/s", beacon.speed) : "Unknown"
                    )
                    pointRow(
                        label: "Accuracy",
                        value: beacon.accuracy >= 0 ? String(format: "+/-%.0f m", beacon.accuracy) : "Unknown"
                    )
                    pointRow(
                        label: "Bearing",
                        value: beacon.bearing >= 0 ? String(format: "%.0f deg", beacon.bearing) : "Unknown"
                    )
                    pointRow(
                        label: "RTT",
                        value: beacon.messageRoundTripMs.map { "\($0) ms" } ?? "No response"
                    )
                    pointRow(
                        label: "ACK Code",
                        value: beacon.messageAckCode.map { String(format: "0x%08X", $0) } ?? "Unknown"
                    )
                    pointRow(
                        label: "ACK SNR",
                        value: beacon.messageAckSnrDb.map { String(format: "%.1f dB", $0) } ?? "Unknown"
                    )
                    pointRow(
                        label: "ACK RSSI",
                        value: beacon.messageAckRssiDbm.map { "\($0) dBm" } ?? "Unknown"
                    )
                    pointRow(label: "Test ID", value: "\(beacon.testID)")
                    pointRow(label: "Recipient", value: beacon.recipientName ?? "Unknown")
                }
            }
        }
    }

    private func pointRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsTightening(true)
                .minimumScaleFactor(minimumScaleFactor(for: value))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func minimumScaleFactor(for value: String) -> CGFloat {
        value.contains(where: \.isWhitespace) ? 0.8 : 0.65
    }
}

#Preview("Range Test Sheet - Populated") {
    RangeTestSheetPreview(populated: true)
}

#Preview("Range Test Sheet - Empty") {
    RangeTestSheetPreview(populated: false)
}

private struct RangeTestSheetPreview: View {
    @State private var sheetDetent: PresentationDetent = .large
    @State private var viewModel = RangeTestViewModel()
    let populated: Bool

    var body: some View {
        RangeTestSheetView(
            viewModel: viewModel,
            sheetDetent: $sheetDetent,
            onCenterBeacon: { _ in }
        )
        .task {
            guard populated else {
                viewModel.beacons = []
                viewModel.history = []
                return
            }

            if viewModel.beacons.isEmpty {
                viewModel.beacons = sampleBeacons()
            }
            if viewModel.history.isEmpty {
                viewModel.history = sampleHistory()
            }
        }
    }

    private func sampleHistory() -> [RangeTestHistoryEntry] {
        var current = sampleBeacons()
        current[2].messageRoundTripMs = 710
        current[2].messageAckCode = 0x0000A1B4
        current[2].messageAckSnrDb = 7.9
        current[2].messageAckRssiDbm = -95

        var earlier = Array(current.prefix(2))
        earlier[0].messageRoundTripMs = 830
        earlier[0].messageAckCode = 0x0000A0F1
        earlier[0].messageAckSnrDb = 5.4
        earlier[0].messageAckRssiDbm = -101

        return [
            RangeTestHistoryEntry(testID: 123455, beacons: earlier),
        ]
    }

    private func sampleBeacons() -> [RangeTestBeacon] {
        let now = Date()
        let locations = [
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.3348, longitude: -122.0090),
                altitude: 14,
                horizontalAccuracy: 4,
                verticalAccuracy: 6,
                course: 45,
                speed: 1.2,
                timestamp: now.addingTimeInterval(-60)
            ),
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.3351, longitude: -122.0082),
                altitude: 15,
                horizontalAccuracy: 5,
                verticalAccuracy: 6,
                course: 62,
                speed: 1.5,
                timestamp: now.addingTimeInterval(-35)
            ),
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.3355, longitude: -122.0076),
                altitude: 17,
                horizontalAccuracy: 3,
                verticalAccuracy: 5,
                course: 81,
                speed: 1.8,
                timestamp: now.addingTimeInterval(-10)
            ),
        ]

        var beacons = locations.enumerated().map { index, location in
            RangeTestBeacon(location: location, testID: 123456, sequenceNumber: index + 1)
        }

        beacons[0].messageRoundTripMs = 680
        beacons[0].messageAckCode = 0x0000A1B2
        beacons[0].messageAckSnrDb = 8.5
        beacons[0].messageAckRssiDbm = -92

        beacons[1].messageRoundTripMs = 540
        beacons[1].messageAckCode = 0x0000A1B3
        beacons[1].messageAckSnrDb = 9.7
        beacons[1].messageAckRssiDbm = -88

        return beacons
    }
}
