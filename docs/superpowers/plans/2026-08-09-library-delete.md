# Easier Library Deletion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make deleting audio files from the library fast and recoverable — swipe-to-delete on a row, tap-anywhere multi-select with Select All, and a 6-second undo banner instead of confirmation alerts.

**Architecture:** Deletes move the audio file into a staging directory under Application Support and drop the row from `audioFiles`. Nothing is destroyed until the batch commits (timer, dismiss, view disappear, or a new delete). A `PendingAudioDeletion` model owns all of that file/state logic with no SwiftUI in it, so it unit-tests directly; the view layer only renders a banner and calls four methods.

**Tech Stack:** SwiftUI, Swift 6.2 strict concurrency, `@Observable`, Swift Testing, `os.Logger`.

**Spec:** [2026-08-09-library-delete-design.md](../specs/2026-08-09-library-delete-design.md)

---

## Why staging exists (read before Task 1)

`AudioLibraryStore.discoverUnregisteredDocumentFiles` (`Ilumionate/AudioLibraryStore.swift:121`) scans `Documents` on every library load and **auto-registers any audio file that isn't already in the library**. So you cannot implement undo by dropping the row and leaving the file where it is — a reload during the undo window puts the row straight back. The file has to physically move out of `Documents`.

The same reasoning drives the error handling: if a move to staging fails, the row must **stay in the library**. Removing the row while the file survives in `Documents` is the one genuinely broken outcome, because the next scan resurrects it as a duplicate.

## File structure

| File | Responsibility | Status |
|---|---|---|
| `Ilumionate/PendingAudioDeletion.swift` | Staging directory, stage/restore/commit/sweep. No SwiftUI. | Create (Tasks 1–3) |
| `IlumionateTests/PendingAudioDeletionTests.swift` | Unit tests for the above | Create (Tasks 1–3) |
| `Ilumionate/UndoDeleteBanner.swift` | Banner presentation only | Create (Task 5) |
| `Ilumionate/SwipeToDeleteRow.swift` | Reusable swipe gesture modifier | Create (Task 6) |
| `Ilumionate/IlumionateApp.swift` | Call `sweepOrphans()` at launch | Modify (Task 3) |
| `Ilumionate/AudioLibraryView+Actions.swift` | `deleteFile` / `deleteSelectedFiles` / `undoDelete` / `toggleSelectAll` | Modify (Tasks 4, 7) |
| `Ilumionate/AudioLibraryView.swift` | Host banner, drop the bulk alert, Select All toolbar | Modify (Tasks 5, 7) |
| `Ilumionate/AudioLibraryView+Filtering.swift` | Conditional `NavigationLink`, attach swipe | Modify (Tasks 6, 7) |
| `Ilumionate/AudioFileRow.swift` | Move Delete to top of context menu | Modify (Task 8) |

## Build and test commands

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PendingAudioDeletionTests
```

macOS is the fast loop. Task 9 runs the full suite on both platforms.

> **New files need Xcode target membership.** After creating a `.swift` file, confirm it is a member of the `Ilumionate` target (test files: `IlumionateTests`). If a build fails with "cannot find X in scope" right after adding a file, this is why.

---

## Task 1: `PendingAudioDeletion` — stage and restore

**Files:**
- Create: `Ilumionate/PendingAudioDeletion.swift`
- Create: `IlumionateTests/PendingAudioDeletionTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `IlumionateTests/PendingAudioDeletionTests.swift`:

