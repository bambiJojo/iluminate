# Spec Audit — 2026-06-19

One-time audit of the codebase against the design specs, per request: check each item/feature
for **completeness, functionality, and design aesthetic**, note what needs work, auto-fix
CRITICAL+HIGH, verify.

**Sources audited:** `app_design_spec.md` (Trance visual spec), `docs/superpowers/specs/*` (11 feature
specs), `features.json` (product inventory), `plan.md` (status tracker).

**Method:** 5 parallel read-only agents (design tokens/components, screens/animations/nav,
accessibility, feature-spec functionality, features.json/plan.md reconciliation).

---

## ⚠️ Key finding: the master visual spec is stale

The codebase deliberately replaced `app_design_spec.md`'s **"Pink Light Mode"** palette and
**5-tab navigation** (Home/Library/Machine/Store/Profile) with the newer **Liminal dark theme**
(void/aurora) and **4-tab** (Home/Library/Read/Create) IA. This is intentional and documented
(`2026-06-13-liminal-ui-overhaul-design.md`, in-code comments "Liminal void — dark only",
`.preferredColorScheme(.dark)`). The Liminal overhaul spec supersedes `app_design_spec.md` for
palette, navigation, and home composition.

**Consequence:** several findings the audit rated CRITICAL/HIGH are *spec drift*, not defects.
The correct remedy is to update the stale doc, **not** revert the code. These are tagged
`STALE-SPEC` below and excluded from code auto-fix.

---

## Triage

### A. Auto-fix now (real, bounded, safe — safety / compliance / a11y)

| # | Item | Severity | Evidence | Fix |
|---|------|----------|----------|-----|
| 1 | `PrivacyInfo.xcprivacy` has empty `NSPrivacyAccessedAPITypes` | CRITICAL | `Ilumionate/PrivacyInfo.xcprivacy:24-25` (found by 2 agents) | Declare `UserDefaults` (CA92.1) + `FileTimestamp` reasons. App Store upload blocker `ITMS-91061`. |
| 2 | Flash path has no `isReduceMotionEnabled` guard | CRITICAL (photosensitivity) | `FlashController.swift:68-87`, `PlayerBackgrounds.swift:40-59` | Render static color instead of flashing when Reduce Motion is on. |
| 3 | No hard frequency cap at engine level | CRITICAL (seizure safety) | `EngineLightEngine.swift`, `SessionGenerator.swift:31` (maxFrequency=40) | Clamp engine flash frequency to the documented safety max; ensure user controls can't exceed it. |
| 4 | Icon-only buttons lack `.accessibilityLabel` | HIGH | `CategoryIcon.swift:18-46`, `TranceTabBar.swift:63-91` (~7/107 labeled) | Add VoiceOver labels to icon/emoji-only buttons. |
| 5 | Most animations ignore Reduce Motion | HIGH | `MandalaVisualizer.swift`, `CategoryIcon.swift:41-46`, `TranceTabBar.swift:64-72` | Add reduce-motion guards to key animated components; `.accessibilityHidden(true)` on decorative motion. |
| 6 | Analyzer-training labeling UI unreachable | HIGH | `Training/CorpusManagerView.swift`, `PhaseLabelingView.swift` (no call-site) | Wire behind a debug entry in `ProfileSettingsView+Sections.swift`. |

### B. Doc reconciliation (stale spec / false status — fix the docs, not the code)

| Item | Severity | Evidence | Action |
|------|----------|----------|--------|
| Pink Light Mode palette inverted to Liminal dark | CRITICAL `STALE-SPEC` | `TranceDesignSystem.swift:28-67` | Mark `app_design_spec.md §1.1` superseded by Liminal overhaul. |
| 5-tab nav vs actual 4-tab Read/Create | CRITICAL `STALE-SPEC` | `TranceTabBar.swift:13-36` | Mark `app_design_spec.md §2.3/§5` superseded. |
| Home dashboard "Portal" vs spec's category grid | HIGH `STALE-SPEC` | `HomeView.swift:104-285` | Mark `app_design_spec.md §3.1` superseded. |
| plan.md false-❌: audio playback IS wired | CRITICAL (false claim) | `UnifiedPlayerViewModel.swift:422,478` | Update plan.md → done. |
| plan.md false-❌: GeneratedSession persistence DONE | CRITICAL (false claim) | `GeneratedSessionStore.swift` | Update plan.md → done. |
| plan.md false-✅: AudioRecorderView missing | CRITICAL (false claim) | not found | Correct plan.md → not done. |
| plan.md tab claim (Machine/Store/Profile) | MEDIUM | `TranceTabBar.swift:14` | Correct plan.md to actual IA. |

