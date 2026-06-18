# Usage Analytics — Design Spec

> Status: Approved design (2026-06-18). Scope: the **measurement system only**. The
> actual feature-cutting/streamlining is a deliberate follow-up once data is collected.

## Goal

Give the developer remote, anonymous visibility into **what features the ~100 TestFlight
testers actually use** — so unused/low-reach features can be cut and the kept features
streamlined. The new features about to ship should be measured from day one.

## Current state (what exists today)

- **`SessionHistoryManager`** ([Ilumionate/SessionHistoryManager.swift](../../../Ilumionate/SessionHistoryManager.swift))
  is the only existing usage tracking: a **local-only** session history (name, category,
  duration, completion %), recorded from a single call site
  ([UnifiedPlayerViewModel.swift:741](../../../Ilumionate/UnifiedPlayerViewModel.swift)),
  consumed by the Profile activity chart.
- It is **off by default** (`listeningHistoryEnabled` defaults `false`), **local-only**
  (never leaves the device), and **session-playback only**.
- No analytics SDK, no MetricKit, no remote backend anywhere in the project.
- "Tagging" that was remembered = **content tags** on audio files / reading scripts, not
  usage-event tagging.

**Conclusion:** the half-built feature is a local session-history feature, not feature-usage
analytics. This spec designs the analytics layer fresh, reusing `SessionHistoryManager`'s
`.shared` singleton + `UserDefaults` persistence pattern.

## Decisions (locked)

| Decision | Choice |
| --- | --- |
| Data delivery | Privacy-first analytics SDK (remote dashboard) |
| SDK | **TelemetryDeck** (anonymous, no IDFA, Swift Package, free tier covers 100 testers) |
| Consent | **On by default, opt-out toggle** in Settings + note in TestFlight "What to Test" |
| Depth | Reach + key actions + funnels |
| Code structure | **Typed facade** over TelemetryDeck (Approach A) |

## Architecture

```
View / ViewModel  →  UsageAnalytics.shared.<typed method>  →  TelemetryDeck.signal(...)
                          │
                          ├─ opt-out gate (analyticsEnabled, default true)
                          ├─ event catalog (one enum, no magic strings)
                          └─ privacy scrubber (only enums + bucketed numbers leave device)
```

- `UsageAnalytics` is `@MainActor @Observable final class`, `.shared` singleton — matches
  `SessionHistoryManager`.
- TelemetryDeck is called **only** inside the facade. Nothing else imports the SDK.
- Internal `emit` closure (defaults to a TelemetryDeck call) so tests inject a spy — no
  network, no real SDK in tests.
- Opt-out gate, event catalog, and privacy scrubber all live in one auditable place.

### Files

- `Ilumionate/Analytics/UsageAnalytics.swift` — facade, opt-out gate, init, `emit` seam.
- `Ilumionate/Analytics/AnalyticsEvent.swift` — typed event catalog + parameter enums +
  bucketing helpers.
- `Ilumionate/PrivacyInfo.xcprivacy` — updated tracking/collection declarations.
- `IlumionateApp` — one-time `TelemetryDeck.initialize(config:)` at startup.
- SPM: add TelemetryDeck package dependency.

### Configuration

- TelemetryDeck **App ID** read from `Info.plist`/`.xcconfig`, **not** hardcoded in source.
- Init runs once on app launch.

## Event taxonomy (~30 events)

### Screen reach (fired on `.onAppear`, one per surface)

Core surfaces:
`home, library, read, create, profile, audioLibrary, analysisQueue, sessionDetail,
player, onboarding`

Long-tail surfaces (**highest-value signal** — if these never fire across 100 testers,
that is the cut list):
`browseSessions, sessionLibrary, libraryCreators, libraryFolders, streamingBrowser,
phraseLibrary, lightScoreEditor`

### Key actions

| Event | Parameters |
| --- | --- |
| `session.started` | `source` = preset \| generated \| textTrance \| mindMachine; `category` |
| `session.completed` | `completionBucket` = under25 \| b25_50 \| b50_75 \| b75_95 \| complete |
| `audio.imported` | `source` = files \| url \| browser \| recording |
| `audio.analyzeStarted` | — |
| `audio.analyzeCompleted` | — |
| `session.generated` | — |
| `mindMachine.started` | `mode` = flash \| colorPulse \| bilateral |
| `textTrance.started` | — |
| `textTrance.completed` | — |
| `readingSource.imported` | — |
| `onboarding.step` | `index` = 0…5 |
| `onboarding.completed` | — |
| `settings.toggled` | `key` = the setting name (fixed set) |

### Funnels (read from the sequenced events above in the dashboard)

- **Audio → Session:** `audio.imported` → `audio.analyzeStarted` → `audio.analyzeCompleted`
  → `session.generated` → `session.started(source: generated)`
- **Onboarding:** `onboarding.step(index:)` → `onboarding.completed`
- **Text Trance:** `read` screen → `textTrance.started` → `textTrance.completed`

## Privacy guardrails (critical — health-adjacent content)

Enforced **by construction** so no free-form user content can ever leave the device:

- ❌ Never sent: file names, session/script titles, transcript text, URLs, search queries,
  any PII.
- ✅ Only sent: fixed enum cases and **bucketed** numbers (durations as ranges, never exact
  seconds).
- Event method signatures accept **only** enums / bucketed types — there is no parameter
  through which a raw string could be passed.
- `PrivacyInfo.xcprivacy`: declare "Product Interaction" analytics, **not** linked to
  identity, **not** used for tracking. TelemetryDeck is anonymous (no IDFA) → clean
  nutrition label.
- Opt-out toggle in Profile/Settings (default **on**) + a line in the TestFlight
  "What to Test" notes.

## Testing

- Swift Testing unit tests against the `emit` spy seam:
  - opt-out gate suppresses emission when `analyticsEnabled == false`;
  - each typed method emits the correct event name + parameters;
  - duration bucketing maps boundaries correctly.
- No network and no real SDK in tests.

## Rollout / timing

Ship analytics **with** the new-feature push, not after — so new features generate data
from day one.

1. Wire facade + SDK + privacy manifest + opt-out toggle.
2. Instrument screens + actions (including the about-to-ship features).
3. One beta cycle (~1–2 weeks) to collect data.
4. **Separate** decision pass: review dashboard, identify zero/low-reach features, plan cuts.
   That cleanup is its own brainstorm/spec — out of scope here.

## Out of scope

- Any feature removal or UI streamlining (follow-up, data-driven).
- Funnel/retention dashboards beyond what TelemetryDeck provides out of the box.
- Migrating or remotely exporting the existing local `SessionHistoryManager` data.
