# Reading Sources Handoff

Date: 2026-06-11

## Goal

Add groundwork for Text Trance/Text Reader to help users find externally hosted scripts and stories without bundling, scraping, caching, or redistributing third-party content.

The product direction from the chat:

- Users should be able to browse a curated list of websites that may contain scripts, stories, public-domain books, or other readable material.
- The app should provide links only for now.
- The app should not bundle third-party scripts or stories.
- Importing readable text can be a future explicit user action, but source rights and site terms must be respected.
- Adult-only story/script sources should not ship in the default curated list until there is a product policy and appropriate age/content gating.

## Implemented

### Reading Source Model

Added `Ilumionate/TextTrance/ReadingSource.swift`.

It defines:

- `ReadingSourceCategory`
- `ReadingSourceLicenseKind`
- `ReadingSourceImportPolicy`
- `ReadingSourceContentRating`
- `ReadingSource`
- `ReadingSourceCatalog.curatedSources`

The model is intentionally metadata-only. It stores titles, URLs, summaries, license notes, content notes, import policy, content rating, and curation state. It does not store page content.

Current curated sources:

- Project Gutenberg
- Standard Ebooks
- Wikisource
- Internet Archive Texts
- Open Library
- Free Hypnosis Scripts

The catalog marks sources as either `linkOnly`, `userInitiatedImport`, or `catalogPlanned` so future work can distinguish simple external links from sources that may support a controlled import/catalog experience.

### Persistent Custom Sources

Added `Ilumionate/TextTrance/ReadingSourceStore.swift`.

It provides:

- Shared observable store: `ReadingSourceStore.shared`
- Curated plus user-added source aggregation
- `UserDefaults` persistence for custom links
- URL normalization with default `https://`
- HTTP/HTTPS-only validation
- Duplicate URL rejection across curated and custom sources
- Custom source deletion

User-added links are always saved as `linkOnly` with `licenseKind == .userProvided`.

### Reading Sources UI

Added `Ilumionate/TextTrance/ReadingSourceDirectoryView.swift`.

The screen includes:

- Searchable source directory
- Horizontal category chips
- Grouped source sections
- Source cards using the app's existing `GlassCard`, `TranceSpacing`, `TranceTypography`, and color system
- Open buttons that use SwiftUI `openURL`
- Context menu actions for open/delete
- Add Source sheet for user-added links

The screen opens external websites only. It does not attempt to fetch or parse website text.

### Library Navigation

Updated `Ilumionate/LibraryView.swift`.

Changes:

- Added `LibraryDestination.readingSources`
- Added `@State private var readingSourceStore = ReadingSourceStore.shared`
- Added a “Reading Sources” row to the Library category list
- Displays the current source count
- Navigates to `ReadingSourceDirectoryView`

### Tests

Added `IlumionateTests/TextTrance/ReadingSourceStoreTests.swift`.

Coverage includes:

- Curated sources have stable/safe shape
- Curated sources use HTTP/HTTPS URLs
- Curated sources avoid `adultOnly` rating by default
- Custom source URL normalization and persistence
- Duplicate rejection against custom and curated URLs
- Empty/invalid/unsupported URLs
- Deleting custom sources does not affect curated sources

## Verification

Passed:

```sh
/usr/bin/xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,id=AF148AA1-2D77-4F50-826E-3EF46E37DC16' -derivedDataPath /tmp/IlumionateReadingSources CODE_SIGNING_ALLOWED=NO -only-testing:IlumionateTests/ReadingSourceStoreTests test
```

Also passed:

```sh
git diff --check
```

The first attempted simulator destination, `platform=iOS Simulator,name=iPhone 16`, failed because Xcode did not resolve it to an available simulator. The successful run used the available iPhone 17 simulator ID above.

## Existing Dirty Worktree Items

These were present before the feature work and were intentionally left untouched:

- `Ilumionate.xcodeproj/xcuserdata/byronquine.xcuserdatad/xcschemes/xcschememanagement.plist`
- `lightMapCreationTool`

