# Light-session duration guardrails

**Date:** 2026-08-21
**Status:** Product research and implementation decision
**Scope:** LumeSync light-engine sessions, audio Light Sync, playlists, Flash, and Color Pulse

## Executive conclusion

There is no evidence-based universal maximum duration that makes rhythmic visual
stimulation safe or comfortable for every person. Photosensitive reactions can occur
early, while people without epilepsy can still experience headache, nausea, dizziness,
or visual discomfort. A duration cap is therefore a **comfort and experience guardrail**,
not a photosensitivity safety threshold and not a substitute for the existing warning.

The evidence is nevertheless consistent enough to make a conservative product choice:

- Default maximum continuous lights-on time: **20 minutes**.
- User choices: **5, 10, 15, 20, 30, 45, or 60 minutes**.
- Count actual lights-on playback time, not audio position or wall-clock time.
- During audio and playlist playback, taper the light field over the final minute, then
  continue audio-only without a spoken prompt, alert, or haptic.
- End light-only Flash and Color Pulse sessions at the selected limit.
- Never call the selected value “safe exposure,” “safe duration,” or a medical limit.
- Continue to tell users to stop immediately if they experience discomfort or unusual
  symptoms, even if only a few seconds or minutes have elapsed.

Twenty minutes is not a discovered biological boundary. It is a conservative default at
the lower end of common AVS protocols, long enough to cover the active exposure in many
published altered-state and entrainment experiments, and short enough to intervene before
the 30–60 minute exposure common in longer consumer sessions.

## What the evidence says

### 1. No study establishes a maximum dose for hypnotic trance

The literature does not provide a dose-response trial that asks how many minutes of
rhythmic light optimizes hypnotic trance while minimizing eye discomfort. Studies vary in
device geometry, luminance, flicker waveform, frequency, color, distance, eyes-open versus
eyes-closed use, participant screening, and intended outcome. Results from LED goggles,
room-sized arrays, and a phone display cannot be treated as interchangeable dose data.

An older review of open-loop AVS also describes the field as limited and methodologically
inconsistent, which is why a precise maximum would overstate the evidence.