```swift
//
//  PendingAudioDeletionTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct PendingAudioDeletionTests {

    // MARK: - Fixture

    /// A temp root holding a fake Documents directory and a staging directory.
    private struct Fixture {
        let root: URL
        let documentsURL: URL
        let stagingURL: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }

        /// Writes a real file on disk and returns an AudioFile pointing at it by
        /// absolute path, so `file.url` resolves inside the fixture rather than
        /// the app's real Documents directory.
        func makeFile(named name: String, contents: String = "audio") throws -> AudioFile {
            let url = documentsURL.appending(path: name)
            try Data(contents.utf8).write(to: url)
            return AudioFile(filename: url.path, duration: 60, fileSize: 5)
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PendingAudioDeletionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let documentsURL = root.appending(path: "Documents", directoryHint: .isDirectory)
        let stagingURL = root.appending(path: "Staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        return Fixture(root: root, documentsURL: documentsURL, stagingURL: stagingURL)
    }

    private func makeSubject(
        _ fixture: Fixture,
        onDeleteSession: @escaping @MainActor (AudioFile) -> Void = { _ in }
    ) -> PendingAudioDeletion {
        PendingAudioDeletion(
            stagingRoot: fixture.stagingURL,
            deleteGeneratedSession: onDeleteSession
        )
    }

    // MARK: - Tests

    @Test
    func stagingMovesTheFileOutOfItsOriginalLocation() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)
        let file = try fixture.makeFile(named: "one.mp3")

        let staged = subject.stage([
            StagedAudioFile(file: file, originalURL: file.url, originalIndex: 0)
        ])

        #expect(staged.count == 1)
        #expect(subject.staged.count == 1)
        #expect(FileManager.default.fileExists(atPath: file.url.path) == false)
    }

    @Test
    func restoreReturnsTheFileToItsExactOriginalURL() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)
        let file = try fixture.makeFile(named: "one.mp3", contents: "original bytes")
        let originalURL = file.url

        subject.stage([StagedAudioFile(file: file, originalURL: originalURL, originalIndex: 3)])
        let recovered = subject.restore()

        #expect(recovered.count == 1)
        #expect(recovered.first?.originalIndex == 3)
        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        let contents = try String(contentsOf: originalURL, encoding: .utf8)
        #expect(contents == "original bytes")
        #expect(subject.staged.isEmpty)
    }

    @Test
    func twoFilesSharingALastPathComponentBothSurvive() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)

        // Same filename, different directories — a real possibility because
        // training and migration flows store absolute paths.
        let nested = fixture.documentsURL.appending(path: "nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let first = try fixture.makeFile(named: "same.mp3", contents: "first")
        let secondURL = nested.appending(path: "same.mp3")
        try Data("second".utf8).write(to: secondURL)
        let second = AudioFile(filename: secondURL.path, duration: 60, fileSize: 6)

        subject.stage([
            StagedAudioFile(file: first, originalURL: first.url, originalIndex: 0),
            StagedAudioFile(file: second, originalURL: second.url, originalIndex: 1)
        ])
        let recovered = subject.restore()

        #expect(recovered.count == 2)
        #expect(try String(contentsOf: first.url, encoding: .utf8) == "first")
        #expect(try String(contentsOf: second.url, encoding: .utf8) == "second")
    }

    @Test
    func restoreReturnsEntriesInAscendingOriginalIndexOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)

        let a = try fixture.makeFile(named: "a.mp3")
        let b = try fixture.makeFile(named: "b.mp3")
        let c = try fixture.makeFile(named: "c.mp3")

        subject.stage([
            StagedAudioFile(file: c, originalURL: c.url, originalIndex: 7),
            StagedAudioFile(file: a, originalURL: a.url, originalIndex: 1),
            StagedAudioFile(file: b, originalURL: b.url, originalIndex: 4)
        ])

        #expect(subject.restore().map(\.originalIndex) == [1, 4, 7])
    }

    @Test
    func aFileThatCannotBeStagedIsNotReportedAsStaged() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)

        let real = try fixture.makeFile(named: "real.mp3")
        // Never written to disk — the move must fail.
        let missingURL = fixture.documentsURL.appending(path: "ghost.mp3")
        let ghost = AudioFile(filename: missingURL.path, duration: 60, fileSize: 0)

        let staged = subject.stage([
            StagedAudioFile(file: real, originalURL: real.url, originalIndex: 0),
            StagedAudioFile(file: ghost, originalURL: ghost.url, originalIndex: 1)
        ])

        #expect(staged.count == 1)
        #expect(staged.first?.file.id == real.id)
        #expect(subject.staged.count == 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PendingAudioDeletionTests
```

Expected: compile failure — `cannot find 'PendingAudioDeletion' in scope` and `cannot find 'StagedAudioFile' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Ilumionate/PendingAudioDeletion.swift`:

```swift
//
//  PendingAudioDeletion.swift
//  Ilumionate
//
//  Holds just-deleted audio files in a staging directory so a delete can be
//  undone. Staging lives outside Documents on purpose: AudioLibraryStore scans
//  Documents on every load and re-registers anything it finds there, so a file
//  left in place during the undo window would reappear in the library.
//

import Foundation
import os

/// One file held for possible undo, with everything needed to put it back.
struct StagedAudioFile: Sendable, Identifiable {
    let file: AudioFile
    /// Recorded rather than recomputed. `AudioFile.url` derives from `filename`,
    /// and training/migration flows store absolute paths pointing outside
    /// Documents — recomputing would restore some files to the wrong place.
    let originalURL: URL
    /// Index in `audioFiles` before removal, so undo restores order, not just presence.
    let originalIndex: Int

    var id: AudioFile.ID { file.id }
}

@MainActor
@Observable
final class PendingAudioDeletion {
    static let shared = PendingAudioDeletion()

    /// The batch currently held for undo. Empty means nothing is pending.
    private(set) var staged: [StagedAudioFile] = []

    private let stagingRoot: URL
    private let fileManager: FileManager
    private let deleteGeneratedSession: @MainActor (AudioFile) -> Void

    init(
        stagingRoot: URL = URL.applicationSupportDirectory
            .appending(path: "PendingAudioDeletion", directoryHint: .isDirectory),
        fileManager: FileManager = .default,
        deleteGeneratedSession: @escaping @MainActor (AudioFile) -> Void = {
            GeneratedSessionStore.shared.delete(for: $0)
        }
    ) {
        self.stagingRoot = stagingRoot
        self.fileManager = fileManager
        self.deleteGeneratedSession = deleteGeneratedSession
    }

    // MARK: - Staging

    /// Moves each file into staging. Any previously staged batch is committed
    /// first — only one batch is ever recoverable.
    ///
    /// - Returns: the entries that actually moved. A file that could not be
    ///   staged must stay in the library; dropping its row while the file
    ///   survives in Documents would resurrect it on the next library scan.
    @discardableResult
    func stage(_ entries: [StagedAudioFile]) -> [StagedAudioFile] {
        commit()

        var succeeded: [StagedAudioFile] = []
        for entry in entries {
            let folder = folderURL(for: entry)
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appending(path: entry.originalURL.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: entry.originalURL, to: destination)
                succeeded.append(entry)
            } catch {
                try? fileManager.removeItem(at: folder)
                Log.audio.error(
                    "Could not stage \(entry.file.filename, privacy: .public) for deletion: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        staged = succeeded
        return succeeded
    }

    // MARK: - Undo

    /// Moves every staged file back to its original location.
    ///
    /// - Returns: the entries that came back, ascending by `originalIndex` so a
    ///   caller can re-insert them in order. A file that failed to move back is
    ///   omitted — re-inserting a row whose file is gone yields a library entry
    ///   that cannot play.
    @discardableResult
    func restore() -> [StagedAudioFile] {
        var recovered: [StagedAudioFile] = []
        for entry in staged {
            let source = folderURL(for: entry).appending(path: entry.originalURL.lastPathComponent)
            do {
                try fileManager.createDirectory(
                    at: entry.originalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: source, to: entry.originalURL)
                recovered.append(entry)
            } catch {
                Log.audio.error(
                    "Could not restore \(entry.file.filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            try? fileManager.removeItem(at: folderURL(for: entry))
        }

        staged = []
        return recovered.sorted { $0.originalIndex < $1.originalIndex }
    }

    // MARK: - Helpers

    /// One folder per file ID, so two files sharing a last path component
    /// cannot collide in staging.
    private func folderURL(for entry: StagedAudioFile) -> URL {
        stagingRoot.appending(path: entry.file.id.uuidString, directoryHint: .isDirectory)
    }
}
```

