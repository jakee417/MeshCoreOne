import CoreLocation
import MC1Services
import MapKit
import MeshCore
import OSLog
import SwiftUI

// MARK: - Recipient

/// A direct chat or channel that can receive range-test beacons.
struct RangeTestRecipient: Identifiable {
    enum Kind {
        case direct(ContactDTO)
        case channel(ChannelDTO)
        case repeater(ContactDTO)
    }

    let kind: Kind
    let name: String
    var isEnabled: Bool

    var id: String {
        switch kind {
        case .direct(let contact):
            return "dm:\(contact.id.uuidString)"
        case .channel(let channel):
            return "channel:\(channel.id.uuidString)"
        case .repeater(let contact):
            return "repeater:\(contact.id.uuidString)"
        }
    }

    var iconName: String {
        switch kind {
        case .direct:
            return "person.fill"
        case .channel:
            return "number"
        case .repeater:
            return ContactType.repeater.iconSystemName
        }
    }

    var kindLabel: String {
        switch kind {
        case .direct:
            return "Direct"
        case .channel(let channel):
            return "Channel \(Int(channel.index))"
        case .repeater:
            return "Repeater"
        }
    }

    var lastMessageDate: Date? {
        switch kind {
        case .direct(let contact):
            return contact.lastMessageDate
        case .channel(let channel):
            return channel.lastMessageDate
        case .repeater(let contact):
            return contact.lastMessageDate
        }
    }

    init(contact: ContactDTO, isEnabled: Bool) {
        self.kind = .direct(contact)
        self.name = contact.displayName
        self.isEnabled = isEnabled
    }

    init(channel: ChannelDTO, isEnabled: Bool) {
        self.kind = .channel(channel)
        self.name = channel.displayName
        self.isEnabled = isEnabled
    }