### C. Flag only — net-new features or product decisions (NOT auto-fixed)

Building these is feature work, not a "fix"; or they need your decision.

- **LightScorePlayer external time-sync** (CRITICAL, `plan.md` NEXT PRIORITY #1) — no `.external`
  time source; light follows audio via polling. Net-new architecture. **This is the top real build item.**
- **Audio Analyzer screen (`AudioAnalyzerView`)** is orphaned + shows mocked/random data
  (`AudioAnalyzerView.swift:104-200`, never instantiated). Decide: delete dead view, or wire it to real analysis.
- **`#if ALLOW_ADULT_SOURCES` build gate** (HIGH, App Store) — 8 adult sources ship unconditionally
  (`ReadingSource.swift:182-293`). Needs xcconfig + pbxproj change (build-config risk) — deferred to your call.
- **Generate Session flow / preview playback** (HIGH) — tapping a file opens `.audioLight` directly,
  never routes through `SessionGenerationView`; no short preview.
- **features.json unbuilt wishes** — `ai_auto_organization`, dark-room `ambient_light_detection` /
  `adaptive_brightness`, frequency-spectrum/FFT analysis. (features.json is the wishlist; not editing it.)
- **Analytics default-ON vs `tracking_enabled: false`** — `UsageAnalytics` is opt-out default-on
  (intentional 2026-06-18 decision) but `features.json` says tracking off. Privacy-sensitive — your call.
- **Dynamic Type** (HIGH) — 148 hardcoded `.font(.system(size:))`; full migration risks the tuned
  layout. Recommend a scoped pass via `TranceTypography`, not a blanket auto-refactor.

### D. Minor (MEDIUM/LOW — reported, not fixed)

- Analytics `screen(.home/.library/.create/.audioLibrary)` not wired at root views.
- `LiminalSurface` implemented but zero call-sites (Liminal Phase 1 migration incomplete).
- `UnifiedPlayerView.swift:116` `useDarkChrome` allows `.light` — contradicts dark-only mandate.
- `IntensityDial` visual divergence (size/gradient) from `app_design_spec §2.10`.
- `textGhost` contrast marginal (~4.1:1) on void background.
- Duplicate session JSON files (e.g. `deep_relaxation_session 2.json`).

---

## Status

- Phase 1 inventory: ✅
- Phase 2 audit: ✅ (this report)
- Phase 3 auto-fix A: ✅ — all 6 items landed
  - 1 PrivacyInfo: `UserDefaults` (CA92.1) + `FileTimestamp` (C617.1) declared; `plutil -lint` OK.
  - 2 Flash reduce-motion guard: `FlashController.swift:130`, `EngineLightEngine.swift:396`, `PlayerBackgrounds.swift:44` — steady color when Reduce Motion on, re-checked per frame.
  - 3 Frequency cap: new `LightSafety.swift` (single source of truth, 40 Hz); clamps at `FlashController:138`, `EngineLightEngine:158/164/407` — covers slider, ramp, session-JSON paths.
  - 4 VoiceOver labels: `CategoryIcon`, `TranceTabBar`, `PlayerTransportSection` play/pause.
  - 5 Reduce-motion animation guards: `MandalaVisualizer`, `TranceTabBar`; decorative motion `.accessibilityHidden`.
  - 6 Analyzer-training UI: wired behind a DEBUG-only row in `ProfileSettingsView+Sections.swift`.
- Phase 4 doc reconciliation B: ✅ — stale-banner on `app_design_spec.md`; audit note in `plan.md` (statuses left unchanged per project "done" rule).
- Phase 5 verify: build ✅ `BUILD SUCCEEDED`; safety integration points re-verified by hand; test suite run — see final report.

Note: the consolidated fixes also resolved a pre-existing build break at `TranceTabBar.swift:77`
(a `Bool` vs `TranceTab` ternary) that was failing the branch before this audit.
