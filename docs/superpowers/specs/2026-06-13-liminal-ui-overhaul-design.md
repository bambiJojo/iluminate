# Liminal UI Overhaul — Design Spec

**Date:** 2026-06-13
**Status:** Approved (brainstorm with Byron, visual companion session)
**Scope:** Full UI overhaul of LumeSync (Ilumionate) — identity, design system, all screens, phased.

---

## 1. Goal & Identity

LumeSync becomes **Liminal**: the app as a portal to altered states. The UI begins the
entrainment before the session does — void backgrounds, slow breathing motion, aurora light.
Target qualities: **polished, immersive, a little addicting** — where the addiction comes
from *sensory delight* (craft, motion, glow, haptics), explicitly **not** from gamification
(no streaks, no stats dashboards, no reminders).

Decisions made during brainstorming:

| Decision | Choice |
|---|---|
| Identity direction | **Liminal** — cosmic void, breathing aurora, light as protagonist (chosen over Velvet Trance, Neuro, Drift) |
| The "pull" | **Sensory delight only** — fidget-toy interface quality; no streaks/stats/evolving-world mechanics |
| Color modes | **Dark-only.** Appearance setting removed; `preferredColorScheme(.dark)` enforced |
| Scope | **Everything, phased** — 3 phases, each independently shippable |
| Home philosophy | **The Portal** — one dominant breathing orb as primary CTA (chosen over browsable "Night Sky") |
| Player philosophy | **Pure Void** — full-screen light field, whisper UI that auto-fades, swipe-up drawer |
| Execution approach | **Token swap first, then restructure** — whole app lands in the new palette on day one |

---

## 2. Design Language

### 2.1 Palette

Replaces Trance tokens. Phase 1 keeps old semantic names as aliases; later phases rename.

| Token | Value | Role |
|---|---|---|
| `voidDeep` | `#03040C` | Outer void — screen edges, player base |
| `voidPrimary` | `#070D1F` | Primary background |
| `voidElevated` | `#0D1428` | Cards, sheets, decks |
| `auroraTeal` | `#7EE8D8` | Primary accent — actions, "Begin", active states |
| `auroraBlue` | `#7C9EFF` | Secondary accent — info, links, focus rings |
| `auroraViolet` | `#B07DC8` | Theta/trance contexts |
| `auroraPink` | `#E87CB8` | Warm highlight (echo of the rose identity) |
| `textBright` | `#E6EEFF` | Primary text |
| `textDim` | `#8FA3CC` | Secondary text |
| `textGhost` | `#5A6A8A` | Tertiary, micro-labels |
| `glassBorder` | `auroraBlue @ 18%` | Hairline borders on glass |

- Brainwave-zone colors (δ θ α β γ) and hypnosis-phase colors keep distinct hues,
  re-tuned to sit on the void (slightly desaturated, glow-capable).
- Flash-mode colors (`flashOn`/`flashOff`) are part of the light-therapy output path and
  are **not** changed by this overhaul.

### 2.2 Typography

- SF Pro. **Ultralight/light at display sizes** (greetings, session titles);
  regular/semibold only at small sizes (labels, data).
- **SF Mono** for frequency/data readouts (`6.0 HZ · θ`) — the one place the
  instrument shows through.
- Wide tracking on uppercase micro-labels.
- Dynamic Type respected throughout; `minimumScaleFactor` only on the orb label.

### 2.3 Motion — three tempos

| Tempo | Duration | Use |
|---|---|---|
| **Breath** | ~5 s loop | Ambient: orb breathing, aurora drift. Never stops, never demands attention |
| **Drift** | 0.6–0.8 s | Transitions: screen crossfade + slight scale, sheets rise on soft springs |
| **Touch** | 0.15–0.3 s | Feedback: glow blooms under fingers, press = scale 0.96 + glow |

All Breath-tempo motion freezes to static gradients under `accessibilityReduceMotion`.

### 2.4 Haptics & sound

- Keep `TranceHaptics` manager, retune: soft ticks on tab switch; medium thump on "Begin"
  synced with the orb bloom; optional (settings-gated) haptic pulses at hypnosis-phase
  transitions during sessions.
- No UI sounds — audio belongs to the session.

---

## 3. Component System

New `Ilumionate/DesignSystem/` group; one file per component.

| Component | Replaces | Description |
|---|---|---|
| `AuroraBackground` | per-screen backgrounds | TimelineView-driven void radial gradient + 2–3 large blurred aurora blobs drifting at Breath tempo. Parameterized by *mood* (zone hue tint). Used on every screen |
| `LumeOrb` | — (new centerpiece) | Conic aurora ring (24 s rotation), inner void disc, breathing outer glow. Sizes: hero (Home), medium (empty states/onboarding), mini (mini-player, loading). Accepts a `pulse` frequency. Tap = bloom + haptic |
| `LiminalSurface` | `GlassCard`/`GlassBackground` | ultraThinMaterial over `voidElevated`, hairline border, **glow shadow instead of drop shadow** (shadows are light, not darkness). Radius 16–20 pt |
| `GlowButton` | `CTAButton`/`TranceButtonStyle` | Aurora gradient primary, glass secondary; press = scale + glow bloom, never opacity dim |
| `StateChip` | category icons | Sleep/Focus/Relax/Trance pills; tinted glass, selection animates inner glow |
| `TranceTabBar` (restyle) | itself | Same floating capsule + matchedGeometry architecture. Void glass, active tab `auroraTeal` with glow dot, inactive `textGhost`; bounce effects stay |
| `PhaseTimeline` | phase pill | Slim glowing segmented strip (intro→induction→deepener→suggestion→awakening); current phase pulses. In player drawer + session detail |
| `VoidScrubber` | standard scrubber | Thin luminous progress line, glowing playhead |
| `MiniPlayerBar` (restyle) | itself | Mini LumeOrb artwork, glass capsule docking visually with tab bar |

