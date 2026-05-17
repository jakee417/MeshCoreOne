import CoreLocation
import Foundation

/// A single location fix captured and broadcast during a range test.
struct RangeTestBeacon: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let coordinate: CLLocationCoordinate2D
    let altitude: Double  // metres
    let speed: Double  // m/s, negative if unavailable
    let accuracy: Double  // horizontal accuracy in metres
    let bearing: Double  // course in degrees true north, negative if unavailable
    let testID: Int  // random identifier for this range test session
    let sequenceNumber: Int  // 1-based sequence in this test
    let recipientName: String?  // selected recipient when this beacon was captured
    var messageRoundTripMs: Int?  // direct message ACK RTT in milliseconds
    var messageAckCode: UInt32?  // exact ACK code matched to this beacon send
    var messageAckSnrDb: Double?  // SNR (dB) for the ACK packet in RX log
    var messageAckRssiDbm: Int?  // RSSI (dBm) for the ACK packet in RX log

    init(
        id: UUID = UUID(),
        location: CLLocation,
        testID: Int,
        sequenceNumber: Int,
        recipientName: String? = nil
    ) {
        self.id = id
        self.timestamp = location.timestamp
        self.coordinate = location.coordinate
        self.altitude = location.altitude
        self.speed = location.speed
        self.accuracy = location.horizontalAccuracy
        self.bearing = location.course
        self.testID = testID
        self.sequenceNumber = sequenceNumber
        self.recipientName = recipientName
        self.messageRoundTripMs = nil
        self.messageAckCode = nil
        self.messageAckSnrDb = nil
        self.messageAckRssiDbm = nil
    }

    static let availableTemplateTokens: [String] = [
        "<id>", "<seq>", "<lat>", "<lon>", "<alt>", "<speed>", "<acc>", "<bearing>", "<ts>",
        "<unix>",
    ]

    /// JSON text payload sent to each recipient using the default template.
    var messageText: String {
        renderedMessage(template: RangeTestSettings.defaultMessageTemplate)
    }

    /// Expands a user-provided template into a beacon payload.
    func renderedMessage(template: String) -> String {
        let safeTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeTemplate.isEmpty ? RangeTestSettings.defaultMessageTemplate : safeTemplate

        let replacements: [String: String] = [
            "<id>": "\(testID)",
            "<seq>": "\(sequenceNumber)",
            "<lat>": format(coordinate.latitude, precision: 6),
            "<lon>": format(coordinate.longitude, precision: 6),
            "<alt>": format(altitude, precision: 1),
            "<speed>": speed >= 0 ? format(speed, precision: 1) : "",
            "<acc>": accuracy >= 0 ? format(accuracy, precision: 1) : "",
            "<bearing>": bearing >= 0 ? format(bearing, precision: 0) : "",
            "<ts>": timestamp.formatted(.iso8601),
            "<unix>": "\(Int(timestamp.timeIntervalSince1970))",
        ]

        return replacements.reduce(base) { partial, replacement in
            partial.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }

    private func format(_ value: Double, precision: Int) -> String {
        String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), precision, value)
    }
}

extension RangeTestBeacon: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case latitude
        case longitude
        case altitude
        case speed
        case accuracy
        case bearing
        case testID
        case sequenceNumber
        case recipientName
        case messageRoundTripMs
        case messageAckCode
        case messageAckSnrDb
        case messageAckRssiDbm
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        altitude = try container.decode(Double.self, forKey: .altitude)
        speed = try container.decode(Double.self, forKey: .speed)
        accuracy = try container.decode(Double.self, forKey: .accuracy)
        bearing = try container.decode(Double.self, forKey: .bearing)
        testID = try container.decode(Int.self, forKey: .testID)
        sequenceNumber = try container.decode(Int.self, forKey: .sequenceNumber)
        recipientName = try container.decodeIfPresent(String.self, forKey: .recipientName)
        messageRoundTripMs = try container.decodeIfPresent(Int.self, forKey: .messageRoundTripMs)
        messageAckCode = try container.decodeIfPresent(UInt32.self, forKey: .messageAckCode)
        messageAckSnrDb = try container.decodeIfPresent(Double.self, forKey: .messageAckSnrDb)
        messageAckRssiDbm = try container.decodeIfPresent(Int.self, forKey: .messageAckRssiDbm)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(altitude, forKey: .altitude)
        try container.encode(speed, forKey: .speed)
        try container.encode(accuracy, forKey: .accuracy)
        try container.encode(bearing, forKey: .bearing)
        try container.encode(testID, forKey: .testID)
        try container.encode(sequenceNumber, forKey: .sequenceNumber)
        try container.encodeIfPresent(recipientName, forKey: .recipientName)
        try container.encodeIfPresent(messageRoundTripMs, forKey: .messageRoundTripMs)
        try container.encodeIfPresent(messageAckCode, forKey: .messageAckCode)
        try container.encodeIfPresent(messageAckSnrDb, forKey: .messageAckSnrDb)
        try container.encodeIfPresent(messageAckRssiDbm, forKey: .messageAckRssiDbm)
    }
}

// MARK: - Summary statistics over a collection of beacons

extension BidirectionalCollection where Element == RangeTestBeacon {
    var averageMessageRoundTripMs: Int? {
        let values = compactMap { $0.messageRoundTripMs }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    var minimumMessageRoundTripMs: Int? {
        compactMap { $0.messageRoundTripMs }.min()
    }

    var maximumMessageRoundTripMs: Int? {
        compactMap { $0.messageRoundTripMs }.max()
    }

    var messageRoundTripSampleCount: Int {
        compactMap { $0.messageRoundTripMs }.count
    }

    var averageMessageAckSnrDb: Double? {
        let values = compactMap { $0.messageAckSnrDb }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var minimumMessageAckSnrDb: Double? {
        compactMap { $0.messageAckSnrDb }.min()
    }

    var maximumMessageAckSnrDb: Double? {
        compactMap { $0.messageAckSnrDb }.max()
    }

    var messageAckSnrSampleCount: Int {
        compactMap { $0.messageAckSnrDb }.count
    }

    var averageMessageAckRssiDbm: Int? {
        let values = compactMap { $0.messageAckRssiDbm }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    var minimumMessageAckRssiDbm: Int? {
        compactMap { $0.messageAckRssiDbm }.min()
    }

    var maximumMessageAckRssiDbm: Int? {
        compactMap { $0.messageAckRssiDbm }.max()
    }

    var messageAckRssiSampleCount: Int {
        compactMap { $0.messageAckRssiDbm }.count
    }

    var averageAltitude: Double? {
        guard !isEmpty else { return nil }
        return reduce(0) { $0 + $1.altitude } / Double(count)
    }

    var averageSpeed: Double? {
        let valid = filter { $0.speed >= 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0) { $0 + $1.speed } / Double(valid.count)
    }

    var averageAccuracy: Double? {
        let valid = filter { $0.accuracy >= 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0) { $0 + $1.accuracy } / Double(valid.count)
    }

    var latestBearing: Double? {
        let bearings = filter { $0.bearing >= 0 }
        return bearings.last?.bearing
    }

    var firstFix: Date? { first?.timestamp }
    var lastFix: Date? { last?.timestamp }
}
