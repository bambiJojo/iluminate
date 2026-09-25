# SharePlay "Listen Together" — Design

**Date:** 2026-09-24
**Status:** Draft — scoping. Awaiting the requesting user's answer on what "joint collab" means
(see Open questions). Not approved for implementation.
**Surfaces:** Unified player (`.audioLight`, `.session` with audio; `.playlist` in phase 2)

## Request

Post-launch user feedback (2026-09-24):

> Are you able to sync it with somebody else's app? I know you can make your own playlist and
> such and share that url? But are you able to do a joint collab with someone?

That could mean live, synchronized listening, or a playlist two people can both edit. The owner
chose to scope SharePlay (live listening) first while asking the user for more detail.
Collaborative playlists (CloudKit sharing) are a separate design if that turns out to be what
they meant.

## Current state (verified 2026-09-24)

- No group, SharePlay, or multi-device code exists: no `GroupActivities`, `MultipeerConnectivity`,
  or CloudKit sharing anywhere in `Ilumionate/`.
- The audio clock is `AVAudioPlayer`, owned by `AudioSyncController`
  (`Ilumionate/AudioSyncController.swift`), not `AVPlayer`.
- Lights already follow the audio clock. `SessionPlaybackRuntime`
  (`Ilumionate/PlaybackRuntime.swift:128`) drives `LightScorePlayer`, `LightEngine`, audio, and
  binaural from one `begin/pause/resume/seek` surface. **If the audio is synchronized, the
  lights are too** — there is no second clock to reconcile.
- Every library file carries `AudioFile.contentFingerprint`, a SHA-256 of its bytes, computed on
  import and backfilled on load (`AudioLibraryStore.swift:405`). That is an exact,
  privacy-preserving identity to match "the same file" across two devices.
- `KnownAudioCatalog.match(audioFile:)` gives fuzzy identity for known published files whose
  bytes differ (re-encodes, different downloads).

## The constraint that shapes everything

