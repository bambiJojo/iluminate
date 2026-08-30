//
//  CableFileImportModelTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct CableFileImportModelTests {
    @Test("An automatic scan refreshes the library and presents a completed batch")
    func automaticScanPublishesImportedBatch() async {
        let imported = AnalysisFixtures.audioFile(filename: "Cable Session.mp3")
        var refreshCount = 0
        let model = CableFileImportModel(
            scan: {
                CableFileImportResult(imported: [imported])
            },
            refreshLibrary: {
                refreshCount += 1
            }
        )

        await model.scan()

        #expect(refreshCount == 1)
        #expect(model.presentedResult?.imported.map(\.id) == [imported.id])
        #expect(model.isScanning == false)
    }

    @Test("An automatic scan stays quiet when there is nothing to report")
    func automaticEmptyScanStaysQuiet() async {
        let model = CableFileImportModel(
            scan: { CableFileImportResult() },
            refreshLibrary: {}
        )

        await model.scan()

        #expect(model.presentedResult == nil)
    }

    @Test("A manual empty scan reports that the inbox is clear")
    func manualEmptyScanReportsResult() async {
        let model = CableFileImportModel(
            scan: { CableFileImportResult() },
            refreshLibrary: {}
        )

        await model.scan(manual: true)

        #expect(model.presentedResult != nil)
        #expect(model.presentedResult?.title == "No New Files Found")
    }

    @Test("Choosing analysis consumes exactly the imported batch")
    func consumesImportedBatchForAnalysis() async {
        let imported = [
            AnalysisFixtures.audioFile(filename: "One.mp3"),
            AnalysisFixtures.audioFile(filename: "Two.mp3")
        ]
        let model = CableFileImportModel(
            scan: { CableFileImportResult(imported: imported) },
            refreshLibrary: {}
        )
        await model.scan()

        let selected = model.consumeImportedForAnalysis()

        #expect(selected.map(\.id) == imported.map(\.id))
        #expect(model.presentedResult == nil)
        #expect(model.consumeImportedForAnalysis().isEmpty)
    }

    @Test("Documents count toward the session without refreshing audio")
    func documentsCountTowardSessionWithoutAudioRefresh() async {
        let document = ReadingDocument(
            id: UUID().uuidString,
            title: "Script",
            kind: .text,
            originalFilename: "Script.txt",
            importedAt: .now,
            wordCount: 12,
            characterCount: 60,
            contentHash: "hash-script",
            textFilename: "Script.txt"
        )
        let counter = ScanCounter()
        var refreshCount = 0
        let model = CableFileImportModel(
            scan: {
                var result = CableFileImportResult()
                if counter.increment() == 1 {
                    result.importedDocuments = [document]
                }
                return result
            },
            refreshLibrary: {
                refreshCount += 1
            }
        )

        await model.scan(manual: true)
        await model.scan(manual: true)

        #expect(model.presentedResult?.priorImportCount == 1)
        #expect(refreshCount == 0)
    }
}

// MARK: - Scan scheduling

/// Main-actor counter; a captured `var` is not expressible from an `@escaping`
/// `@Sendable` closure under strict concurrency.
@MainActor
private final class ScanCounter {
    private(set) var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}

private actor ScanGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

@MainActor
struct CableFileScanSchedulingTests {

    /// The button promises a result. Dropping the tap because an automatic
    /// foreground scan happens to be running is what made a 20-file transfer
    /// look like nothing happened.
    @Test("A manual scan is not swallowed by an in-flight scan")
    func manualScanIsNotSwallowed() async {
        let counter = ScanCounter()
        // Two gates rather than a yield: `async let` gives no guarantee the
        // first scan has begun, so a bare yield made this a coin flip.
        let started = ScanGate()
        let release = ScanGate()
        let model = CableFileImportModel(
            scan: {
                let call = counter.increment()
                if call == 1 {
                    await started.open()
                    await release.wait()
                }
                return CableFileImportResult()
            },
            refreshLibrary: {}
        )

        async let automatic: Void = model.scan()
        await started.wait()          // pass 1 is definitely in flight
        async let manual: Void = model.scan(manual: true)
        await release.open()
        _ = await (automatic, manual)

        #expect(counter.value == 2)
        #expect(model.presentedResult != nil)
    }

