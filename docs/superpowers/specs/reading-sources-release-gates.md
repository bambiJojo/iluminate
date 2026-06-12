# Reading Sources — Release Gates

**Status:** Groundwork merged (link-only directory + Library/Read entry points). NOT release-ready until the gates below are cleared.
**Source:** distilled from `docs/superpowers/handoffs/2026-06-11-reading-sources-handoff.md`.
**Scope reminder:** v1 ships as a **curated external-links directory plus private user bookmarks**. It must never fetch, scrape, parse, cache, summarize, transform, or store third-party webpage content. Importing external text is a separate, design-gated milestone (Text Trance M4).

## What shipped (M1 groundwork)

- `ReadingSource` metadata model + `ReadingSourceCatalog.curatedSources` (6 curated public-domain/library/script sources; none `adultOnly`).
- `@MainActor @Observable ReadingSourceStore` — curated + user-added aggregation, `UserDefaults` persistence (key `readingSourceCustomLinks`), HTTP/HTTPS-only URL validation (rejects `javascript:`/`data:`/`file:`/`ftp:`), duplicate rejection, deletion.
- `ReadingSourceDirectoryView` — searchable directory, category chips, source cards, **opens links via external browser only** (`openURL`), add-source sheet.
- Entry points: Library tab row + Read tab "Find more scripts online" card.

## Release gates (clear before shipping to users)

### 1. Product scope lock
- [ ] Reviewer can describe the feature as "a curated external links directory plus user bookmarks" with no caveats.
- [ ] No background page fetches; no parse/cache/summarize/transform/store of website text.

### 2. Curated source review
- [ ] Every curated URL resolves and is audience-appropriate.
- [ ] `licenseNote` / `contentNote` / `importPolicy` accurate for each source; each has a documented, owner-approved decision.
- [ ] Hypnosis-script directories remain `linkOnly` unless reuse/import permission is confirmed in writing.
- [ ] No `adultOnly` source in the default catalog (enforced by `curatedSourcesHaveStableSafeShape` test).

### 3. App Store compliance preflight
- [ ] Reviewed against Apple rules: user-generated/external content, objectionable content, medical/health claims, adult content.
- [ ] Confirm external Safari (not in-app web view) is the chosen open behavior.
- [ ] No hypnosis content presented as medical treatment; disclaimer added if needed ("external third-party resources; terms/content vary").
- [ ] Passes compliance review before TestFlight.

### 4. UX polish
- [ ] Row count/placement (Library + Read); search no-match empty state; chip spacing on small devices; card density for license/content notes.
- [ ] Add-source sheet copy + validation feedback; delete affordance (consider swipe-to-delete vs context menu).
- [ ] Footer/disclaimer noting links open external sites.

### 5. Accessibility
- [ ] VoiceOver reads source title, category, host, open action; chips announce selected state; add-source fields labelled.
- [ ] Color not the only signal for policy/category; tap targets meet iOS sizes; no clipped critical license/content text at larger Dynamic Type.

### 6. Test coverage additions
- [ ] Category filtering; search helper (if extracted); custom-source newest-first ordering; load ignores accidentally-persisted curated records; URL normalization edge cases (uppercase scheme/host, trailing-slash on deep paths, query-string preservation, host-only input); deleting unknown ID is harmless.
- [ ] Smoke path manually verified in Simulator.

### 7. Data & migration
- [ ] Storage key `readingSourceCustomLinks` documented/stable; only title/URL/notes stored (no sensitive data); migration path noted if moving to SwiftData.

### 8. Analytics & privacy
- [ ] If analytics added: no full custom URLs logged by default (they can reveal sensitive interests); privacy-reviewed.

### 9. Error handling
- [ ] Add-source failure paths show visible feedback, never crash; Save disabled state matches validation; pasted URLs with whitespace handled.

### 10. Future import (M4 — design-gated)
- [ ] Import stays disabled until a separate approved spec exists covering: import-eligible source types, import mechanism (page text / download / paste / document picker), source-URL/attribution recording, unclear-rights handling, local-only private storage, edit/delete/export/sync, and anti-scraping/redistribution safeguards.

## Suggested skills for this work
`swiftui-ui-patterns` (UX polish), `swift-testing-pro` (coverage), `app-store-aso` / App Store compliance review (before any broader external-content discovery ships).