**SharePlay syncs playback state, not media.** Each participant must already have the audio on
their device. LumeSync does not ship content, and the audio is user-imported, frequently adult,
and not ours to redistribute. The design therefore **never transfers audio files** between
participants — not over `GroupSessionMessenger`, not via `GroupSessionJournal`. This is also the
posture App Review has already accepted (`APP_REVIEW_NOTES.md`: "Users choose and remain
responsible for their own local files").

So the core problem is **matching**, not syncing.

## Proposed design

### 1. Activity

A `GroupActivity` named `ListenTogetherActivity`, `Codable`, carrying:

| Field | Purpose |
|---|---|
| `fingerprint: String` | SHA-256 from `contentFingerprint`; exact match |
| `title: String` | Shown in the SharePlay banner and used for the fuzzy fallback |
| `duration: TimeInterval` | Guards the fuzzy fallback (±2 s) |
| `knownCatalogID: String?` | `KnownAudioCatalog` identity when the host's file matched one |
| `sourceURL: URL?` | The playlist/import link the host got it from, if any, so a joiner can import it |
| `lightSession: LightSession?` | Host's generated session JSON, so every participant sees the same lights |

Sending the host's `LightSession` matters. Each device otherwise runs its own analysis, and iOS 18
(keyword heuristics) and iOS 26 (Foundation Models) produce different sessions from the same
audio. The session JSON is small, and a shared session is the point of listening together.

### 2. Joining and matching

On `GroupSession` join, resolve the activity against the local library in order:

1. `contentFingerprint == fingerprint` → exact match, join immediately.
2. `KnownAudioCatalog` match on `knownCatalogID` → offer "Use your copy of *Title*?"
3. Title + duration (±2 s) → offer the same confirmation. Never auto-join on a fuzzy match.
4. No match → a sheet: "You don't have *Title*." If `sourceURL` is present, offer
   **Import from link**, which reuses the existing playlist import flow
   (`PlaylistImport/`), then retries matching. Otherwise explain the joiner needs the file.

### 3. Synchronization

Use **`AVDelegatingPlaybackCoordinator`**, AVFoundation's coordinator for players that are not
`AVPlayer`. Its delegate receives coordinated play/pause/seek commands with a host-time anchor
and routes them into `PlaybackRuntime`. This gets Apple's drift correction, suspension handling
(e.g. a participant takes a call), and "waiting for others" behaviour without a hand-rolled
clock protocol.

Rejected alternatives:

- **Migrate `AudioSyncController` to `AVPlayer` to use `AVPlayerPlaybackCoordinator`.** It is the
  least code for SharePlay itself, but it replaces the audio clock the entire light engine is
  timed against, and puts the playback-sync work already done in `PlaybackRuntime` at risk.
  Revisit only if the delegating coordinator proves inadequate.
- **Custom sync over `GroupSessionMessenger`.** We would own drift correction, latency
  compensation, and suspension semantics ourselves. That's a lot to own for no gain.

The messenger is still used for non-transport state (e.g. playlist track changes in phase 2).

### 4. Safety — local, always

A remote participant must never be able to change what flashes on someone else's screen:

- Joining shows each participant their **own** flashing-lights acknowledgement if they have not
  given it. Light sync starts off for a joiner until they accept.
- `LightSafety` frequency caps and the `LightExposureBudget` apply per device. Hitting your own
  budget dims your lights and does not stop the group.
- **Stop is local.** Leaving or stopping never ends the session for others. Pause is shared, as
  in every SharePlay media app.
- Steady Light, Flash Tint, brightness, and Focus Spots stay personal preferences.

### 5. Entry points

- Player overflow sheet (`PlayerOverflowSheet`): **SharePlay** when a FaceTime call is active
  (`GroupStateObserver.isEligibleForGroupSession`), otherwise **Start SharePlay…**, which presents
  the system share sheet with the activity registered.
- On iOS 18 and macOS 26 this needs no availability gating: GroupActivities predates both
  deployment targets.

### 6. Privacy and review

- The activity metadata (title and fingerprint) goes to FaceTime participants the user chose.
  SharePlay traffic is end-to-end encrypted by Apple, and nothing reaches LumeSync or
  TelemetryDeck. Titles of adult files will be visible to call participants; the Start SharePlay
  confirmation should say so.
- Analytics: at most `sharePlayStarted` / `sharePlayJoined` / `sharePlayMatchResult(kind)` —
  never titles or fingerprints, per the existing TelemetryDeck policy.
- Needs the Group Activities capability on both app entitlements files
  (`Ilumionate.entitlements`, `IlumionateMac.entitlements`) and a provisioning profile update.
  **Verify the exact entitlement key and any Info.plist requirement against current Apple docs
  before implementation** — not confirmed from this repository.
- Add a line to `APP_REVIEW_NOTES.md` explaining that SharePlay shares playback state only and
  that no media leaves the device.

## Phasing

| Phase | Scope |
|---|---|
| 1 | Single file (`.audioLight`, `.session` with audio): activity, fingerprint match, delegating coordinator, shared `LightSession`, local safety |
| 2 | Fuzzy matching + "Import from link" for joiners |
| 3 | Playlists: shared track index over the messenger, per-track matching up front with a pre-flight "you're missing 2 of 8" |

## Testing

- Unit (Swift Testing): matching resolution order, including fuzzy-duration boundaries, no
  auto-join on fuzzy matches, and the missing-file path; activity `Codable` round-trip; the
  coordinator delegate's translation into `PlaybackRuntime` calls against `ManualPlaybackRuntime`.
- Safety: a joiner who has not acknowledged the flash warning gets no light output from a
  remote play command.
- Manual: two physical devices on a FaceTime call. SharePlay does not run in the Simulator —
  **verify this before planning the test matrix**. Cover iOS 18 ↔ iOS 26 (different local
  analysis, same shared lights), and iOS ↔ macOS.

## Open questions

1. **What did the user mean by "joint collab"?** Live listening (this doc), or co-editing a
   playlist? Pending the owner's follow-up with them.
2. Should a guest be able to scrub, or only the host? SharePlay convention is that anyone can;
   hypnosis sessions may want host-only seeking.
3. Is `sourceURL` safe to share? It may be a BambiCloud link that the host considers private.
   Default off, with a toggle in the Start SharePlay confirmation?