    /// "will be checked again later" was a promise nothing kept — the only
    /// triggers were launch, foreground, and the button.
    @Test("Files still copying are rechecked without another tap")
    func rechecksPendingFiles() async {
        let counter = ScanCounter()
        let model = CableFileImportModel(
            scan: {
                var result = CableFileImportResult()
                if counter.increment() == 1 {
                    result.pending = ["Big Session.mp3"]
                } else {
                    result.imported = [AudioFile(
                        filename: "Big Session.mp3",
                        duration: 60,
                        fileSize: 4_000_000
                    )]
                }
                return result
            },
            refreshLibrary: {},
            pendingRecheckDelay: .zero
        )

        await model.scan()

        #expect(counter.value == 2)
        #expect(model.presentedResult?.imported.count == 1)
        // The earlier pending entry must not linger once the file landed.
        #expect(model.presentedResult?.pending.isEmpty == true)
    }

    @Test("Recheck gives up rather than looping forever")
    func pendingRecheckIsBounded() async {
        let counter = ScanCounter()
        let model = CableFileImportModel(
            scan: {
                _ = counter.increment()
                var result = CableFileImportResult()
                result.pending = ["Never Settles.mp3"]
                return result
            },
            refreshLibrary: {},
            pendingRecheckDelay: .zero
        )

        await model.scan(manual: true)

        #expect(counter.value <= 4)
        #expect(model.presentedResult?.pending == ["Never Settles.mp3"])
    }
}

@MainActor
struct CableAudioEmptyResultCopyTests {

    /// The watcher imports automatically, so by the time the user taps Check
    /// the batch is often already in. Telling them to go connect Finder reads
    /// as failure when the transfer in fact succeeded moments earlier.
    @Test("An empty scan after a successful one says nothing new, not nothing happened")
    func emptyResultAcknowledgesEarlierImports() {
        var result = CableFileImportResult()
        result.priorImportCount = 5

        #expect(result.message == "Nothing new to import. 5 transferred files are already in LumeSync.")
        #expect(result.message.contains("Connect your iPhone") == false)
    }

    @Test("An empty scan with no prior imports still explains how to transfer")
    func emptyResultWithoutPriorImportsExplainsTransfer() {
        let result = CableFileImportResult()

        #expect(result.message.contains("drag audio or documents onto LumeSync"))
    }

    @Test("A scan carries forward what earlier passes imported")
    func modelReportsPriorImportsOnALaterEmptyScan() async {
        let counter = ScanCounter()
        let model = CableFileImportModel(
            scan: {
                var result = CableFileImportResult()
                if counter.increment() == 1 {
                    result.imported = [AudioFile(
                        filename: "One.mp3",
                        duration: 60,
                        fileSize: 1_000
                    )]
                }
                return result
            },
            refreshLibrary: {},
            pendingRecheckDelay: .zero
        )

        await model.scan(manual: true)
        await model.scan(manual: true)

        #expect(model.presentedResult?.imported.isEmpty == true)
        #expect(model.presentedResult?.priorImportCount == 1)
    }
}

@MainActor
struct CableFileImportTitleTests {

    /// "No New Files Found" over a body explaining that five files just landed
    /// reads as failure — the title is what a user acts on.
    @Test("An empty scan after imports is titled as success, not absence")
    func emptyResultAfterImportsIsTitledAsSuccess() {
        var result = CableFileImportResult()
        result.priorImportCount = 5

        #expect(result.title == "5 Files Already Added")
    }

    @Test("A single earlier import reads in the singular")
    func singleEarlierImportIsSingular() {
        var result = CableFileImportResult()
        result.priorImportCount = 1

        #expect(result.title == "1 File Already Added")
    }

    @Test("Earlier imports do not hide files that now need review")
    func priorImportsDoNotHideReviewWork() {
        var result = CableFileImportResult()
        result.priorImportCount = 4
        result.duplicates = ["Repeated.mp3"]

        #expect(result.title == "File Transfer Needs Review")
    }

    @Test("A genuinely empty inbox still says nothing was found")
    func trulyEmptyResultKeepsTheAbsenceTitle() {
        #expect(CableFileImportResult().title == "No New Files Found")
    }

    @Test("Files admitted by this very scan are counted in the title")
    func freshImportsAreCountedInTheTitle() {
        var result = CableFileImportResult()
        result.imported = [
            AudioFile(filename: "One.mp3", duration: 1, fileSize: 1),
            AudioFile(filename: "Two.mp3", duration: 1, fileSize: 1)
        ]

        #expect(result.title == "2 Audio Files Added")
    }

