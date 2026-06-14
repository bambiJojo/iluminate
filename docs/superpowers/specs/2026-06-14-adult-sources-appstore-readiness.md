# App Store Submission Readiness — Adult Reading Sources

**Date:** 2026-06-14
**Scope:** Shipping the eight curated adult (erotic-hypnosis) reading-source directories added in `feature/phase-eval-harness`.
**Verdict:** **NOT submission-ready as-is.** One genuine app-wide blocker (privacy manifest) plus a high-risk Guideline 1.1.4 / age-rating exposure specific to the adult sources. Greenlight produced 4 "CRITICAL" findings; 1 is real, 1 is a false positive, and the dominant compliance risk (objectionable content) is not something greenlight checks.

---

## 1. The core risk: Guideline 1.1.4 + age rating

This is the issue that motivated the review and the one greenlight cannot see.

### What the feature does
The catalog now curates eight directories whose content is explicitly erotic/pornographic
(MC Stories, Literotica – Mind Control, HypnoTube Stories, Warp My Mind, HypnoHub,
Spirals Nightclub, Nimja, r/hypnautimagery). They open inside the app via
`SFSafariViewController`. The app *curates and labels* these as a feature; it does not host the content.

### How Apple treats this
- **Guideline 1.1.4 — "Overtly sexual or pornographic material … is not allowed."**
  Apps are routinely rejected when a *prominent, curated feature* exists primarily to surface
  pornography. General-purpose apps with incidental adult web content (Reddit, X, web browsers)
  survive because adult content is not their purpose and is not curated by the developer.
  Here the adult directories are a deliberate, first-party-curated list — that reads to a
  reviewer as "the app facilitates access to pornography," which is the exact 1.1.4 trigger.
  **Risk level: HIGH** if these ship in the public binary.
- **Unrestricted web access → top age tier.** Embedding a full web browser
  (`SFSafariViewController` to arbitrary user-reachable sites) is "unrestricted web access" in
  the Age Rating questionnaire and forces the highest age band (17+ on the legacy scale; 18+
  on Apple's 2025 13/16/18 scale) regardless of the curated content.
- **Age rating is necessary but not sufficient.** A correct 17+/18+ rating does **not** exempt
  an app from 1.1.4. Rating high does not make curated porn allowed.

### Options (pick one before any public submission)

| Option | What it is | 1.1.4 risk | Effort |
|--------|-----------|-----------|--------|
| **A. Exclude adult sources from the App Store build** *(recommended)* | Gate the eight curated adult entries behind a compile-time flag / build configuration so they ship only in personal / sideload / internal-TestFlight builds, not the public binary. The link-only directory + user "＋ Add source" remain. | Low | Small (code) |
| **B. Drop curation; keep user-added only** | Remove the eight curated adult entries entirely; users can still add their own via the existing custom-source flow. The app no longer curates porn. Still needs 17+/18+ for the in-app browser. | Medium | Small (delete data) |
| **C. Ship as-is at 17+/18+ and defend** | Submit with the highest age rating + the existing one-time gate, argue link-only/no-hosting/gated. | High — likely rejection | None, but rework on rejection |

Recommendation: **A**. It keeps the feature fully working for personal use (your stated
primary context) and removes the public-binary 1.1.4 exposure cleanly. A simple
`#if ALLOW_ADULT_SOURCES` (off in the Release/App Store config) around the eight curated
entries does it; the gate, badge, and in-app browser all stay.

---

## 2. Genuine technical blocker: privacy manifest (independent of adult content)

**[CRITICAL] No `PrivacyInfo.xcprivacy` in the project.** Required since May 2024; absence
triggers `ITMS-91061` at upload. This is app-wide, not specific to the adult sources, but it
will block *any* submission.

Required-Reason APIs detected in the app that must be declared:
- **`NSPrivacyAccessedAPICategoryUserDefaults`** — the app uses `UserDefaults`/`@AppStorage`
  broadly, and the new adult gate adds `@AppStorage("readingSourceAdultConfirmed")`.
  Declare with reason **`CA92.1`** (access only to data written by the app itself, in-process).
- **`NSPrivacyAccessedAPICategoryFileTimestamp`** — used in corpus/training code. Declare with
  the applicable reason (commonly **`C617.1`** — timestamps for files inside the app container —
  or **`DDA9.1`**; pick per actual use).

No tracking SDK is present (see §3), so `NSPrivacyTracking` should be `false` and
`NSPrivacyTrackingDomains` empty.

---

## 3. Greenlight false positives (do not act on these)

- **Amplitude / ATT (3 findings: 1 CRITICAL + 1 WARN).** False positive. The scanner matched
  the word *"amplitude"* in audio DSP code (`EngineWaveforms.swift`, `AudioEnergyAnalyzer.swift`,
  `BinauralBeatsEngine.swift`, `FlashController.swift`, `SessionGenerator+Strategies.swift`),
  not the Amplitude analytics SDK. No tracking SDK is integrated. No ATT prompt needed.
- **Insecure HTTP URL — `ReadingSource.swift` spirals entry (WARN).** Spirals is HTTP-only
  (HTTPS handshake fails; HTTP returns 200). It loads via `SFSafariViewController`, which runs
  out-of-process and is **not** subject to the app's App Transport Security, so it works with no
  ATS exception and is not a functional defect. Leave as-is (or drop the source under Option B).
  Do **not** add an `NSAllowsArbitraryLoads` ATS exception for it — that would weaken the whole
  app for no benefit.
- **IAP "Restore Purchases", placeholder content, competing-platform reference,
  missing `CFBundleDisplayName` (4 WARNs).** All located under `.worktrees/liminal-ui/` or
  `Tools/CorpusGenerator/.build/` (a separate worktree and build artifacts), not the shipping
  app target. Re-run the scan scoped to the app to confirm. The greenlight run also
  misidentified the bundle as `com.apple.xcode.dsym.corpus-gen` (a dSYM), confirming it swept
  build artifacts.

> Tip: re-run against just the app sources to cut the noise, e.g. point greenlight at the
> `Ilumionate/` app directory or add `.worktrees` and `**/.build` to its ignore set.

---

## 4. Pre-submission checklist

Blocking (must do before *any* App Store upload):
- [ ] Add `PrivacyInfo.xcprivacy` to the **Ilumionate** app target with `UserDefaults` (CA92.1)
      and `FileTimestamp` (appropriate reason) declared; `NSPrivacyTracking = false`.
- [ ] Decide adult-sources disposition: **Option A** (compile-flag out of Release) recommended.

Required if any adult/web access ships:
- [ ] Set Age Rating to the top tier (17+ legacy / 18+ new) and answer "Unrestricted Web
      Access = Yes" in the questionnaire.
- [ ] Keep the one-time adult confirmation gate (it's a mitigation, not a guarantee).

Hygiene (not blocking, but verify):
- [ ] Re-run greenlight scoped to the app target to clear the `.worktrees`/`.build` noise.
- [ ] Confirm there is a Privacy Policy URL in App Store Connect (required for 17+/web-access apps).
- [ ] If the app has real IAP (StoreKit appears in `ProfileSettingsView+Sections.swift`),
      ensure a "Restore Purchases" affordance exists — out of scope for this feature, but on the list.

---

## 5. Bottom line

For **personal / sideload use** (your stated context) nothing here blocks you — the feature is
done and works. For a **public App Store release**, the curated adult directories are the
dominant rejection risk (Guideline 1.1.4); gate them out of the Release build (Option A), and
separately add the privacy manifest that the app needs regardless. The remaining greenlight
"criticals" are a false positive (Amplitude) and build-artifact noise.