    init(repeater: ContactDTO, isEnabled: Bool) {
        self.kind = .repeater(repeater)
        self.name = repeater.displayName
        self.isEnabled = isEnabled
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class RangeTestViewModel: NSObject {

    private static let telemetryLogKey = "RANGE_TEST_ACK_DBG"

    // MARK: - Published state

    var isRunning = false
    var beacons: [RangeTestBeacon] = []
    var recipients: [RangeTestRecipient] = [] {
        didSet { rebuildMapPoints() }
    }
    var errorMessage: String?
    var settings = RangeTestSettings()
    var isSummaryExpanded = false
    var expandedBeaconIDs: Set<UUID> = []
    var isReadyToStart: Bool {
        session != nil && dataStore != nil && messageService != nil
    }

    /// True when a recipient target is selected for outgoing beacon messages.
    var hasSelectedRecipient: Bool {
        recipients.contains(where: \.isEnabled)
    }

    /// Manual points can be captured after a test has started if a recipient is selected.
    var canAddManualBeacon: Bool {
        hasActiveTest && hasSelectedRecipient
    }

    /// True once a test session has been initialised (via startNewTest).
    var hasActiveTest: Bool { testID != 0 }

    /// The test ID of the currently active session (0 if none).
    var currentTestID: Int { testID }
    
    // MARK: - History state
    
    var history: [RangeTestHistoryEntry] = []
    private(set) var loadedHistoryEntry: RangeTestHistoryEntry? = nil

    /// Map camera region (version-bump pattern to trigger camera moves)
    var cameraRegion: MKCoordinateRegion?
    private(set) var cameraRegionVersion = 0

    /// Map points derived from beacons
    private(set) var mapPoints: [MapPoint] = []

    /// Whether point labels should be shown on the map.
    var showLabels = true {
        didSet { rebuildMapPoints() }
    }

    /// Map orientation lock for heads-up/north control
    var isNorthLocked = true

    /// Map lines connecting beacons in sequence
    var mapLines: [MapLine] {
        guard beacons.count > 1 else { return [] }
        var lines: [MapLine] = []
        for i in 0..<(beacons.count - 1) {
            let from = beacons[i]
            let to = beacons[i + 1]
            let line = MapLine(
                id: "beacon-line-\(i)",
                coordinates: [from.coordinate, to.coordinate],
                style: .traceGood,
                opacity: 0.6
            )
            lines.append(line)
        }
        return lines
    }

    /// Haptic triggers
    var beaconSentHapticTrigger = 0
    var startStopHapticTrigger = 0

    // MARK: - Private state

    private let logger = Logger(subsystem: "com.mc1", category: "RangeTestViewModel")
    private let locationManager = CLLocationManager()
    private var historyStore = RangeTestHistoryStore()
    private var lastBeaconTime: Date?
    private var testID: Int = 0
    private var isRequestingPermission = false
    private var dataStore: PersistenceStore?
    private var radioID: UUID?
    private var session: (any MeshCoreSessionProtocol)?
    private var messageService: MessageService?
    private var binaryProtocolService: BinaryProtocolService?
    private var syncCoordinator: SyncCoordinator?
    private var sendTask: Task<Void, Never>?
    private var pendingManualBeaconRequest = false
    private var traceHashMode: UInt8 = 0
    private var traceHashSize = 1

    // MARK: - Configuration

    func configure(appState: AppState) {
        self.dataStore = appState.offlineDataStore
        self.radioID = appState.currentRadioID
        self.session = appState.services?.session
        self.messageService = appState.services?.messageService
        self.binaryProtocolService = appState.services?.binaryProtocolService
        self.syncCoordinator = appState.services?.syncCoordinator
        self.traceHashMode = appState.connectedDevice?.pathHashMode ?? 0
        self.traceHashSize = appState.connectedDevice?.traceHashSize ?? 1
        // Scope history to the connected radio so multiple radios don't share entries.
        historyStore = RangeTestHistoryStore(radioID: appState.currentRadioID)
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        updateBackgroundLocationMode(for: locationManager.authorizationStatus)
        locationManager.pausesLocationUpdatesAutomatically = false
        Task { await loadRecipients() }
        reloadHistory()

        // Start location tracking to pan map to current location on init
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    // MARK: - History management

    func reloadHistory(preferredTestID: Int? = nil) {
        history = historyStore.allEntries(limit: settings.historyLimit)
        ensureHistorySelection(preferredTestID: preferredTestID)
    }

    func loadHistoryEntry(_ entry: RangeTestHistoryEntry) {
        // Preserve in-flight data only when a range test is actively running.
        if isRunning {
            saveCurrentTestProgressToHistory()
        }

        beacons = entry.beacons
        testID = entry.testID
        loadedHistoryEntry = history.first(where: { $0.id == entry.id }) ?? entry
        rebuildMapPoints()
        
        // Update camera to show all beacons
        if !beacons.isEmpty {
            let initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: beacons.map { $0.coordinate.latitude }.reduce(0, +) / Double(beacons.count),
                    longitude: beacons.map { $0.coordinate.longitude }.reduce(0, +) / Double(beacons.count)
                ),
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            )
            cameraRegion = initialRegion
            cameraRegionVersion += 1
        }
    }

    func deleteHistoryEntry(_ entryID: UUID) {
        let removedWasSelected = (loadedHistoryEntry?.id == entryID)
        history.removeAll { $0.id == entryID }
        if removedWasSelected {
            ensureHistorySelection()
        }
        historyStore.deleteEntry(entryID, limit: settings.historyLimit)
    }

    /// Keeps selection valid whenever history changes.
    /// If a preferred test exists, selects it; otherwise preserves current selection
    /// if possible, then falls back to the newest entry.
    private func ensureHistorySelection(preferredTestID: Int? = nil) {
        guard !history.isEmpty else {
            loadedHistoryEntry = nil
            return
        }

        if let preferredTestID,
            let preferredEntry = history.first(where: { $0.testID == preferredTestID })
        {
            loadedHistoryEntry = preferredEntry
            return
        }

        if let selectedID = loadedHistoryEntry?.id,
            let existingSelection = history.first(where: { $0.id == selectedID })
        {
            loadedHistoryEntry = existingSelection
            return
        }

        loadedHistoryEntry = history.first
    }

    // MARK: - Recipients

    func loadRecipients() async {
        guard let dataStore, let radioID else { return }
        do {
            let previousSelection = Dictionary(
                uniqueKeysWithValues: recipients.map { ($0.id, $0.isEnabled) })
            let directConversations = try await dataStore.fetchConversations(radioID: radioID)
            let activeChannels = try await dataStore.fetchChannels(radioID: radioID)
                .filter { $0.lastMessageDate != nil }
            let favoriteRepeaters = try await dataStore.fetchContacts(radioID: radioID)
                .filter { $0.type == .repeater && $0.isFavorite }

            var newRecipients = directConversations.map { contact in
                let candidate = RangeTestRecipient(contact: contact, isEnabled: false)
                return RangeTestRecipient(
                    contact: contact,
                    isEnabled: previousSelection[candidate.id] ?? false
                )
            }

            newRecipients.append(
                contentsOf: activeChannels.map { channel in
                    let candidate = RangeTestRecipient(channel: channel, isEnabled: false)
                    return RangeTestRecipient(
                        channel: channel,
                        isEnabled: previousSelection[candidate.id] ?? false
                    )
                })

            newRecipients.append(
                contentsOf: favoriteRepeaters.map { repeater in
                    let candidate = RangeTestRecipient(repeater: repeater, isEnabled: false)
                    return RangeTestRecipient(
                        repeater: repeater,
                        isEnabled: previousSelection[candidate.id] ?? false
                    )
                })

            newRecipients.sort {
                let lhsDate = $0.lastMessageDate ?? Date.distantPast
                let rhsDate = $1.lastMessageDate ?? Date.distantPast
                return lhsDate > rhsDate
            }

            recipients = newRecipients
        } catch {
            logger.error("Failed to load recipients: \(error.localizedDescription)")
        }
    }

    // MARK: - Start / Stop

    /// Resumes location capture for the currently active test session.
    /// Does not create a new test ID or clear existing beacons.
    /// Use `startNewTest()` to begin a fresh session.
    func start() {
        guard !isRunning else { return }
        guard session != nil else {
            errorMessage = "Connect to a mesh radio to start the range test."
            return
        }
        guard dataStore != nil, messageService != nil else {
            errorMessage = "Range test services are still initializing. Please try start again in a moment."
            return
        }
        guard hasActiveTest else {
            errorMessage = "Tap \"Start New Test\" to begin your first range test."
            return
        }

        let status = locationManager.authorizationStatus
        updateBackgroundLocationMode(for: status)
        switch status {
        case .notDetermined:
            guard !isRequestingPermission else { return }
            isRequestingPermission = true
            locationManager.requestAlwaysAuthorization()
            return
        case .denied, .restricted:
            errorMessage = "Location access is required for the range test. Enable it in Settings."
            return
        case .authorizedWhenInUse:
            break
        default:
            break
        }

        isRequestingPermission = false
        errorMessage = nil

        locationManager.stopUpdatingLocation()
        locationManager.distanceFilter = max(1, settings.minimumDistanceMeters)
        locationManager.startUpdatingLocation()
        locationManager.requestLocation()

        isRunning = true
        startStopHapticTrigger += 1
        logger.info("Range test resumed for testID \(self.testID)")
    }

    /// Creates a brand-new test session: saves any in-progress test, assigns a
    /// fresh test ID, clears current beacons, and starts capturing location.
    func startNewTest() {
        guard session != nil else {
            errorMessage = "Connect to a mesh radio to start the range test."
            return
        }
        guard dataStore != nil, messageService != nil else {
            errorMessage = "Range test services are still initializing. Please try again in a moment."
            return
        }

        // Persist whatever is currently in-flight before switching sessions.
        if !beacons.isEmpty {
            saveCurrentTestProgressToHistory()
        }

        // Assign new identity and clear state *before* the permission check so
        // that if the auth callback fires it can call start() directly.
        beacons.removeAll()
        rebuildMapPoints()
        expandedBeaconIDs.removeAll()
        lastBeaconTime = nil
        cameraRegion = nil
        errorMessage = nil
        testID = Int.random(in: 1...999999)

        let status = locationManager.authorizationStatus
        updateBackgroundLocationMode(for: status)
        switch status {
        case .notDetermined:
            guard !isRequestingPermission else { return }
            isRequestingPermission = true
            locationManager.requestAlwaysAuthorization()
            return
        case .denied, .restricted:
            errorMessage = "Location access is required for the range test. Enable it in Settings."
            return
        case .authorizedWhenInUse:
            break
        default:
            break
        }

        isRequestingPermission = false

        locationManager.stopUpdatingLocation()
        locationManager.distanceFilter = max(1, settings.minimumDistanceMeters)
        locationManager.startUpdatingLocation()
        locationManager.requestLocation()

        isRunning = true
        startStopHapticTrigger += 1
        logger.info("New range test started with testID \(self.testID)")
    }

    func stop() {
        locationManager.stopUpdatingLocation()

        guard isRunning else { return }
        sendTask?.cancel()
        sendTask = nil
        isRunning = false
        isRequestingPermission = false
        startStopHapticTrigger += 1
        logger.info("Range test stopped with \(self.beacons.count) beacons")
        // History is saved incrementally on each beacon; no extra save needed.
    }

    func addManualBeacon() {
        guard canAddManualBeacon else {
            if !hasActiveTest {
                errorMessage = "Tap \"Start New Test\" to begin your first range test."
            } else {
                errorMessage = "Select a recipient before adding a manual beacon."
            }
            return
        }

        errorMessage = nil

        // Reuse the same pipeline as background updates by routing through handleLocation.
        if let currentLocation = locationManager.location {
            handleLocation(currentLocation, bypassIntervalThrottle: true, allowWhenStopped: true)
            return
        }

        pendingManualBeaconRequest = true
        logger.debug("Manual beacon requested without a cached location; requesting a fresh fix")
        locationManager.requestLocation()
    }

    // MARK: - Private helpers

    private func handleLocation(
        _ location: CLLocation,
        bypassIntervalThrottle: Bool = false,
        allowWhenStopped: Bool = false
    ) {
        // Initialize camera once; after that, preserve user panning unless manually recentered.
        if cameraRegion == nil {
            let initialRegion = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            cameraRegion = initialRegion
            cameraRegionVersion += 1
        }

        guard isRunning || allowWhenStopped else { return }

        // Time-based throttle
        if !bypassIntervalThrottle,
            let last = lastBeaconTime,
            Date().timeIntervalSince(last) < settings.minimumIntervalSeconds
        {
            return
        }

        let beacon = RangeTestBeacon(
            location: location,
            testID: testID,
            sequenceNumber: beacons.count + 1,
            recipientName: recipients.first(where: \.isEnabled)?.name
        )
        beacons.append(beacon)
        lastBeaconTime = beacon.timestamp

        // Persist progress as points arrive so an in-flight test is recoverable.
        saveCurrentTestProgressToHistory()

        rebuildMapPoints()

        beaconSentHapticTrigger += 1
        logger.info(
            "Beacon #\(self.beacons.count) captured at \(location.coordinate.latitude), \(location.coordinate.longitude)"
        )

        sendBeacon(beacon)
    }

    private func saveCurrentTestProgressToHistory() {
        guard !beacons.isEmpty else { return }
        let currentTestID = beacons.first?.testID ?? testID
        let entry = RangeTestHistoryEntry(testID: currentTestID, beacons: beacons)
        historyStore.saveEntry(entry, limit: settings.historyLimit)
        reloadHistory(preferredTestID: currentTestID)
    }

    private func sendBeacon(_ beacon: RangeTestBeacon) {
        guard let selectedRecipient = recipients.first(where: \.isEnabled) else {
            logger.warning("Skipped beacon send: no recipient selected")
            return
        }
        guard let messageService else {
            logger.warning("Skipped beacon send: message service unavailable")
            return
        }

        let text = beacon.renderedMessage(template: settings.messageTemplate)
        sendTask = Task {
            guard !Task.isCancelled else { return }
            do {
                switch selectedRecipient.kind {
                case .direct(let contact):
                    let sentMessage = try await messageService.sendDirectMessage(
                        text: text,
                        to: contact
                    )
                    let messageID = sentMessage.id
                    let beaconID = beacon.id
                    Task { @MainActor [weak self] in
                        await self?.captureMessageRTT(for: messageID, beaconID: beaconID)
                    }
                case .channel(let channel):
                    guard let radioID else {
                        logger.warning(
                            "Failed to send beacon to Channel \(Int(channel.index)): missing radioID"
                        )
                        return
                    }
                    _ = try await messageService.sendChannelMessage(
                        text: text,
                        channelIndex: channel.index,
                        radioID: radioID
                    )
                // Channel sends intentionally do not run RTT/SNR ping sampling.
                case .repeater(let repeater):
                    await captureRepeaterTraceTelemetry(for: repeater, beaconID: beacon.id)
                }

                syncCoordinator?.notifyConversationsChanged()
                logger.debug(
                    "Beacon sent to \(selectedRecipient.kindLabel): \(selectedRecipient.name)")
            } catch {
                logger.warning(
                    "Failed to send beacon to \(selectedRecipient.kindLabel) \(selectedRecipient.name): \(error.localizedDescription)"
                )
            }
        }
    }

    private enum RepeaterTracePingError: Error {
        case timeout
    }

    private func captureRepeaterTraceTelemetry(for repeater: ContactDTO, beaconID: UUID) async {
        guard let binaryProtocolService else {
            logger.warning("Skipped repeater trace ping: binary protocol service unavailable")
            return
        }

        let start = ContinuousClock.now
        let sentAt = Date()
        let tag = UInt32.random(in: 0..<UInt32.max)
        let pathData = Data(repeater.publicKey.prefix(traceHashSize))

        do {
            let localSnr = try await withThrowingTaskGroup(of: Double?.self) { group in
                group.addTask {
                    for await notification in NotificationCenter.default.notifications(named: .rxLogTraceReceived) {
                        if let notifTag = notification.userInfo?["tag"] as? UInt32, notifTag == tag {
                            return notification.userInfo?["localSnr"] as? Double
                        }
                    }
                    throw CancellationError()
                }

                let sentInfo = try await binaryProtocolService.sendTrace(
                    tag: tag,
                    flags: traceHashMode,
                    path: pathData
                )

                group.addTask {
                    try await Task.sleep(for: .milliseconds(sentInfo.suggestedTimeoutMs))
                    throw RepeaterTracePingError.timeout
                }

                guard let result = try await group.next() else {
                    throw RepeaterTracePingError.timeout
                }
                group.cancelAll()
                return result
            }

            let latencyMs = Int((ContinuousClock.now - start) / .milliseconds(1))
            setBeaconAckTelemetry(roundTripMs: latencyMs, ackCode: tag, beaconID: beaconID)

            var snr = localSnr
            var rssi: Int?
            if let dataStore, let radioID,
                let traceEntry = try await findTraceEntry(
                    dataStore: dataStore,
                    radioID: radioID,
                    traceTag: tag,
                    sentAt: sentAt
                )
            {
                snr = snr ?? traceEntry.snr
                rssi = traceEntry.rssi
            }

            setBeaconAckSignal(snrDb: snr, rssiDbm: rssi, beaconID: beaconID)
            logger.debug(
                "Captured repeater telemetry beaconID=\(beaconID.uuidString, privacy: .public) tag=\(String(format: "0x%08X", tag), privacy: .public) rttMs=\(latencyMs) snr=\(String(describing: snr), privacy: .public) rssi=\(String(describing: rssi), privacy: .public)"
            )
        } catch {
            logger.warning(
                "Failed repeater trace ping for \(repeater.displayName): \(error.localizedDescription)"
            )
        }
    }

    private func updateBackgroundLocationMode(for status: CLAuthorizationStatus) {
        // Setting this to true before Always authorization can trigger a Core Location assertion.
        locationManager.allowsBackgroundLocationUpdates = (status == .authorizedAlways)
    }

    private func rebuildMapPoints() {
        let beaconPoints = beacons.enumerated().map { index, beacon in
            MapPoint(
                id: beacon.id,
                coordinate: beacon.coordinate,
                pinStyle: .badge,
                label: showLabels ? beaconMapLabel(for: beacon, index: index + 1) : nil,
                isClusterable: true,
                hopIndex: nil,
                badgeText: "\(index + 1)"
            )
        }

        var recipientPoints: [MapPoint] = []
        var seenRecipientIDs: Set<UUID> = []

        for recipient in recipients where recipient.isEnabled {
            let contact: ContactDTO
            switch recipient.kind {
            case .direct(let directContact):
                contact = directContact
            case .repeater(let repeaterContact):
                contact = repeaterContact
            case .channel:
                continue
            }

            guard contact.hasLocation else { continue }
            guard seenRecipientIDs.insert(contact.id).inserted else { continue }

            recipientPoints.append(
                MapPoint(
                    id: contact.id,
                    coordinate: contact.coordinate,
                    pinStyle: .contactRepeater,
                    label: showLabels ? recipient.name : nil,
                    isClusterable: true,
                    hopIndex: nil,
                    badgeText: nil
                )
            )
        }

        mapPoints = beaconPoints + recipientPoints
    }

    private func beaconMapLabel(for beacon: RangeTestBeacon, index _: Int) -> String? {
        guard let rssi = beacon.messageAckRssiDbm else { return nil }
        return "\(rssi) dBm"
    }

    // MARK: - Camera Methods

    func setCameraRegion(_ region: MKCoordinateRegion) {
        cameraRegion = region
        cameraRegionVersion += 1
    }

    func isBeaconExpanded(_ id: UUID) -> Bool {
        expandedBeaconIDs.contains(id)
    }

    func setBeaconExpanded(_ id: UUID, isExpanded: Bool) {
        if isExpanded {
            expandedBeaconIDs.insert(id)
        } else {
            expandedBeaconIDs.remove(id)
        }
    }

    private func captureMessageRTT(for messageID: UUID, beaconID: UUID) async {
        guard let dataStore else { return }

        let start = Date()
        var attempt = 0
        var rttCaptured = false
        let timeoutAt = Date().addingTimeInterval(10)
        logger.debug("\(Self.telemetryLogKey, privacy: .public) start messageID=\(messageID.uuidString, privacy: .public) beaconID=\(beaconID.uuidString, privacy: .public)")

        while Date() < timeoutAt {
            attempt += 1
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            guard !Task.isCancelled else { return }

            if let message = try? await dataStore.fetchMessage(id: messageID) {
                logger.debug(
                    "\(Self.telemetryLogKey, privacy: .public) poll attempt=\(attempt) elapsedMs=\(elapsedMs) hasMessage=true hasRTT=\(message.roundTripTime != nil) hasAckCode=\(message.ackCode != nil)"
                )

                if let roundTripTime = message.roundTripTime {
                    if !rttCaptured {
                        let ackCodeText = message.ackCode.map { String(format: "0x%08X", $0) } ?? "nil"
                        setBeaconAckTelemetry(
                            roundTripMs: Int(roundTripTime),
                            ackCode: message.ackCode,
                            beaconID: beaconID
                        )
                        rttCaptured = true
                        logger.info(
                            "\(Self.telemetryLogKey, privacy: .public) rtt-captured messageID=\(messageID.uuidString, privacy: .public) beaconID=\(beaconID.uuidString, privacy: .public) rttMs=\(roundTripTime) ackCode=\(ackCodeText, privacy: .public)"
                        )
                    }

                    if let ackCode = message.ackCode, let radioID {
                        let ackCodeText = String(format: "0x%08X", ackCode)
                        if let ackEntry = try? await findAckEntry(
                            dataStore: dataStore,
                            radioID: radioID,
                            ackCode: ackCode,
                            sentAt: message.createdAt,
                            roundTripTimeMs: roundTripTime
                        ) {
                            setBeaconAckSignal(
                                snrDb: ackEntry.snr,
                                rssiDbm: ackEntry.rssi,
                                beaconID: beaconID
                            )
                            logger.info(
                                "\(Self.telemetryLogKey, privacy: .public) ack-signal-captured messageID=\(messageID.uuidString, privacy: .public) beaconID=\(beaconID.uuidString, privacy: .public) ackCode=\(ackCodeText, privacy: .public) snr=\(String(describing: ackEntry.snr), privacy: .public) rssi=\(String(describing: ackEntry.rssi), privacy: .public)"
                            )
                            return
                        }

                        logger.debug(
                            "\(Self.telemetryLogKey, privacy: .public) ack-signal-pending attempt=\(attempt) ackCode=\(ackCodeText, privacy: .public)"
                        )
                    } else {
                        logger.debug(
                            "\(Self.telemetryLogKey, privacy: .public) ack-code-or-radio-missing attempt=\(attempt) hasAckCode=\(message.ackCode != nil) hasRadioID=\(self.radioID != nil)"
                        )
                    }
                }
            } else {
                logger.debug(
                    "\(Self.telemetryLogKey, privacy: .public) poll attempt=\(attempt) elapsedMs=\(elapsedMs) hasMessage=false"
                )
            }

            try? await Task.sleep(for: .milliseconds(250))
        }

        logger.warning(
            "\(Self.telemetryLogKey, privacy: .public) timeout messageID=\(messageID.uuidString, privacy: .public) beaconID=\(beaconID.uuidString, privacy: .public) rttCaptured=\(rttCaptured)"
        )
    }

    private func setBeaconAckTelemetry(roundTripMs: Int, ackCode: UInt32?, beaconID: UUID) {
        guard let index = beacons.firstIndex(where: { $0.id == beaconID }) else { return }
        beacons[index].messageRoundTripMs = roundTripMs
        beacons[index].messageAckCode = ackCode
        saveCurrentTestProgressToHistory()
    }

    private func setBeaconAckSignal(snrDb: Double?, rssiDbm: Int?, beaconID: UUID) {
        guard let index = beacons.firstIndex(where: { $0.id == beaconID }) else { return }
        beacons[index].messageAckSnrDb = snrDb
        beacons[index].messageAckRssiDbm = rssiDbm
        saveCurrentTestProgressToHistory()
    }

    private func findAckEntry(
        dataStore: PersistenceStore,
        radioID: UUID,
        ackCode: UInt32,
        sentAt: Date,
        roundTripTimeMs: UInt32
    ) async throws -> RxLogEntryDTO? {
        let expectedPrefix = withUnsafeBytes(of: ackCode.littleEndian) { Data($0) }
        let expectedReceivedAt = sentAt.addingTimeInterval(Double(roundTripTimeMs) / 1000)
        let cutoff = sentAt
        let upperBound = sentAt.addingTimeInterval(15)

        let entries = try await dataStore.fetchRxLogEntries(radioID: radioID, limit: 256)
        let candidates = entries.filter { entry in
            entry.payloadType == .ack &&
                entry.receivedAt >= cutoff &&
                entry.receivedAt <= upperBound &&
                entry.packetPayload.count >= 4 &&
                entry.packetPayload.prefix(4) == expectedPrefix
        }
        let ackCodeText = String(format: "0x%08X", ackCode)

        logger.debug(
            "\(Self.telemetryLogKey, privacy: .public) ack-lookup ackCode=\(ackCodeText, privacy: .public) entries=\(entries.count) candidates=\(candidates.count)"
        )

        let match = candidates.min { lhs, rhs in
            abs(lhs.receivedAt.timeIntervalSince(expectedReceivedAt)) <
                abs(rhs.receivedAt.timeIntervalSince(expectedReceivedAt))
        }

        if let match {
            let deltaMs = Int(abs(match.receivedAt.timeIntervalSince(expectedReceivedAt)) * 1000)
            logger.debug(
                "\(Self.telemetryLogKey, privacy: .public) ack-lookup-match ackCode=\(ackCodeText, privacy: .public) deltaMs=\(deltaMs)"
            )
        }

        return match
    }

    private func findTraceEntry(
        dataStore: PersistenceStore,
        radioID: UUID,
        traceTag: UInt32,
        sentAt: Date
    ) async throws -> RxLogEntryDTO? {
        let expectedPrefix = withUnsafeBytes(of: traceTag.littleEndian) { Data($0) }
        let upperBound = sentAt.addingTimeInterval(15)

        let entries = try await dataStore.fetchRxLogEntries(radioID: radioID, limit: 256)
        return entries.first(where: { entry in
            entry.payloadType == .trace &&
                entry.receivedAt >= sentAt &&
                entry.receivedAt <= upperBound &&
                entry.packetPayload.count >= 4 &&
                entry.packetPayload.prefix(4) == expectedPrefix
        })
    }

}

// MARK: - CLLocationManagerDelegate

extension RangeTestViewModel: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let bypassIntervalThrottle = self.pendingManualBeaconRequest
            let allowWhenStopped = self.pendingManualBeaconRequest
            self.pendingManualBeaconRequest = false
            self.handleLocation(
                location,
                bypassIntervalThrottle: bypassIntervalThrottle,
                allowWhenStopped: allowWhenStopped
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.logger.error("Location error: \(error.localizedDescription)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.updateBackgroundLocationMode(for: status)
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.isRequestingPermission {
                    self.isRequestingPermission = false
                    if !self.isRunning {
                        self.start()
                    }
                }
            } else if status == .denied || status == .restricted {
                self.errorMessage =
                    "Location access is required for the range test. Enable it in Settings."
            }
        }
    }
}