    @Test("A mixed transfer names both kinds")
    func mixedTransferNamesBothKinds() {
        var result = CableFileImportResult()
        result.imported = [
            AudioFile(filename: "One.mp3", duration: 1, fileSize: 1),
            AudioFile(filename: "Two.mp3", duration: 1, fileSize: 1)
        ]
        result.importedDocuments = [makeDocument("Script")]

        #expect(result.title == "2 Audio Files, 1 Document Added")
        #expect(result.message.contains("1 document is ready in your Reader."))
    }

    @Test("A documents-only transfer never mentions audio")
    func documentOnlyTransferNeverMentionsAudio() {
        var result = CableFileImportResult()
        result.importedDocuments = [makeDocument("One"), makeDocument("Two")]

        #expect(result.title == "2 Documents Added")
        #expect(result.message.contains("Audio") == false)
    }

    private func makeDocument(_ name: String) -> ReadingDocument {
        ReadingDocument(
            id: UUID().uuidString,
            title: name,
            kind: .text,
            originalFilename: "\(name).txt",
            importedAt: .now,
            wordCount: 12,
            characterCount: 60,
            contentHash: "hash-\(name)",
            textFilename: "\(name).txt"
        )
    }
}

/// Import moves the originals rather than copying them, so a file dragged in
/// through Finder disappears from the folder it was dragged into. The alert is
/// the only place that can say so, and until it did, a successful transfer read
/// as "my files vanished".
@MainActor
struct CableTransferRelocationCopyTests {

    @Test("An audio import says the files are no longer in the Finder folder")
    func audioImportReportsThatOriginalsLeftFinder() {
        var result = CableFileImportResult()
        result.imported = [AudioFile(filename: "One.mp3", duration: 1, fileSize: 1)]

        #expect(result.message.contains("no longer in the Finder folder"))
    }

    /// Reader documents keep a visible original in _Imported, so they must not
    /// borrow the audio wording — the file really is still there.
    @Test("A document import names where the original was filed")
    func documentImportNamesTheArchiveLocation() {
        var result = CableFileImportResult()
        result.importedDocuments = [makeDocument("Script")]

        #expect(result.message.contains("The original moved to _Imported."))
        #expect(result.message.contains("no longer in the Finder folder") == false)
    }

    @Test("Several documents pluralize the archived originals")
    func multipleDocumentsPluralizeTheArchiveSentence() {
        var result = CableFileImportResult()
        result.importedDocuments = [makeDocument("One"), makeDocument("Two")]

        #expect(result.message.contains("The originals moved to _Imported."))
    }

    @Test("Files taken out of dropped folders are counted in the message")
    func subfolderRelocationIsReported() {
        var result = CableFileImportResult()
        result.imported = [
            AudioFile(filename: "One.mp3", duration: 1, fileSize: 1),
            AudioFile(filename: "Two.mp3", duration: 1, fileSize: 1)
        ]
        result.movedFromSubfolderCount = 2

        #expect(result.message.contains("2 files came out of folders"))
    }

    @Test("A single file out of a folder is described in the singular")
    func singleSubfolderRelocationUsesSingularCopy() {
        var result = CableFileImportResult()
        result.imported = [AudioFile(filename: "One.mp3", duration: 1, fileSize: 1)]
        result.movedFromSubfolderCount = 1

        #expect(result.message.contains("1 file came out of a folder"))
    }

    /// A flat drop is the common case. Explaining folder flattening that did not
    /// happen is noise.
    @Test("A flat drop never mentions folders")
    func flatDropOmitsTheFolderSentence() {
        var result = CableFileImportResult()
        result.imported = [AudioFile(filename: "One.mp3", duration: 1, fileSize: 1)]

        #expect(result.message.contains("came out of") == false)
    }

    /// Recheck passes accumulate, so a batch split across two passes must not
    /// lose the count from the first.
    @Test("Recheck passes accumulate the subfolder count")
    func mergeAccumulatesSubfolderCount() {
        var first = CableFileImportResult()
        first.movedFromSubfolderCount = 2
        var second = CableFileImportResult()
        second.movedFromSubfolderCount = 3

        first.merge(second)

        #expect(first.movedFromSubfolderCount == 5)
    }

    private func makeDocument(_ name: String) -> ReadingDocument {
        ReadingDocument(
            id: UUID().uuidString,
            title: name,
            kind: .text,
            originalFilename: "\(name).txt",
            importedAt: .now,
            wordCount: 12,
            characterCount: 60,
            contentHash: "hash-\(name)",
            textFilename: "\(name).txt"
        )
    }
}
