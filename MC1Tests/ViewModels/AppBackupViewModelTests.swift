import Foundation
import Testing
@testable import MC1
@testable import MC1Services

@Suite("AppBackupViewModel — export success handling")
@MainActor
struct AppBackupViewModelExportTests {

    private func makeViewModel() throws -> AppBackupViewModel {
        let container = try PersistenceStore.createContainer(inMemory: true)
        let manager = ConnectionManager(modelContainer: container)
        return AppBackupViewModel(connectionManager: manager)
    }

    private func sampleManifest(messages: Int = 3, contacts: Int = 2) -> BackupManifest {
        BackupManifest(contactCount: contacts, messageCount: messages)
    }

    @Test("handleExportResult(.success) promotes pendingExport to exportSummary")
    func successPromotesToSummary() throws {
        let vm = try makeViewModel()
        let manifest = sampleManifest()
        vm.pendingExport = AppBackupViewModel.PendingExport(
            data: Data(repeating: 0xAB, count: 128),
            manifest: manifest
        )

        let saveURL = URL(fileURLWithPath: "/tmp/MC1-backup-2026-04-19.mc1backup")
        vm.handleExportResult(.success(saveURL))

        #expect(vm.pendingExport == nil)
        #expect(vm.exportSummary != nil)
        #expect(vm.exportSummary?.filename == "MC1-backup-2026-04-19.mc1backup")
        #expect(vm.exportSummary?.byteCount == 128)
        #expect(vm.exportSummary?.manifest.messageCount == 3)
        #expect(vm.exportSummary?.manifest.contactCount == 2)
        #expect(vm.errorMessage == nil)
    }

    @Test("handleExportResult(.failure(userCancelled)) clears pendingExport without errorMessage")
    func userCancelIsSilent() throws {
        let vm = try makeViewModel()
        vm.pendingExport = AppBackupViewModel.PendingExport(
            data: Data([0x01]),
            manifest: sampleManifest()
        )
        vm.handleExportResult(.failure(CocoaError(.userCancelled)))

        #expect(vm.pendingExport == nil)
        #expect(vm.exportSummary == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test("handleExportResult(.failure(other)) surfaces errorMessage")
    func genericFailureSurfacesErrorMessage() throws {
        let vm = try makeViewModel()
        vm.pendingExport = AppBackupViewModel.PendingExport(
            data: Data([0x01]),
            manifest: sampleManifest()
        )
        let saveError = NSError(domain: NSPOSIXErrorDomain, code: 28) // ENOSPC

        vm.handleExportResult(.failure(saveError))

        #expect(vm.pendingExport == nil)
        #expect(vm.exportSummary == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test("handleExportResult(.success) with no pendingExport is a no-op")
    func successWithoutPendingIsNoOp() throws {
        let vm = try makeViewModel()
        #expect(vm.pendingExport == nil)

        vm.handleExportResult(.success(URL(fileURLWithPath: "/tmp/x.mc1backup")))

        #expect(vm.exportSummary == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test("dismissExportSuccess clears the summary")
    func dismissClearsSummary() throws {
        let vm = try makeViewModel()
        vm.exportSummary = AppBackupViewModel.ExportSuccessSummary(
            filename: "x.mc1backup",
            byteCount: 1,
            manifest: sampleManifest()
        )

        vm.dismissExportSuccess()

        #expect(vm.exportSummary == nil)
    }
}