> `commit()` does not exist yet — Task 2 adds it. To keep Task 1 compiling, add this temporary stub at the bottom of the class and **delete it in Task 2**:
>
> ```swift
>     func commit() { staged = [] }
> ```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PendingAudioDeletionTests
```

Expected: 5 tests, all passing.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/PendingAudioDeletion.swift IlumionateTests/PendingAudioDeletionTests.swift
git commit -m "feat(library): stage deleted audio outside Documents so deletes can be undone"
```

---

## Task 2: `commit()` — make the delete permanent

**Files:**
- Modify: `Ilumionate/PendingAudioDeletion.swift`
- Modify: `IlumionateTests/PendingAudioDeletionTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `PendingAudioDeletionTests`, before the closing brace:

```swift
    @Test
    func commitDeletesTheStagedFileAndItsGeneratedSession() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var sessionsDeleted: [AudioFile.ID] = []
        let subject = makeSubject(fixture) { sessionsDeleted.append($0.id) }
        let file = try fixture.makeFile(named: "one.mp3")

        subject.stage([StagedAudioFile(file: file, originalURL: file.url, originalIndex: 0)])
        subject.commit()

        #expect(subject.staged.isEmpty)
        #expect(sessionsDeleted == [file.id])
        #expect(FileManager.default.fileExists(atPath: file.url.path) == false)
        // Nothing left behind in staging.
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.stagingURL,
            includingPropertiesForKeys: nil
        )
        #expect(leftovers.isEmpty)
    }

    @Test
    func stagingANewBatchCommitsThePreviousOne() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var sessionsDeleted: [AudioFile.ID] = []
        let subject = makeSubject(fixture) { sessionsDeleted.append($0.id) }
        let first = try fixture.makeFile(named: "first.mp3")
        let second = try fixture.makeFile(named: "second.mp3")

        subject.stage([StagedAudioFile(file: first, originalURL: first.url, originalIndex: 0)])
        subject.stage([StagedAudioFile(file: second, originalURL: second.url, originalIndex: 0)])

        // The first batch is gone for good; only the second is recoverable.
        #expect(sessionsDeleted == [first.id])
        #expect(subject.staged.map(\.file.id) == [second.id])

        let recovered = subject.restore()
        #expect(recovered.count == 1)
        #expect(FileManager.default.fileExists(atPath: second.url.path))
        #expect(FileManager.default.fileExists(atPath: first.url.path) == false)
    }

    @Test
    func generatedSessionSurvivesUntilCommit() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var sessionsDeleted: [AudioFile.ID] = []
        let subject = makeSubject(fixture) { sessionsDeleted.append($0.id) }
        let file = try fixture.makeFile(named: "one.mp3")

        subject.stage([StagedAudioFile(file: file, originalURL: file.url, originalIndex: 0)])
        #expect(sessionsDeleted.isEmpty, "the light session must outlive the undo window")

        subject.restore()
        #expect(sessionsDeleted.isEmpty, "undo must not destroy the light session")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PendingAudioDeletionTests
```

Expected: `commitDeletesTheStagedFileAndItsGeneratedSession` and `stagingANewBatchCommitsThePreviousOne` FAIL — the Task 1 stub clears `staged` without deleting anything, so `sessionsDeleted` stays empty and the staged file is still on disk. `generatedSessionSurvivesUntilCommit` already passes.

- [ ] **Step 3: Replace the stub with the real implementation**

Delete the temporary `func commit() { staged = [] }` stub and add this in a new `// MARK: - Commit` section after `restore()`:

```swift
    // MARK: - Commit

    /// Destroys the staged batch for real: the staged copies and each file's
    /// generated light session. Called by the undo timer, banner dismissal,
    /// the library disappearing, or the next `stage(_:)`.
    func commit() {
        guard !staged.isEmpty else { return }

        for entry in staged {
            do {
                try fileManager.removeItem(at: folderURL(for: entry))
            } catch {
                // sweepOrphans() reclaims this at next launch.
                Log.audio.error(
                    "Could not remove staged \(entry.file.filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            deleteGeneratedSession(entry.file)
            Log.audio.info("🗑 Deleted: \(entry.file.filename, privacy: .public)")
        }

        staged = []
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PendingAudioDeletionTests
```