Everything else (rows, sheets, settings groups) composes `LiminalSurface` + typography
tokens — no bespoke styling per screen.

---

## 4. Screens by Phase

### Phase 1 — Foundation + identity-defining surfaces

1. **Token swap.** Replace `TranceDesignSystem.swift` values with the Liminal palette;
   enforce dark-only; remove appearance picker from Settings; flip shadow styles from
   dark drop-shadows to glow shadows. Entire app wears the void immediately.
2. **Build the kit:** `AuroraBackground`, `LumeOrb`, `LiminalSurface`, `GlowButton`,
   with previews.
3. **Home → The Portal.** Time-aware greeting; hero LumeOrb as primary CTA. The orb is
   smart: offers resume-in-progress session, else best-fit session for time of day
   (reuses existing `BrainwaveCategory` frequency ranges; evening→sleep/trance,
   morning→energy/focus). StateChips filter the orb's offer and the shelf below. One slim
   "Tonight" shelf replaces the current featured/quick-start sections — browsing lives in
   Library.
4. **Player → Pure Void.** Builds on `UnifiedPlayerView`'s existing minimal-overlay
   pattern. Light field fills the screen (flash rendering unchanged). Whisper overlay:
   session name, `6.0 HZ · θ` readout, VoidScrubber. Auto-fades after ~4 s idle; tap
   recalls. Swipe up → glass drawer with PhaseTimeline, intensity dial, sync options,
   smart-transitions toggle, track list (everything in the current controls overlay —
   nothing lost). Exit: swipe-down or X in recalled overlay. Optional haptic pulse on
   phase transitions.
5. **Tab bar + MiniPlayer** restyled.

### Phase 2 — Main tabs

- **Library:** structure kept; reskin. Ghost-tracked micro-label headers, `LiminalSurface`
  rows with zone-tinted glow dots replacing thumbnail boxes, glass-capsule search.
  Session detail gets aurora treatment + PhaseTimeline preview.
- **Create (Mind Machine):** the instrument screen. Luminous frequency dial with SF Mono
  readout, waveform picker showing actual glowing waveform shapes, binaural section as
  glass deck. Live preview: mini light-field strip pulsing at chosen settings.
- **Read (TextTrance):** RSVP words in light type on `voidDeep`; sources/setup screens
  reskinned with the kit. Functionality untouched (restyle, not redesign).

### Phase 3 — Secondary surfaces

Settings, Audio Library, Analyzer/analysis overlays, profile sheet, streaming views —
all composition of the kit. **Onboarding** is the one real new design: rebuilt around the
LumeOrb introducing itself; short, atmospheric, 3 screens. Final step: migrate remaining
token call sites to Liminal names and delete `TranceDesignSystem.swift`.

---

## 5. Architecture & Constraints

- **File organization:** `Ilumionate/DesignSystem/` — `LiminalDesignSystem.swift`
  (tokens: colors, spacing, radius, glow, typography, motion durations) + one file per
  component. App-target files in the synchronized group; no project-file surgery.
- **Migration mechanics:** Phase 1 keeps old semantic names (`bgPrimary`, `roseGold`, …)
  as deprecated aliases pointing at new tokens so existing call sites compile untouched.
  Phases 2–3 migrate call sites; final phase deletes the Trance system.
- **Engine boundary (hard rule):** presentation only. `LightEngine`, `FlashController`,
  audio pipeline, analyzers, session models untouched. The engine's brightness output
  path stays byte-identical.
- **Performance guardrails:** ambient animation via scoped `TimelineView`/`.animation`
  on gradient layers — no CADisplayLink competition with the light engine. **Ambient
  aurora motion pauses during active flash sessions** (the light field owns the GPU).
  Max 2–3 blur layers per screen.
- **Branching:** phases land as separate PRs off `feature/liminal-ui`, each
  independently shippable.

---

## 6. Accessibility & Edge Cases

- `accessibilityReduceMotion` → Breath motion frozen to static gradients.
- `textDim` on `voidPrimary` verified against WCAG AA at body sizes.
- Glow-only state changes always paired with a shape/weight change (never color alone).
- Photosensitivity warning flow in the player is safety-critical and stays exactly as-is.
- Mini-player / analysis-overlay / tab-bar stacking keeps current clearance math
  (`tabBarClearance` carries over, renamed).
- Pure Void auto-hide timer suspends while the drawer is open and whenever VoiceOver is
  running (controls never hide under VoiceOver).

---

## 7. Testing & Verification

- Existing unit/integration tests stay green (engine untouched ⇒ they should).
- New tests:
  - Token/contrast sanity tests.
  - View-model tests for smart-orb session selection (time-of-day → category mapping).
  - Auto-hide overlay timer state tests (timer extracted into a small observable model).
- UI verification per phase: Xcode previews + simulator build (iPhone 17 destination).
- Instruments profiling only if visible hitching appears.

---

## 8. Out of Scope

- Any gamification (streaks, stats, reminders, evolving-world mechanics).
- Light mode / appearance switching.
- Engine, analysis, audio, or session-format changes.
- TextTrance functional changes (restyle only).
- App icon / App Store assets (worth doing later to match Liminal; separate effort).

---

## 9. Brainstorm Artifacts

Visual companion mockups (palette directions, Portal home, Pure Void player) saved under
`.superpowers/brainstorm/50006-1781310857/content/` (gitignored; for reference while the
session directory survives).