Current feature files are new/untracked unless they have since been staged:

- `Ilumionate/TextTrance/ReadingSource.swift`
- `Ilumionate/TextTrance/ReadingSourceDirectoryView.swift`
- `Ilumionate/TextTrance/ReadingSourceStore.swift`
- `IlumionateTests/TextTrance/ReadingSourceStoreTests.swift`
- `docs/superpowers/handoffs/2026-06-11-reading-sources-handoff.md`

`Ilumionate/LibraryView.swift` is modified for navigation.

## Safety And Policy Notes

Keep the current implementation link-only unless there is a clear source-specific import policy.

Do not scrape or cache third-party content by default. A future importer should require explicit user action and should show a source/license reminder before importing.

For sites with unclear rights, keep `ReadingSourceImportPolicy.linkOnly`.

For public-domain or structured library sources, import may be possible later, but should still validate item-level rights. Project Gutenberg, Internet Archive, Wikisource, and Open Library all have item/source-specific caveats.

Adult-oriented sites such as MCStories were discussed as examples of large story databases users may know about, but they were not added to the curated catalog. Adding those needs a deliberate adult content policy, App Store review consideration, and UI gating.

## Suggested Next Steps

1. Run the app in Simulator and visually inspect the Library row and Reading Sources screen.
2. Decide whether the default catalog should include more link-only script directories.
3. Add a short in-app note or empty-state copy explaining that sources open externally and content rights vary.
4. Consider a source detail sheet before launching the browser if the current card text feels too dense.
5. Design a future “Import From Web” workflow separately:
   - explicit user action
   - source URL entry
   - terms reminder
   - readable text extraction only when allowed
   - no background scraping
   - local-only saved imported text unless the user exports it

## Production Readiness Plan

This feature is currently good groundwork, not release-ready. The work below should be completed before shipping it to users.

### 1. Product Scope Lock

Decide what version 1 is allowed to do:

- Ship as a link directory only.
- Do not fetch remote pages in the background.
- Do not parse, cache, summarize, transform, or save website text.
- Let users add custom source links, but treat them as private link bookmarks.
- Keep import-related metadata in the model for future work, but hide or simplify labels if they create user confusion.

Release gate:

- A reviewer can describe the shipped feature as “a curated external links directory plus user bookmarks” without caveats.

### 2. Curated Source Review

Audit every default source before release:

- Confirm each URL still resolves.
- Confirm the source is appropriate for the app's audience.
- Confirm the app only links to the source and does not imply endorsement.
- Confirm the `licenseNote`, `contentNote`, and `importPolicy` are accurate enough for a user-facing app.
- Remove any source with unclear, unstable, or risky terms.

Recommended default posture:

- Public-domain/library sources can stay if notes are accurate.
- Hypnosis script directories should remain `linkOnly` unless explicit reuse/import permission is confirmed.
- Adult-only sources should remain excluded until there is policy, gating, and App Store review strategy.

Release gate:

- Each curated source has a documented review decision and an owner-approved `importPolicy`.

### 3. Compliance And App Store Review

Run a preflight specifically for external content discovery:

- Check Apple App Store rules around user-generated/external content, objectionable content, medical/health claims, and adult content.
- Confirm whether opening these links in Safari is preferable to an in-app web view. Safari/external browser is likely safer for third-party content.
- Avoid presenting hypnosis scripts as medical treatment.
- Avoid linking directly to pages that primarily contain explicit adult content in the default catalog.
- Add a clear in-app disclaimer if needed: external sites are third-party resources and terms/content vary.

Release gate:

- The feature passes an App Store compliance review before TestFlight distribution.

### 4. UX Polish

The current UI is functional. Before release, inspect and refine:

- Library row count and placement.
- Search behavior with no matches.
- Category chip spacing on small devices.
- Card density, especially license/content notes.
- Add Source sheet copy and validation feedback.
- Delete affordance for custom sources. Context menu may be too hidden; consider swipe-to-delete if it fits the app.
- External open behavior: consider a confirmation or source detail view if users need context before leaving the app.

