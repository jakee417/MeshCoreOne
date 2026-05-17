import Foundation
import MC1Services
import Testing

@testable import MC1

@Suite("Range Test Manual Point Eligibility")
@MainActor
struct RangeTestViewModelManualPointTests {

    @Test("manual point is disabled until a test is active")
    func manualPointDisabledWithoutActiveTest() {
        let viewModel = RangeTestViewModel()
        viewModel.recipients = [makeRecipient(isEnabled: true)]

        #expect(viewModel.canAddManualBeacon == false)
    }

    @Test("manual point is enabled for a started test with a selected recipient")
    func manualPointEnabledWithActiveTestAndRecipient() {
        let viewModel = RangeTestViewModel()
        viewModel.loadHistoryEntry(RangeTestHistoryEntry(testID: 42, beacons: []))
        viewModel.recipients = [makeRecipient(isEnabled: true)]

        #expect(viewModel.isRunning == false)
        #expect(viewModel.canAddManualBeacon == true)
    }

    @Test("addManualBeacon asks for new test when no test is active")
    func addManualBeaconRequiresActiveTest() {
        let viewModel = RangeTestViewModel()
        viewModel.recipients = [makeRecipient(isEnabled: true)]

        viewModel.addManualBeacon()

        #expect(viewModel.errorMessage == "Tap \"Start New Test\" to begin your first range test.")
    }

    @Test("addManualBeacon asks for recipient when no recipient is selected")
    func addManualBeaconRequiresRecipientSelection() {
        let viewModel = RangeTestViewModel()
        viewModel.loadHistoryEntry(RangeTestHistoryEntry(testID: 42, beacons: []))
        viewModel.recipients = [makeRecipient(isEnabled: false)]

        viewModel.addManualBeacon()

        #expect(viewModel.errorMessage == "Select a recipient before adding a manual beacon.")
    }

    @Test("addManualBeacon is allowed after test start even when currently stopped")
    func addManualBeaconAllowedWhenStoppedWithActiveTestAndRecipient() {
        let viewModel = RangeTestViewModel()
        viewModel.loadHistoryEntry(RangeTestHistoryEntry(testID: 42, beacons: []))
        viewModel.recipients = [makeRecipient(isEnabled: true)]

        viewModel.addManualBeacon()

        #expect(viewModel.isRunning == false)
        #expect(viewModel.errorMessage == nil)
    }

    private func makeRecipient(isEnabled: Bool) -> RangeTestRecipient {
        let contact = ContactDTO(
            id: UUID(),
            radioID: UUID(),
            publicKey: Data(repeating: 0x11, count: 32),
            name: "Test Recipient",
            typeRawValue: ContactType.direct.rawValue,
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
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
        return RangeTestRecipient(contact: contact, isEnabled: isEnabled)
    }
}