Expected: 8 tests, all passing.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/PendingAudioDeletion.swift IlumionateTests/PendingAudioDeletionTests.swift
git commit -m "feat(library): commit staged deletes and their generated sessions"
```

---

## Task 3: `sweepOrphans()` and launch wiring

If the app is killed mid-undo-window, the staged files are already out of `audioFiles` but still on disk. Without a sweep they sit there forever.

**Files:**
- Modify: `Ilumionate/PendingAudioDeletion.swift`
- Modify: `IlumionateTests/PendingAudioDeletionTests.swift`
- Modify: `Ilumionate/IlumionateApp.swift:48-58`

- [ ] **Step 1: Write the failing tests**

Append to `PendingAudioDeletionTests`, before the closing brace:

```swift
    @Test
    func sweepOrphansEmptiesTheStagingDirectory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        // Simulate a batch left over from a killed session.
        let orphan = fixture.stagingURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: orphan.appending(path: "stale.mp3"))

        let subject = makeSubject(fixture)
        subject.sweepOrphans()

        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.stagingURL,
            includingPropertiesForKeys: nil
        )
        #expect(leftovers.isEmpty)
    }

    @Test
    func sweepOrphansLeavesALiveBatchAlone() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)
        let file = try fixture.makeFile(named: "one.mp3")

        subject.stage([StagedAudioFile(file: file, originalURL: file.url, originalIndex: 0)])
        subject.sweepOrphans()

        // Still recoverable — sweeping must never eat a pending undo.
        #expect(subject.restore().count == 1)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test
    func sweepOrphansOnAMissingDirectoryIsHarmless() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        // stagingURL was never created — nothing has been staged yet.
        makeSubject(fixture).sweepOrphans()
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PendingAudioDeletionTests
```

Expected: compile failure — `value of type 'PendingAudioDeletion' has no member 'sweepOrphans'`.

- [ ] **Step 3: Write the implementation**

Add to `PendingAudioDeletion`, after `commit()`:

```swift
    // MARK: - Launch cleanup

    /// Clears anything left in staging by a session that was killed mid-undo.
    /// Those files are already absent from the library, so the delete stood —
    /// this only reclaims the disk space. Call once at launch.
    func sweepOrphans() {
        guard staged.isEmpty else { return }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in contents {
            try? fileManager.removeItem(at: url)
        }
        if !contents.isEmpty {
            Log.audio.info("🧹 Swept \(contents.count) orphaned pending deletion(s)")
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PendingAudioDeletionTests
```

Expected: 11 tests, all passing.

- [ ] **Step 5: Call the sweep at launch**

In `Ilumionate/IlumionateApp.swift`, the `init()` currently ends like this:

```swift
        UsageAnalytics.configure()
        #if os(macOS)
        BackgroundAnalysisScheduler.shared.register()
        #endif
    }
```

Replace with:

```swift
        UsageAnalytics.configure()
        #if os(macOS)
        BackgroundAnalysisScheduler.shared.register()
        #endif
        // Reclaim files left staged by a session that was killed during an
        // undo window. They are already gone from the library.
        PendingAudioDeletion.shared.sweepOrphans()
    }
```

> SwiftUI's `App` conformance is `@MainActor`-isolated, so this direct call should compile as-is. If the compiler instead reports *"call to main actor-isolated ... in a synchronous nonisolated context"*, wrap it:
>
> ```swift
>         MainActor.assumeIsolated {
>             PendingAudioDeletion.shared.sweepOrphans()
>         }
> ```
>
> Do **not** reach for `Task { @MainActor in ... }` here — that defers the sweep and lets the first library load race it.

- [ ] **Step 6: Build to verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Ilumionate/PendingAudioDeletion.swift IlumionateTests/PendingAudioDeletionTests.swift Ilumionate/IlumionateApp.swift
git commit -m "feat(library): sweep orphaned pending deletions at launch"
```

---

## Task 4: Route library deletes through staging

**Files:**
- Modify: `Ilumionate/AudioLibraryView+Actions.swift:75-86` (`deleteFile`) and `:137-146` (`deleteSelectedFiles`)
- Modify: `Ilumionate/AudioLibraryView.swift:87` (state)

No unit test here — these are `AudioLibraryView` extension methods operating on view state, and the logic they now delegate to is already covered by Tasks 1–3. Verification is the build plus the manual pass in Task 9.

- [ ] **Step 1: Add the model to the view's state**

In `Ilumionate/AudioLibraryView.swift`, replace this line:

```swift
    @State var showingDeleteSelectedAlert = false
```

with:

```swift
    @State var pendingDeletion = PendingAudioDeletion.shared
    /// Which row currently has its swipe action revealed. Only one at a time.
    @State var openSwipeRowID: AudioFile.ID?
```

- [ ] **Step 2: Rewrite `deleteFile`**

In `Ilumionate/AudioLibraryView+Actions.swift`, replace the whole `deleteFile` function:

```swift
    func deleteFile(_ file: AudioFile) {
        // Delete the audio file
        try? FileManager.default.removeItem(at: file.url)

        // Delete the generated session if it exists
        GeneratedSessionStore.shared.delete(for: file)

        // Remove from list
        audioFiles.removeAll { $0.id == file.id }
        Task { await saveAudioFiles() }
        Log.audio.info("🗑 Deleted: \(file.filename)")
    }
```

with:

```swift
    /// Removes the row and stages the file for undo. Nothing is destroyed here —
    /// `PendingAudioDeletion.commit()` does that once the undo window closes.
    func deleteFile(_ file: AudioFile) {
        guard let index = audioFiles.firstIndex(where: { $0.id == file.id }) else { return }

        let staged = pendingDeletion.stage([
            StagedAudioFile(file: file, originalURL: file.url, originalIndex: index)
        ])

        // The move failed, so the file is still sitting in Documents. Keep the
        // row: dropping it would let the next library scan re-register the file
        // as a duplicate.
        guard !staged.isEmpty else { return }

        audioFiles.remove(at: index)
        Task { await saveAudioFiles() }
        TranceHaptics.shared.medium()
    }
```

- [ ] **Step 3: Rewrite `deleteSelectedFiles` and add `undoDelete`**

Replace the whole `deleteSelectedFiles` function:

```swift
    func deleteSelectedFiles() {
        let filesToDelete = audioFiles.filter { selectedFiles.contains($0.id) }
        for file in filesToDelete {
            deleteFile(file)
        }

        // Exit selection mode
        selectedFiles.removeAll()
        isSelectionMode = false
    }
```

with:

```swift
    /// Stages the whole selection as one batch, so a single Undo brings all of
    /// it back. Calling `deleteFile` in a loop would not — each `stage(_:)`
    /// commits the batch before it.
    func deleteSelectedFiles() {
        let entries = audioFiles.enumerated()
            .filter { selectedFiles.contains($0.element.id) }
            .map { index, file in
                StagedAudioFile(file: file, originalURL: file.url, originalIndex: index)
            }
        guard !entries.isEmpty else { return }

        let staged = pendingDeletion.stage(entries)
        let stagedIDs = Set(staged.map(\.file.id))
        audioFiles.removeAll { stagedIDs.contains($0.id) }
        Task { await saveAudioFiles() }
        TranceHaptics.shared.medium()

        selectedFiles.removeAll()
        isSelectionMode = false
    }

    /// Puts the staged batch back where it came from.
    func undoDelete() {
        let recovered = pendingDeletion.restore()
        // Ascending by original index, so inserting in order reproduces the
        // original arrangement. Clamped because filters or a concurrent reload
        // may have changed the array's length in the meantime.
        for entry in recovered {
            audioFiles.insert(entry.file, at: min(entry.originalIndex, audioFiles.count))
        }
        Task { await saveAudioFiles() }
        TranceHaptics.shared.light()
        Log.audio.info("↩️ Restored \(recovered.count) deleted file(s)")
    }
```

- [ ] **Step 4: Remove the now-dead bulk alert**

In `Ilumionate/AudioLibraryView.swift`, delete this modifier entirely (the undo banner replaces it):

```swift
            .alert("Delete \(selectedFiles.count) Files?", isPresented: $showingDeleteSelectedAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSelectedFiles()
                }
            } message: {
                Text("Are you sure you want to delete these audio files? This action cannot be undone.")
            }
```

And in the selection toolbar, change the trash button's action from raising the alert to deleting directly:

```swift
                                Button {
                                    TranceHaptics.shared.medium()
                                    showingDeleteSelectedAlert = true
                                } label: {
```

becomes:

```swift
                                Button {
                                    deleteSelectedFiles()
                                } label: {
```

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

Expected: `BUILD SUCCEEDED`. If it fails with `cannot find 'showingDeleteSelectedAlert'`, a reference to the removed state survived — search for it and remove it.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/AudioLibraryView.swift Ilumionate/AudioLibraryView+Actions.swift
git commit -m "feat(library): route deletes through staging instead of destroying immediately"
```

> At this point deletes are recoverable but nothing exposes Undo. Task 5 adds the banner.

---

## Task 5: The undo banner

**Files:**
- Create: `Ilumionate/UndoDeleteBanner.swift`
- Modify: `Ilumionate/AudioLibraryView.swift`

- [ ] **Step 1: Create the banner view**

Create `Ilumionate/UndoDeleteBanner.swift`:

```swift
//
//  UndoDeleteBanner.swift
//  Ilumionate
//

import SwiftUI