Suggested UI additions:

- Empty state for search results.
- Small footer explaining that links open external websites.
- Source detail sheet for license/content notes if cards feel crowded.
- Accessibility labels for category chips and source cards.

Release gate:

- Manual UI pass on small and large iPhone simulators with Dynamic Type at default and at least one larger size.

### 5. Accessibility

Verify the screen with standard accessibility checks:

- VoiceOver reads source title, category, website host, and open action clearly.
- Category chips announce selected state.
- The add-source form has clear field labels and error messages.
- Color is not the only signal for import policy/category.
- Tap targets meet expected iOS sizes.
- Text does not truncate essential license/content warnings.

Release gate:

- No critical VoiceOver navigation issues and no clipped critical text at larger Dynamic Type.

### 6. Test Coverage

Current store tests cover the core persistence/validation path. Add tests before release for:

- Filtering by category.
- Search behavior if search is extracted into a testable helper.
- Custom source ordering by newest first.
- Loading ignores any accidentally persisted curated records.
- URL normalization edge cases:
  - uppercase schemes/hosts
  - trailing slash equivalence
  - query strings preserved
  - invalid host-only input
- Deleting an unknown ID is harmless.

Consider UI tests for:

- Library shows Reading Sources row.
- Tapping row opens Reading Sources.
- Adding a custom source displays it in Custom.
- Duplicate source shows validation error.

Release gate:

- Focused unit tests pass plus at least one smoke path manually verified in Simulator.

### 7. Data And Migration

The current store uses `UserDefaults` for custom source links. That is acceptable for v1 bookmarks, but check:

- Storage key stability: `readingSourceCustomLinks`.
- No sensitive content is stored beyond user-entered titles, URLs, and notes.
- Future migration path if custom sources move into SwiftData or a richer library model.
- Reset/delete behavior if the user removes app data.

Release gate:

- Storage key is intentionally named and documented; no bundled external content is added to the app package.

### 8. Analytics And Privacy

If analytics exist in the app, decide whether to track:

- Opening the Reading Sources screen.
- Opening a source category.
- Adding/deleting a custom source.

Avoid tracking full custom URLs unless there is an explicit privacy decision. Custom source URLs can reveal sensitive interests.

Release gate:

- Analytics either omitted or privacy-reviewed. No full custom URLs are logged by default.

### 9. Error Handling

Current validation catches empty names, invalid URLs, unsupported schemes, and duplicates. Before release, confirm:

- Error messages are understandable in the UI.
- Save button disabled state matches validation.
- Pasted URLs with whitespace behave correctly.
- Network failure is left to Safari/external browser because the app does not prefetch.

Release gate:

- Add-source failure paths have visible user feedback and do not crash.

### 10. Future Import Design

Do not bolt import onto this link directory without a separate design pass. A production import workflow should specify:

- Which source types are import-eligible.
- Whether import is page text, file download, copy/paste, or document picker.
- How the app records source URL and attribution.
- What happens when source rights are unclear.
- Whether imported text is private local user content.
- Whether imported text can be edited, deleted, exported, or synced.
- How to prevent background scraping and accidental redistribution.

Release gate:

- Import remains disabled for v1, or a separate approved spec/test plan exists.

### 11. Final Release Checklist

Before merging/releasing:

- Run `git diff --check`.
- Run focused `ReadingSourceStoreTests`.
- Run a broader app build/test target if time permits.
- Manually inspect the new screen in Simulator.
- Review curated source list one final time.
- Confirm no external content files were added to the bundle.
- Confirm no unrelated dirty files were reverted or included unintentionally.

## Suggested Skills For Future Sessions

- `swiftui-ui-patterns` for UI polish and navigation work.
- `swift-testing-pro` if expanding store or importer tests.
- `app-store-preflight-compliance` before shipping any broader external-content discovery feature.