Source: [Tang et al., 2016, *Applied Psychophysiology and Biofeedback*](https://pubmed.ncbi.nlm.nih.gov/26294268/)

### 2. Meaningful effects do not clearly require a long exposure

A randomized, controlled study of 262 adults compared rhythmic audiovisual stimulation
at 5.5, 11, and 22 minutes. Mood improvements were broadly similar across durations, and
the authors found some evidence that approximately five minutes might be sufficient for
the outcomes measured. This was not a hypnosis-duration study and it excluded people with
epilepsy, seizures, migraines, photosensitivity, and several eye conditions, so it cannot
define a safe cap. It does show that “longer is better” should not be the product default.

Source: [Johnson, Simonian, and Reggente, 2024, *Scientific Reports*](https://pmc.ncbi.nlm.nih.gov/articles/PMC11513117/)

Twenty-minute exposures are common in laboratory work:

- A flicker-light altered-states study used 20-minute eyes-closed exposures at constant
  light, 3 Hz, and 10 Hz.
- A cortical EEG experiment used 20 minutes of individualized alpha-frequency AVS and
  found some post-exposure EEG effects lasting into the 30-minute follow-up.
- Another repeated AVS experiment used a 20-minute program across 25 sessions.

Sources: [Kometer et al., 2021, *PLOS ONE*](https://pmc.ncbi.nlm.nih.gov/articles/PMC8248711/),
[Timmermann et al., 1999, *International Journal of Psychophysiology*](https://doi.org/10.1016/S0167-8760(98)00064-6),
and [Teplan et al., 2011, *Neuroscience Letters*](https://pubmed.ncbi.nlm.nih.gov/21256616/)

Thirty-minute programs are also common, particularly in sleep research. A small randomized
pilot in older adults used a 30-minute program, descending from 10 Hz to 2 Hz. That is an
example of a chosen study protocol, not evidence that 30 minutes is a universal optimum.

Source: [Tang et al., 2021, *Nature and Science of Sleep*](https://pmc.ncbi.nlm.nih.gov/articles/PMC8196909/)

### 3. One-hour exposure can be tolerated in screened studies, but not by everyone

Small Alzheimer’s feasibility studies have used one hour per day of 40 Hz audiovisual
stimulation and reported that the protocol was feasible and generally well tolerated.
Those participants were screened, the devices and intensity were controlled, and the
sample sizes were small. These studies support offering an upper option for experienced
users; they do not justify making one hour the default.

Source: [Ismail et al., 2021, *Alzheimer's & Dementia: Translational Research & Clinical Interventions*](https://pubmed.ncbi.nlm.nih.gov/34027028/)

A separate one-hour human validation of an open-source 40 Hz system illustrates why
individual tolerance matters: one of eight participants found the light or sound
intolerable, and two reported headache after stimulation. The paper also reports mild
events including dizziness, tinnitus, headache, and worsened hearing in another small
cohort. These are small samples, but they directly contradict a one-size-fits-all comfort
assumption.

Source: [McDermott et al., 2023, *PLOS ONE*](https://pmc.ncbi.nlm.nih.gov/articles/PMC9979148/)

### 4. Consumer-device practice clusters around 15–30 minutes, with longer outliers

MindPlace’s current Kasina catalog includes many 15–25 minute sessions, several 30–40
minute sessions, a 50-minute meditation session, and a legacy 60-minute “Deep Meditation”
session. Its own description calls 60 minutes the longest offering and says it may seem too
long for beginners. The catalog also suggests a gentle 25-minute session for sensitive or
new users. Manufacturer material is not clinical evidence, but it is useful human-factors
evidence about established consumer AVS session design.

Source: [MindPlace Kasina support and factory session catalog](https://mindplacesupport.com/kasina/)

### 5. Duration is only one component of photosensitive risk

The Epilepsy Foundation explains that response depends on frequency, brightness, contrast,
distance, wavelength, and whether the eyes are open or closed. It also notes that people
without epilepsy may experience headache, nausea, or dizziness in response to light. The
frequencies it identifies as commonly provocative overlap LumeSync’s entrainment range.

Source: [Epilepsy Foundation: Photosensitivity and Seizures](https://www.epilepsy.com/what-is-epilepsy/seizure-triggers/photosensitivity)

The ITU flashing-image guidance is even more important for product language: it states that
cumulative risk from successive flashing sequences over a prolonged period is unknown and
that medical opinion suggests risk rises with duration. Broadcast limits are not a device
specification for intentional AVS, but the uncertainty means a timer must never be presented
as making exposure safe.

Source: [ITU-R BT.1702-3, 2023](https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.1702-3-202311-I%21%21PDF-E.pdf)

The WHO’s 20-20-20 eye-break advice is aimed at near-work and ordinary screen strain, not
eyes-closed rhythmic stimulation. Its 20-minute interval happens to align with the selected
default, but it is not the evidence for the LumeSync cutoff and should not be cited in-product
as if it were.

Source: [WHO Science in 5: Adult eye care](https://www.who.int/activities/raising-awareness-on-eye-care/science-in-5/episode--109---adult-eye-care)

## Product decision

### Setting

Use the label **Maximum Light Time** with a recommended 20-minute default. Supporting copy:

> Lights fade out at your limit. When audio is playing, it keeps going. Stop sooner if you feel discomfort.

Avoid the terms “dose,” “safe time,” “medical maximum,” and “protection.”

### Runtime behavior

1. Start a new light-time budget when a playback attempt starts.
2. Advance it only while playback is running and light is actually being emitted.
3. Pausing playback or manually turning lights off pauses the budget.
4. Seeking and playlist track changes do not reset the budget.
5. Over the final 60 seconds, apply a smooth fade to the rendered light output.
6. At the limit:
   - Audio-backed Session, audio Light Sync, and playlist modes disable light output while
     preserving audio position and playback.
   - Light-only Session, Flash, and Color Pulse modes complete.
7. Do not vibrate, speak, show a modal, or reveal hidden controls at the boundary. Show an
   informational status only when controls are already visible or next revealed.
8. Do not persist an automatic cutoff as the user’s manual “lights off” preference. A new
   session receives a fresh budget and starts according to the user’s stored preference.
9. Once the budget is exhausted, do not let track changes or a light toggle silently restart
   output during the same playback attempt.

### Why the default is 20 minutes

The default balances four observations without pretending they form a clinical threshold:

- Controlled AVS and altered-state experiments frequently use 20-minute exposure.
- A strong recent duration comparison found no consistent mood advantage at 11 or 22
  minutes over 5.5 minutes.
- Consumer AVS sessions commonly cluster around 15–25 minutes.
- Discomfort and intolerance are individual and can occur during longer exposure.

### Why the upper choice is 60 minutes

One-hour protocols and consumer sessions exist, so an experienced adult may reasonably
choose 60 minutes. It remains a hard product ceiling because this feature is intended to
interrupt accidentally unbounded playlists, not reproduce indefinitely looping consumer
hardware. Choosing 60 minutes is not an assurance of safety or comfort.

## Follow-up validation

Before marketing this as more than a comfort feature:

- Have a neurologist familiar with photosensitive epilepsy review the warning, frequency,
  contrast, duty-cycle, and full-screen-area behavior.
- Have an optometrist or ophthalmologist review the discomfort language and exclusion
  criteria; eye pain or persistent symptoms should direct the user to stop and seek care.
- Measure actual luminance, contrast, duty cycle, and fade behavior on physical iPhone and
  iPad displays at every supported brightness and accessibility setting.
- In beta, collect an optional post-session comfort rating and the minute at which users
  manually disable lights. Use aggregated observations to revisit the default; do not infer
  a medical threshold from telemetry.
- Specifically test that pauses, seeks, mini-player transitions, audio interruptions,
  playlist crossfades, and track changes cannot reset or bypass the light-time budget.