/// Transient confirmation that a delete happened, with a way back.
/// Presentation only — the caller owns the timer and the undo action.
struct UndoDeleteBanner: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: "trash")
                .font(.callout)
                .foregroundStyle(.textSecondary)

            Text(message)
                .font(TranceTypography.caption)
                .foregroundStyle(.textPrimary)
                .lineLimit(1)

            Spacer(minLength: TranceSpacing.inner)

            Button("Undo", action: onUndo)
                .font(TranceTypography.caption)
                .bold()
                .foregroundStyle(.roseGold)

            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.textLight)
        }
        .padding(.horizontal, TranceSpacing.card)
        .padding(.vertical, TranceSpacing.list)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: TranceRadius.thumbnail))
        .overlay(
            RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                .strokeBorder(Color.glassBorder.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, TranceSpacing.screen)
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        UndoDeleteBanner(message: "Deleted “Deep Rest”", onUndo: {}, onDismiss: {})
    }
}
```

- [ ] **Step 2: Host the banner in the library**

In `Ilumionate/AudioLibraryView.swift`, the outer `ZStack` currently reads:

```swift
            ZStack {
                // Trance background
                Color.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
```

Add the banner as the last child of that `ZStack` — after the closing brace of the `VStack`, still inside the `ZStack`:

```swift
                if !pendingDeletion.staged.isEmpty {
                    VStack {
                        Spacer()
                        UndoDeleteBanner(
                            message: undoBannerMessage,
                            onUndo: { undoDelete() },
                            onDismiss: { pendingDeletion.commit() }
                        )
                        .padding(.bottom, TranceSpacing.tabBarClearance)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
```

It sits in the outer `ZStack` deliberately, above **both** `emptyState` and `audioLibraryContent`: deleting your last file flips the screen to the empty state, and Undo has to stay reachable from there.

- [ ] **Step 3: Add the message and the commit triggers**

Add this computed property to `AudioLibraryView`, next to `analysisAttentionCount`:

```swift
    private var undoBannerMessage: String {
        let staged = pendingDeletion.staged
        guard staged.count == 1, let only = staged.first else {
            return "\(staged.count) files deleted"
        }
        return "Deleted “\(only.file.displayName)”"
    }
```

Then add these modifiers alongside the existing `.task { ... }` on the `NavigationStack`:

```swift
            .animation(.snappy(duration: 0.25), value: pendingDeletion.staged.count)
            .task(id: pendingDeletion.staged.map(\.id)) {
                guard !pendingDeletion.staged.isEmpty else { return }
                // Re-runs whenever the batch changes, cancelling the previous
                // wait — so a second delete restarts the window rather than
                // inheriting the remains of the first.
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                pendingDeletion.commit()
            }
            .onDisappear {
                // Leaving the library finalizes the delete.
                pendingDeletion.commit()
            }
```

> **Where this modifier goes matters.** Attached to the `NavigationStack` (as here), it fires when the
> user leaves the Audio tab — but *not* when they push a detail screen, because the stack itself stays
> alive. So navigating into a file keeps Undo available, and switching tabs commits. That is the
> intended behavior. If you attach it to the inner `VStack` instead, pushing any detail screen silently
> finalizes the delete, which is not what the spec asks for. Manual checks 7 and 8 in Task 9 confirm
> you got this right.

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Verify by hand in the simulator**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run the app, go to the Audio tab, long-press a row → Delete. Confirm: the row vanishes, the banner appears, and Undo restores the row **to its original position** (not to the top). Then delete again and let the banner time out; the row must not come back after switching tabs and returning.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/UndoDeleteBanner.swift Ilumionate/AudioLibraryView.swift
git commit -m "feat(library): add undo banner for deleted audio"
```

---

## Task 6: Swipe-to-delete

The rows live in a `LazyVStack` inside a `GlassCard`, not a `List`, so `.swipeActions` is unavailable — hence a hand-rolled gesture. **This is the riskiest task in the plan.** Budget time for tuning.

**Files:**
- Create: `Ilumionate/SwipeToDeleteRow.swift`
- Modify: `Ilumionate/AudioLibraryView+Filtering.swift:17-30`

- [ ] **Step 1: Create the modifier**

Create `Ilumionate/SwipeToDeleteRow.swift`:

```swift
//
//  SwipeToDeleteRow.swift
//  Ilumionate
//

import SwiftUI

/// Swipe-left-to-reveal-delete for rows in a custom stack.
///
/// `List`'s `.swipeActions` only works inside a `List`, and the audio library
/// draws its rows in a `LazyVStack` inside a `GlassCard` to keep the Trance
/// styling. This reproduces the gesture without giving that up.
///
/// The revealed action is sized to exactly the strip the row vacates, so it
/// never shows through the row's transparent background.
struct SwipeToDeleteRow<ID: Hashable>: ViewModifier {
    let id: ID
    /// Which row is open, shared across rows so only one opens at a time.
    @Binding var openRowID: ID?
    var isEnabled: Bool = true
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0

    private static var actionWidth: CGFloat { 76 }
    private static var triggerDistance: CGFloat { 40 }

    private var isOpen: Bool { openRowID == id }

    /// Resting position plus whatever the finger is currently adding, clamped
    /// so the row never slides right past its home position.
    private var offset: CGFloat {
        let resting = isOpen ? -Self.actionWidth : 0
        return min(0, max(-Self.actionWidth, resting + dragOffset))
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            deleteAction
            content
                .offset(x: offset)
                .simultaneousGesture(dragGesture, isEnabled: isEnabled)
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { close() }
        }
    }

    private var deleteAction: some View {
        Button(role: .destructive) {
            close()
            onDelete()
        } label: {
            Color.red
                .overlay {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                // Exactly the width the row has vacated.
                .frame(width: max(0, -offset))
                .clipShape(.rect(cornerRadius: TranceRadius.thumbnail))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete")
        .allowsHitTesting(isOpen)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Ignore drags that are mostly vertical — those belong to the
                // enclosing ScrollView.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    dragOffset = 0
                    return
                }
                let settled = offset
                withAnimation(.snappy(duration: 0.22)) {
                    dragOffset = 0
                    openRowID = settled < -Self.triggerDistance ? id : nil
                }
            }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.22)) {
            dragOffset = 0
            if isOpen { openRowID = nil }
        }
    }
}

extension View {
    /// Reveals a delete action when the row is swiped left.
    func swipeToDelete<ID: Hashable>(
        id: ID,
        openRowID: Binding<ID?>,
        isEnabled: Bool = true,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(
            SwipeToDeleteRow(id: id, openRowID: openRowID, isEnabled: isEnabled, onDelete: onDelete)
        )
    }
}
```

- [ ] **Step 2: Attach it to the rows**

In `Ilumionate/AudioLibraryView+Filtering.swift`, the `ForEach` body currently reads:

```swift
                        ForEach(filteredAudioFiles) { file in
                            // Every file gets a detail route — the detail screen
                            // renders a "not analyzed yet" state for unanalyzed files.
                            NavigationLink(value: file) {
                                audioFileRow(for: file)
                            }
                            .buttonStyle(.plain)
```

Replace those lines (keep the divider block that follows) with:

```swift
                        ForEach(filteredAudioFiles) { file in
                            // Every file gets a detail route — the detail screen
                            // renders a "not analyzed yet" state for unanalyzed files.
                            NavigationLink(value: file) {
                                audioFileRow(for: file)
                            }
                            .buttonStyle(.plain)
                            .swipeToDelete(
                                id: file.id,
                                openRowID: $openSwipeRowID,
                                isEnabled: !isSelectionMode
                            ) {
                                deleteFile(file)
                            }
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Tune the gesture on a real touch surface**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Check all four, in order:

1. Swiping left on a row reveals the red trash; tapping it deletes and shows the undo banner.
2. Scrolling the list vertically does **not** open any row.
3. Tapping a row still navigates to its detail screen.
4. Opening a second row closes the first.

**If (1) does not register or (3) breaks**, the wrapping `NavigationLink` is consuming the drag. Try in this order, re-checking all four each time:

- Swap `.simultaneousGesture(dragGesture, isEnabled: isEnabled)` for `.highPriorityGesture(dragGesture, isEnabled: isEnabled)`.
- If that kills navigation, drop the `NavigationLink` and drive navigation with an explicit path: add `@State var path = NavigationPath()` to `AudioLibraryView`, use `NavigationStack(path: $path)`, wrap the row in a plain `Button { path.append(file) }`, and keep `.navigationDestination(for: AudioFile.self)` as-is.
- If the gesture still fights the `ScrollView`, raise `DragGesture(minimumDistance:)` from 12 to 20.

Record which variant you landed on in the commit message — the next person will want to know.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/SwipeToDeleteRow.swift Ilumionate/AudioLibraryView+Filtering.swift
git commit -m "feat(library): swipe left on a library row to delete it"
```

---

## Task 7: Fix selection mode

Two problems: the row navigates instead of toggling, and there is no Select All.

**Files:**
- Modify: `Ilumionate/AudioLibraryView+Filtering.swift`
- Modify: `Ilumionate/AudioLibraryView+Actions.swift`
- Modify: `Ilumionate/AudioLibraryView.swift:165-178`

- [ ] **Step 1: Make the whole row toggle selection**

In `Ilumionate/AudioLibraryView+Filtering.swift`, replace the `NavigationLink` block from Task 6 with a branch on selection mode:

```swift
                        ForEach(filteredAudioFiles) { file in
                            if isSelectionMode {
                                // The whole row is the target. Wrapping it in a
                                // NavigationLink here sent taps to the detail
                                // screen instead, leaving only the 52pt
                                // thumbnail able to toggle selection.
                                Button {
                                    toggleSelection(for: file)
                                } label: {
                                    audioFileRow(for: file)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // Every file gets a detail route — the detail screen
                                // renders a "not analyzed yet" state for unanalyzed files.
                                NavigationLink(value: file) {
                                    audioFileRow(for: file)
                                }
                                .buttonStyle(.plain)
                                .swipeToDelete(
                                    id: file.id,
                                    openRowID: $openSwipeRowID
                                ) {
                                    deleteFile(file)
                                }
                            }
```

The `isEnabled:` argument is gone because the swipe branch is now unreachable in selection mode.

- [ ] **Step 2: Add the Select All action**

Add to `Ilumionate/AudioLibraryView+Actions.swift`, in the `// MARK: - Selection Management` section after `toggleSelection`:

```swift
    /// True when every *visible* file is selected. Scoped to the filtered set —
    /// "Select All" must never reach files the current filter is hiding.
    var allVisibleSelected: Bool {
        !filteredAudioFiles.isEmpty && filteredAudioFiles.allSatisfy { selectedFiles.contains($0.id) }
    }

    func toggleSelectAll() {
        TranceHaptics.shared.light()
        if allVisibleSelected {
            for file in filteredAudioFiles {
                selectedFiles.remove(file.id)
            }
        } else {
            for file in filteredAudioFiles {
                selectedFiles.insert(file.id)
            }
        }
    }
```

- [ ] **Step 3: Add the toolbar button**

In `Ilumionate/AudioLibraryView.swift`, replace this toolbar item:

```swift
                ToolbarItem(placement: .cancellationAction) {
                    if !audioFiles.isEmpty {
                        Button(isSelectionMode ? "Done" : "Select") {
                            TranceHaptics.shared.light()
                            if isSelectionMode {
                                selectedFiles.removeAll()
                            }
                            isSelectionMode.toggle()
                        }
                        .font(TranceTypography.body)
                        .foregroundStyle(.roseGold)
                    }
                }
```

with:

```swift
                ToolbarItem(placement: .cancellationAction) {
                    if !audioFiles.isEmpty {
                        HStack(spacing: TranceSpacing.list) {
                            Button(isSelectionMode ? "Done" : "Select") {
                                TranceHaptics.shared.light()
                                if isSelectionMode {
                                    selectedFiles.removeAll()
                                }
                                isSelectionMode.toggle()
                            }

                            if isSelectionMode {
                                Button(allVisibleSelected ? "Deselect All" : "Select All") {
                                    toggleSelectAll()
                                }
                            }
                        }
                        .font(TranceTypography.body)
                        .foregroundStyle(.roseGold)
                    }
                }
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Verify by hand**

In the simulator: tap Select, then tap a row **on its title** — it must toggle the checkmark, not navigate. Tap Select All, confirm the count matches the visible rows, tap the trash, and confirm one Undo restores the whole batch. Apply a filter first and re-check that Select All only takes the filtered rows.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/AudioLibraryView.swift Ilumionate/AudioLibraryView+Actions.swift Ilumionate/AudioLibraryView+Filtering.swift
git commit -m "feat(library): tap anywhere to select, add Select All"
```

---

## Task 8: Surface Delete in the context menu

**Files:**
- Modify: `Ilumionate/AudioFileRow.swift:181-237`

- [ ] **Step 1: Move Delete to the top**

In `Ilumionate/AudioFileRow.swift`, the `rowMenu` builder starts with the Play button and ends with a `Divider()` then the Delete button. Move Delete to the front: replace the opening of `rowMenu`

```swift
    @ViewBuilder
    private var rowMenu: some View {
        Button {
            onPlay()
        } label: {
            Label("Play", systemImage: "play.fill")
        }
```

with:

```swift
    @ViewBuilder
    private var rowMenu: some View {
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }

        Divider()

        Button {
            onPlay()
        } label: {
            Label("Play", systemImage: "play.fill")
        }
```

and delete the trailing occurrence at the end of the builder:

```swift
        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
```

Also update the comment above `rowMenu` — it explains why swipe actions were rejected, which is no longer true:

```swift
    /// All per-file actions live here. Long-press (or tap-and-hold) reveals them.
    /// A context menu works inside the LazyVStack list, unlike `.swipeActions`
    /// which only functions inside a `List`.
```

becomes:

```swift
    /// All per-file actions live here. Long-press (or tap-and-hold) reveals them.
    /// Delete leads because it is the action people hunt for; it is also on a
    /// left swipe (see `SwipeToDeleteRow`), which this menu backs up on pointer
    /// platforms where swiping is awkward.
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/AudioFileRow.swift
git commit -m "feat(library): lead the row context menu with Delete"
```

---

## Task 9: Full verification

- [ ] **Step 1: Run the whole suite on macOS**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

Expected: all tests pass, including the 11 new `PendingAudioDeletionTests`.

- [ ] **Step 2: Run the whole suite on iOS Simulator**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

Expected: same result.

- [ ] **Step 3: Keep Mac Catalyst compiling**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Manual pass on the iOS Simulator**

Work through every row. Each one is a behavior the unit tests cannot reach.

| # | Check | Expected |
|---|---|---|
| 1 | Swipe a row left | Red trash appears; the row does not show through it |
| 2 | Scroll the list vertically, fast | No row opens |
| 3 | Tap a row | Navigates to detail |
| 4 | Open one row, then swipe another | The first closes |
| 5 | Swipe → trash | Row goes, banner appears |
| 6 | Tap Undo | Row returns **to its original position** |
| 7 | Delete, wait 6s | Banner goes; row does not come back after leaving and re-entering the tab |
| 8 | Delete, then leave the tab immediately | Delete is final; no banner on return |
| 8b | Delete, then push a detail screen and come back within 6s | Undo is still available — pushing a screen must not commit |
| 9 | Delete a file that has a generated session, then Undo | The lightbulb badge is still on the restored row |
| 10 | Delete the same file, let it commit, restart | The file is gone and stays gone |
| 11 | Select → tap a row title | Toggles selection, does not navigate |
| 12 | Select All → trash | All go; one Undo brings all back in order |
| 13 | Filter, then Select All | Only the visible rows get selected |
| 14 | Delete the last remaining file | Empty state appears **with the banner still visible and Undo working** |
| 15 | Delete, then force-quit before the timer | On relaunch the file is gone and staging is empty |
| 16 | Long-press a row | Delete is the first menu item |

Rows 7, 9, 10, 14 and 15 are the ones most likely to fail quietly — check them deliberately.

- [ ] **Step 5: Update the plan checklist and commit**

```bash
git add docs/superpowers/plans/2026-08-09-library-delete.md
git commit -m "docs: mark library delete plan complete"
```

---

## Definition of done

- Deleting one file takes a single left swipe plus a tap on the trash.
- Every delete is undoable for 6 seconds, restoring position as well as presence.
- Deleting in bulk takes Select → Select All → trash, with one Undo for the batch.
- Nothing deleted ever reappears in the library on its own.
- A generated light session survives an undo and dies with a commit.
- `IlumionateTests` passes on macOS and iOS Simulator; Mac Catalyst still builds.
