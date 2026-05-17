import CoreLocation
import Foundation
import MC1Services
import Testing

@testable import MC1

@Suite("Range Test Template Tests")
struct RangeTestTemplateTests {

    @Test("Message template defaults when unset")
    func messageTemplateDefaultsWhenUnset() throws {
        let suite = "RangeTestTemplateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = RangeTestSettings(defaults: defaults)
        #expect(settings.messageTemplate == RangeTestSettings.defaultMessageTemplate)
    }

    @Test("Message template stores custom values")
    func messageTemplateStoresCustomValues() throws {
        let suite = "RangeTestTemplateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = RangeTestSettings(defaults: defaults)
        settings.messageTemplate = "beacon <lat>,<lon>"

        #expect(settings.messageTemplate == "beacon <lat>,<lon>")
    }

    @Test("Message template falls back when blank")
    func messageTemplateFallsBackWhenBlank() throws {
        let suite = "RangeTestTemplateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = RangeTestSettings(defaults: defaults)
        settings.messageTemplate = "   "

        #expect(settings.messageTemplate == RangeTestSettings.defaultMessageTemplate)
    }

    @Test("Beacon renders token template")
    func beaconRendersTokenTemplate() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 12.3456789, longitude: -98.7654321),
            altitude: 123.4,
            horizontalAccuracy: 5.6,
            verticalAccuracy: 2.0,
            course: 270.0,
            speed: 1.25,
            timestamp: timestamp
        )

        let beacon = RangeTestBeacon(location: location, testID: 42, sequenceNumber: 3)
        let text = beacon.renderedMessage(template: "id=<id> seq=<seq> lat=<lat> lon=<lon> alt=<alt> speed=<speed> acc=<acc> bearing=<bearing> unix=<unix>")

        #expect(text == "id=42 seq=3 lat=12.345679 lon=-98.765432 alt=123.4 speed=1.2 acc=5.6 bearing=270 unix=1700000000")
    }

    @Test("Unknown tokens are preserved")
    func unknownTokensArePreserved() {
        let location = CLLocation(latitude: 1, longitude: 2)
        let beacon = RangeTestBeacon(location: location, testID: 1, sequenceNumber: 1)

        let text = beacon.renderedMessage(template: "hello <unknown> <lat>")

        #expect(text.contains("<unknown>"))
        #expect(text.contains("1.000000"))
    }

    @Test("Repeater recipient has repeater metadata")
    func repeaterRecipientMetadata() {
        let repeater = ContactDTO(
            id: UUID(),
            radioID: UUID(),
            publicKey: Data(repeating: 0x2A, count: 32),
            name: "Field Repeater",
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: true,
            lastMessageDate: nil,
            unreadCount: 0
        )

        let recipient = RangeTestRecipient(repeater: repeater, isEnabled: true)

        #expect(recipient.iconName == "antenna.radiowaves.left.and.right")
        #expect(recipient.kindLabel == "Repeater")
        #expect(recipient.id.starts(with: "repeater:"))
    }
}
