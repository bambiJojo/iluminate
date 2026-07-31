#!/usr/bin/env python3
"""Build the private, bundled known-audio transcript and gold-score catalog.

Run from the repository root:

    uv run --with pymupdf python3 Tools/build_known_audio_catalog.py

The source PDFs are intentionally not used at runtime. This script extracts the
individual track transcripts, combines them with reviewed track intent and
playlist-placement metadata, and writes the generated JSON resource consumed by
the app.
"""

from __future__ import annotations

import json
import re
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path

import pymupdf


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = REPOSITORY_ROOT / "Download 2026-07-23T03-56-50-459Z"
TRANSCRIPT_ROOT = SOURCE_ROOT / "bs file transcriptions by series"
OUTPUT_PATH = REPOSITORY_ROOT / "Ilumionate" / "KnownAudioCatalog.json"


@dataclass(frozen=True)
class TrackSpec:
    number: str
    title: str
    start_pattern: str
    role: str
    seed_profile: str
    aliases: tuple[str, ...] = ()
    end_pattern: str | None = None


@dataclass(frozen=True)
class DocumentSpec:
    filename: str
    series: str
    source_url: str
    tracks: tuple[TrackSpec, ...]


@dataclass(frozen=True)
class GoldScoreSpec:
    design_intent: str
    playlist_placement: str
    template: str
    accent_terms: tuple[str, ...]
    reviewed_anchors: tuple["ReviewedAnchor", ...] = ()
    reviewed_audio_timing: bool = False


@dataclass(frozen=True)
class GoldOnlyTrackSpec:
    number: str
    title: str
    series: str
    source_url: str
    role: str
    seed_profile: str
    aliases: tuple[str, ...] = ()
    source_kind: str = "catalogMetadata"
    source_document: str | None = None


@dataclass(frozen=True)
class ReviewedAnchor:
    position: float
    cue: str


@dataclass(frozen=True)
class AudioReference:
    duration: float
    fingerprint: str


@dataclass(frozen=True)
class EvidenceAnchor:
    position: float
    cue: str
    source: str


def track(
    number: str,
    title: str,
    start_pattern: str,
    role: str = "suggestions",
    seed_profile: str = "conditioning",
    aliases: tuple[str, ...] = (),
    end_pattern: str | None = None,
) -> TrackSpec:
    return TrackSpec(
        number=number,
        title=title,
        start_pattern=start_pattern,
        role=role,
        seed_profile=seed_profile,
        aliases=aliases,
        end_pattern=end_pattern,
    )


def gold(
    design_intent: str,
    playlist_placement: str,
    template: str,
    *accent_terms: str,
    reviewed_anchors: tuple[ReviewedAnchor, ...] = (),
    reviewed_audio_timing: bool = False,
) -> GoldScoreSpec:
    return GoldScoreSpec(
        design_intent=design_intent,
        playlist_placement=playlist_placement,
        template=template,
        accent_terms=accent_terms,
        reviewed_anchors=reviewed_anchors,
        reviewed_audio_timing=reviewed_audio_timing,
    )


def anchor(position: float, cue: str) -> ReviewedAnchor:
    return ReviewedAnchor(position=position, cue=cue)


# Exact developer-supplied encodes. Fingerprints let the app recognize these
# recordings even after a user renames them, while the duration calibrates
# transcript markers against the audio rather than stretching the last marker
# to the end of a recording.
KNOWN_AUDIO_REFERENCES = {
    "Rapid Induction": AudioReference(162.037551, "cf7604334801bbf68ef5dc6754f937b816d901b4108e89c25a893027c47bb17e"),
    "Bubble Induction": AudioReference(1049.051429, "8f8dcd009e82cb16cf6f7b0e4ec60c8127d3c6a903b85279d7c2d02e932a9f5d"),
    "Bubble Acceptance": AudioReference(1734.034286, "a619145155c044f196345377ca1a4efe9972f0e236dd1ba2619cf67bbe81d940"),
    "Bambi Named and Drained": AudioReference(949.028571, "22facaa869fae455a588a03403c7bc31305e7ad08e1e9b06ae49bdc93609b542"),
    "Bambi IQ Lock": AudioReference(726.047347, "b3eea76f980a0fba5cb3383c2ffd2b9f82963ab167dc56119ead82974eaa6c4f"),
    "Bambi Body Lock": AudioReference(908.042449, "03dc662ea2aab02c31e29398d17d0da86af355b0f0555a63401307bccfb2fca1"),
    "Bambi Attitude Lock": AudioReference(839.026939, "b829d0d8a13903372ad79b1bfbc53437fb658c6ba538252be0bc726df3662fd4"),
    "Bambi Uniformed": AudioReference(815.046531, "447df4a928e45e58f91d1190806607279dd3e1ab581caf5f2ce2023da8123638"),
    "Bambi Takeover": AudioReference(625.031837, "0892e64827e2cf6e8040b05212506e9ff671a97810c9fa01025a5c06c8195602"),
    "Bambi Cockslut": AudioReference(1081.051429, "b074398a9bff929ff8afd521d67526037cb8bb6c8518c38e2737564f8f99d679"),
    "Bambi Awakens": AudioReference(591.046531, "c669088ae1b0abaef56b7a2b5bb8d3278705c20ec3e432190e84a8767108bbe8"),
    "Blank Mindless Doll": AudioReference(1270.047347, "d8eaa3bb5c40c60967f733ae0dd5f653b6071cf31b24a6497c394dae57ed58f8"),
    "Cock Dumb Hole": AudioReference(552.045714, "c74beed51826f3b9bf239d1b4e6cfe59030913c82a3d4360ad6d2f9223ca6635"),
    "Uniform Slut Puppet": AudioReference(570.044082, "3eb1d58289e99b460c2def0ae4fbf68a410048ccadb9fd478d38291a2283b2e0"),
    "Vain Horny Happy": AudioReference(656.039184, "f64fe41de26d4c323db4891f75fba9ee29e4903248c29fe30e6ed6138687df6a"),
    "Bimbo Drift": AudioReference(308.035918, "09378c1f4647bb8a11fbcd185db1dfbb9d9e5231e2d6b58d4dd2431ba68bb169"),
    "Sleepygirl Salon": AudioReference(704.026122, "3b1ae890737eb3c6ea02fb9a279f6cc8f61e2359b9ea99fbbe3aa99a53033bc6"),
    "Mentally Platinum Blonde": AudioReference(944.039184, "dfdb5b7cebd996c293fe53718b3e490256349d84721fd65e24801a687c8c9609"),
    "Automatic Airhead": AudioReference(956.029388, "ebba39a0e4def1824146d443a36fcbc736462fc1c4537c18b2322945c20758db"),
    "Superficial Basic Bitch": AudioReference(1922.037551, "f6fd0cd031e3312541a957a82aa735d89d108709de53d56e7119b1bcf7507774"),
    "Life Control Total Doll": AudioReference(1815.040000, "341f4818cb819ffaad04c88c49196d8ab7267364e385b80b6fe945016362aed4"),
    "Makeover Awakener": AudioReference(328.045714, "12db1aec5deb20ebd51eee4e60f04520608184747c44ea161f12320f86ea2d81"),
    "Sleepyhead": AudioReference(490.031020, "bab09aa76949e1af1bf8462238116b6e5a17c869f4464b3f01d58992b53d7431"),
    "Bobblehead": AudioReference(470.047347, "1ffd82b56c849628f5a06d38097a20e01f5d792242cda5334676ffe0a78398ee"),
    "Bambidoll": AudioReference(330.031020, "4eecff547b1da5abcf80a4f4e21e8eb02579f555cbbed50ebc287e1d8486d3fa"),
    "Giggledoll": AudioReference(394.031020, "0dd4f2df4c295506fd04fa7593e78138d30e750c6428e39c183a5e66bcf0aebf"),
    "Ohmigod": AudioReference(520.045714, "09a6b23724cf4642235a4c8e8cbbe246de0172a5e0068fe1a8c54bbffcfb42e3"),
    "Ziplock": AudioReference(596.035918, "5d86768ff9a5601cac9c88f0694eef2ea463cd040098f9547cf424d686dd7111"),
    "Bimbodoll Trancetone": AudioReference(154.044082, "d46ffe15ba6c0b9c7bc500e8d69ba4ed9fcc9f052b00af5d435c64dd575bc3a5"),
    "Instant Bimbo Sleepdoll": AudioReference(876.042449, "ed58d993b44501276b4562ed3151b73392e4b162f7eedb906d02d0907b7daca3"),
    "Mindlock Bimbo Slavedoll": AudioReference(1390.027755, "ac7f66c017e0ffd0c40799f70e45ad985396c7d0c533bd41534e6c36d09e05c9"),
    "Total Bimbo Wipeout Doll": AudioReference(1434.044082, "b2df9a1320ecbeb7cd1b32dd4e208be09a4cb8c445a0fbba2859decb91414362"),
    "Blissful Bimbo Dumbdown Doll": AudioReference(3034.044082, "c88cdeb2d569d937c120fa3b40abfcffea252f716372329ad518bc9642adf457"),
    "Pleasurelock Bimbo Compliance Doll": AudioReference(3954.050612, "998951d871ba031d8f38bb448446c0f6e3b20ff6f7df83029d5335d8edefa2bf"),
    "Bimbodoll Sleepener": AudioReference(452.048980, "bb25fdb360c1239fef8c14441b701c35cd963de58fcbde969e7e43ba195e3008"),
}


# Reviewed against the supplied transcripts and the listening/track guidance
# linked by each DocumentSpec. Templates define the transition contract; accent
# terms place a small number of transcript-timed emphasis points within it.
GOLD_SCORE_SPECS = {
    "Bimbodoll Trancetone": gold(
        "Short nonverbal primer for the very beginning of a reboot-series playlist.",
        "entry", "nonverbalPrimer", "binaural", "subliminal",
        reviewed_anchors=(
            anchor(0.50, "stable nonverbal loudness plateau"),
        ),
    ),
    "Bimbo Drone": gold(
        "Short nonverbal support bed that establishes a gentle entry state before spoken tracks.",
        "entry", "nonverbalPrimer", "binaural", "drone",
    ),
    "Rapid Induction": gold(
        "An eighty-second nonverbal primer followed by a fast spoken drop into deep trance for an established listener.",
        "entry", "delayedRapidInduction", "bambi sleep", "sleep now", "deep trance",
        reviewed_anchors=(
            anchor(0.49, "spoken induction begins after nonverbal primer"),
        ),
    ),
    "Bubble Induction": gold(
        "Gradual relaxation and bubble imagery that ends ready for a deepener or conditioning track.",
        "entry", "gradualInduction", "relax", "bubble", "bimbo doll",
    ),
    "Bubble Acceptance": gold(
        "Early-playlist deepening and acceptance work that strengthens the tracks that follow.",
        "early", "deepener", "deeper", "accept", "good girl",
    ),
    "Bambi Named and Drained": gold(
        "Mid-session identity and blankness conditioning that stays connectable to later tracks.",
        "middle", "brainwashing", "bambi", "drain", "empty",
    ),
    "Bambi IQ Lock": gold(
        "Sustained low-theta conditioning with accents at repeated wipe and lock passages.",
        "middle", "brainwashing", "iq", "lock", "wipe",
    ),
    "Bambi Body Lock": gold(
        "Immersive transformation imagery held at a steady playlist-middle depth.",
        "middle", "conditioning", "body", "transform", "lock",
    ),
    "Bambi Attitude Lock": gold(
        "Behavioral conditioning with gentle rhythmic emphasis on repeated lock and trigger language.",
        "middle", "conditioning", "craving", "obey", "resistance", "good girl", "bambi sleep", "bubble", "posture",
    ),
    "Bambi Uniformed": gold(
        "Late-session reinforcement designed to follow the core conditioning tracks without waking.",
        "late", "reinforcement", "uniform", "trigger", "lock",
    ),
    "Bambi Takeover": gold(
        "Late-session identity reinforcement with deeper accents at takeover and replacement passages.",
        "late", "brainwashing", "take over", "replace", "control",
        reviewed_anchors=(
            anchor(0.088, "opening control framing"),
        ),
    ),
    "Bambi Cockslut": gold(
        "Late-session erotic fantasy with a lifted rhythmic contour while preserving a deep handoff.",
        "late", "eroticFantasy", "pleasure", "orgasm", "cum",
    ),
    "Bambi Awakens": gold(
        "Conditioning remains deep through most of the recording, then rises during the final reviewed awakening passage.",
        "exit", "lateEmergence", "wake", "awaken", "eyes open",
        reviewed_anchors=(
            anchor(0.01, "opening future-awakening frame"),
            anchor(0.81, "final awakening setup"),
            anchor(0.962, "spoken wake-up"),
        ),
        reviewed_audio_timing=True,
    ),
    "Bimbo Relaxation": gold(
        "Short relaxation opener that descends gently and hands off to an induction deepener.",
        "entry", "gradualInduction", "relax", "bubble", "training",
    ),
    "Bimbo Mindwipe": gold(
        "Compact early-playlist mind-clearing deepener with emphasis on wipe and blankness language.",
        "early", "rapidDeepener", "mind wipe", "blank", "empty",
    ),
    "Bimbo Slumber": gold(
        "Rapid trigger-led drop that can deepen an existing trance or start a trained listener's session.",
        "early", "rapidDeepener", "bambi sleep", "drop", "deeper",
    ),
    "Bimbo Tranquility": gold(
        "Early-playlist freeze and thought-replacement deepener that settles into a stable low hold.",
        "early", "deepener", "freeze", "tranquil", "replace",
    ),
    "Bimbo Pride": gold(
        "Flexible early or middle reinforcement centered on pride, approval, and obedience passages.",
        "earlyOrMiddle", "reinforcement", "pride", "good girl", "obey",
    ),
    "Bimbo Pleasure": gold(
        "Flexible pleasure-and-compliance reinforcement with a slightly lifted rhythmic contour.",
        "earlyOrMiddle", "eroticFantasy", "pleasure", "cum", "obey",
    ),
    "Bimbo Servitude": gold(
        "Late-playlist obedience reinforcement that remains deep for a following reinforcer or exit.",
        "late", "reinforcement", "obey", "yes", "told",
    ),
    "Bimbo Addiction": gold(
        "Late-playlist repetition-heavy reinforcement with stable, non-emergent transitions.",
        "late", "reinforcement", "addict", "uniform", "primped",
    ),
    "Bimbo Amnesia": gold(
        "Late-playlist amnesia conditioning with transcript accents at forget and blankness clusters.",
        "late", "brainwashing", "forget", "amnesia", "blank",
    ),
    "Bimbo Protection": gold(
        "Late-playlist permanence reinforcement that ends deep so an explicit exit track remains required.",
        "late", "brainwashing", "protect", "permanent", "conditioning",
    ),
    "Blank Mindless Doll": gold(
        "Condensed induction for experienced playlists, descending quickly into a stable deep handoff.",
        "entry", "rapidInduction", "blank", "mindless", "deeper",
    ),
    "Cock Dumb Hole": gold(
        "Mid-session erotic conditioning with soft rhythmic accents and no independent emergence.",
        "middle", "eroticFantasy", "cock", "dumb", "blank",
    ),
    "Uniform Slut Puppet": gold(
        "Mid-session uniform and behavior conditioning designed for seamless sequence playback.",
        "middle", "conditioning", "uniform", "puppet", "control",
    ),
    "Vain Horny Happy": gold(
        "Mid-session identity reinforcement with a steady deep contour before the set's exit track.",
        "middle", "reinforcement", "vain", "happy", "bambi",
    ),
    "Bimbo Drift": gold(
        "Brief memory-clear and gentle awakening that closes the base session or a mixed playlist.",
        "exit", "emergence", "forget", "wake", "awaken",
    ),
    "Fake Plastic Fuckpuppet": gold(
        "Transformation-fantasy add-on that starts and ends at playlist-middle depth.",
        "middle", "conditioning", "plastic", "transform", "lock",
    ),
    "Designer Pleasure Puppet": gold(
        "Appearance-focused add-on with restrained rhythmic emphasis and a deep handoff.",
        "middle", "conditioning", "designer", "pleasure", "uniform",
    ),
    "Bambi Fuckpuppet Oblivion": gold(
        "Long-form brainwashing track that can serve as a deepener or central conditioning segment.",
        "earlyOrMiddle", "brainwashing", "brain drain", "erase", "forget",
    ),
    "Blowup Pleasure Toy": gold(
        "Pleasure-fantasy add-on intended between conditioning and the base session's exit.",
        "middle", "eroticFantasy", "pleasure", "inflate", "cum",
    ),
    "Perfect Bimbo Maid": gold(
        "Role and behavior fantasy that stays at a connectable middle-of-playlist depth.",
        "middle", "conditioning", "maid", "obey", "instruction",
    ),
    "Restrained and Milked": gold(
        "Immersive fantasy add-on with a low-theta hold and soft peaks at pleasure passages.",
        "middle", "eroticFantasy", "pleasure", "milk", "orgasm",
    ),
    "Bimbo Giggletime": gold(
        "Trigger-training add-on with playful fractionation-like accents around repeated giggle cues.",
        "middle", "rhythmicConditioning", "giggle", "trigger", "dizzy",
    ),
    "Mindlocked Cock Zombie": gold(
        "Trigger-training add-on using a narrow deep contour around blankness and lock passages.",
        "middle", "brainwashing", "mindlock", "blank", "trigger",
    ),
    "Sleepygirl Salon": gold(
        "ASMR-styled standalone induction that prepares the listener for the makeover sequence.",
        "entry", "gradualInduction", "sleep", "salon", "relax",
    ),
    "Mentally Platinum Blonde": gold(
        "Core mental-makeover conditioning with a stable central-session contour.",
        "middle", "conditioning", "platinum", "blonde", "program",
    ),
    "Automatic Airhead": gold(
        "Repetition-heavy behavior conditioning with deeper accents at automatic and blankness passages.",
        "middle", "brainwashing", "automatic", "airhead", "blank",
    ),
    "Superficial Basic Bitch": gold(
        "Long-form personality conditioning using a non-habituating low-theta contour.",
        "middle", "conditioning", "superficial", "basic", "perfect",
    ),
    "Life Control Total Doll": gold(
        "Long-form lifestyle conditioning that sustains depth until the separate makeover exit.",
        "middle", "brainwashing", "total doll", "control", "obey",
    ),
    "Makeover Awakener": gold(
        "Final makeover reinforcement followed by a clear emergence to an alert ending.",
        "exit", "emergence", "wake", "awaken", "eyes open",
    ),
    "Instant Bimbo Sleepdoll": gold(
        "Foundational induction with deliberate wake-drop fractionation before a deep playlist handoff.",
        "entry", "fractionatedInduction", "bambi sleep", "wake", "drop",
    ),
    "Mindlock Bimbo Slavedoll": gold(
        "Foundational deepener with a narrow low-theta contour around freeze, blankness, and amnesia.",
        "early", "brainwashing", "freeze", "blank", "forget",
    ),
    "Total Bimbo Wipeout Doll": gold(
        "Central brainwashing track with deep accents around erasure and reconstruction passages.",
        "middle", "brainwashing", "wipeout", "erase", "reconstruct",
    ),
    "Bimbodoll Sleepener": gold(
        "Sleep-oriented playlist exit that descends rather than awakening and deliberately ends low.",
        "sleepExit", "sleepener", "sleep", "forget", "nap",
    ),
    "Pleasurelock Bimbo Compliance Doll": gold(
        "Long-form compliance conditioning with a reviewed wake-and-test fractionation near eighty percent, followed by a return to deep conditioning.",
        "middle", "fractionatedConditioning", "pleasure", "compliance", "obey",
        reviewed_anchors=(
            anchor(0.18, "pleasure-lock calibration"),
            anchor(0.48, "compliance-implant reinforcement"),
            anchor(0.82, "wake-and-test fractionation"),
            anchor(0.90, "return-to-sleep drop"),
            anchor(0.97, "terminal obedience trigger cluster"),
        ),
    ),
    "Blissful Bimbo Dumbdown Doll": gold(
        "Long-form control and intelligence-conditioning track using intent-based structure where timestamps are unavailable.",
        "middle", "brainwashing", "dumb", "level", "control",
    ),
    "Sleepyhead": gold(
        "Puppet Princess deepener built around repeated obedience language and a late sleep-drop sequence.",
        "earlyOrMiddle", "rapidDeepener", "obey", "sleep",
        reviewed_anchors=(
            anchor(0.35, "first sustained obedience cluster"),
            anchor(0.76, "second sustained obedience cluster"),
            anchor(0.95, "terminal sleep-drop cluster"),
        ),
    ),
    "Bobblehead": gold(
        "Puppet Princess deepener using bubble imagery to clear memory, thought, and intelligence before a central-session handoff.",
        "earlyOrMiddle", "brainwashing", "bubble", "memory", "thought", "intelligence",
        reviewed_anchors=(
            anchor(0.18, "memory-and-intelligence clearing cluster"),
            anchor(0.67, "head-focused reinforcement"),
        ),
    ),
    "Bambidoll": gold(
        "Puppet Princess identity-reinforcement loop contrasting the new doll identity with the discarded prior self.",
        "middle", "reinforcement", "partner", "family", "memory", "old self",
        reviewed_anchors=(
            anchor(0.14, "new-identity repetition"),
            anchor(0.56, "old-self rejection cluster"),
        ),
    ),
    "Giggledoll": gold(
        "Mostly musical Puppet Princess reinforcement loop using spaced laughter cues as rhythmic conditioning accents.",
        "middle", "rhythmicConditioning", "laugh", "giggle", "uniform",
        reviewed_anchors=(
            anchor(0.11, "opening laughter cue"),
            anchor(0.47, "mid-loop laughter cue"),
            anchor(0.95, "closing laughter cue"),
        ),
    ),
    "Ohmigod": gold(
        "Puppet Princess makeover-reinforcement loop with an early mental-suppression passage followed by a lighter repeated reaction hold.",
        "middle", "conditioning", "platinum blonde", "pacify", "superficial", "lock", "oh my god",
        reviewed_anchors=(
            anchor(0.04, "mental-suppression and lock passage"),
            anchor(0.13, "reaction cue"),
            anchor(0.20, "repeated reaction hold"),
        ),
    ),
    "Ziplock": gold(
        "Puppet Princess transformation and restraint reinforcement that moves through mental, uniform, hand-lock, and puppet-lock passages.",
        "late", "brainwashing", "zip", "lock", "princess", "uniform", "puppet", "hands",
        reviewed_anchors=(
            anchor(0.22, "mental zip cue"),
            anchor(0.35, "first lock passage"),
            anchor(0.53, "uniform reinforcement"),
            anchor(0.63, "hand-lock cluster"),
            anchor(0.79, "puppet-princess reinforcement"),
        ),
    ),
}


DOCUMENTS = (
    DocumentSpec(
        filename="bambi bimbo doll conditioning transcriptions.pdf",
        series="Bambi Bimbodoll Conditioning",
        source_url="https://bambisleep.info/Bambi_Bimbodoll_Conditioning",
        tracks=(
            track("00", "Rapid Induction", r"^RAPID INDUCTION$", "induction", "induction"),
            track("01", "Bubble Induction", r"^BUBBLE INDUCTION$", "induction", "induction"),
            track("02", "Bubble Acceptance", r"^BUBBLE ACCEPTANCE$", "deepening", "deepening"),
            track("03", "Bambi Named and Drained", r"^NAMED AND DRAINED$"),
            track("04", "Bambi IQ Lock", r"^IQ LOCK$"),
            track("05", "Bambi Body Lock", r"^BODY LOCK$"),
            track("06", "Bambi Attitude Lock", r"^ATTITUDE LOCK$"),
            track("07", "Bambi Uniformed", r"^BAMBI UNIFORMED$"),
            track("08", "Bambi Takeover", r"^BAMBI TAKEOVER$"),
            track("09", "Bambi Cockslut", r"^BAMBI COCKSLUT$"),
            track("10", "Bambi Awakens", r"^BAMBI AWAKENS$", "emergence", "emergence"),
        ),
    ),
    DocumentSpec(
        filename="bimbo enforcement transcriptions.pdf",
        series="Bambi Enforcement",
        source_url="https://bambisleep.info/Bambi_Enforcement",
        tracks=(
            track("01", "Bimbo Relaxation", r"^BIMBO RELAXATION$", "induction", "induction"),
            track("02", "Bimbo Mindwipe", r"^BIMBO MINDWIPE$", "deepening", "deepening"),
            track("03", "Bimbo Slumber", r"^BIMBO SLUMBER$", "deepening", "deepening"),
            track("04", "Bimbo Tranquility", r"^BIMBO TRANQUILITY$", "deepening", "deepening"),
            track("05", "Bimbo Pride", r"^BIMBO PRIDE$"),
            track("06", "Bimbo Pleasure", r"^BIMBO PLEASURE$"),
            track("07", "Bimbo Servitude", r"^BIMBO SERVITUDE$"),
            track("08", "Bimbo Addiction", r"^BIMBO ADDICTION$"),
            track("09", "Bimbo Amnesia", r"^BIMBO AMNESIA$"),
            track("10", "Bimbo Protection", r"^BIMBO PROTECTION$"),
        ),
    ),
    DocumentSpec(
        filename="bambi fuckdoll brainwash transcriptions.pdf",
        series="Bambi Fuckdoll Brainwash",
        source_url="https://bambisleep.info/Bambi_Fuckdoll_Brainwash",
        tracks=(
            track(
                "01",
                "Blank Mindless Doll",
                r"^01 Blank Mindless Doll.*$",
                "induction",
                "induction",
                end_pattern=r"^01 Blowup Pleasure Toy$",
            ),
            track("02", "Cock Dumb Hole", r"^02 Cock Dumb Hole$", end_pattern=r"^UNIFORM SLUT PUPPET$"),
            track("03", "Uniform Slut Puppet", r"^UNIFORM SLUT PUPPET$", end_pattern=r"^VAIN HORNY HAPPY$"),
            track("04", "Vain Horny Happy", r"^VAIN HORNY HAPPY$", end_pattern=r"^BIMBO DRIFT$"),
            track("05", "Bimbo Drift", r"^BIMBO DRIFT$", "emergence", "emergence"),
        ),
    ),
    DocumentSpec(
        filename="bambi fuckpuppet freedom transcriptions.pdf",
        series="Bambi Fuckpuppet Freedom",
        source_url="https://bambisleep.info/Bambi_Fuckpuppet_Freedom",
        tracks=(
            track("01", "Fake Plastic Fuckpuppet", r"^FAKE PLASTIC FUCKPUPPET$"),
            track("02", "Designer Pleasure Puppet", r"^DESIGNER PLEASURE PUPPET$"),
            track("03", "Bambi Fuckpuppet Oblivion", r"^BAMBI FUCKPUPPET OBLIVION$"),
        ),
    ),
    DocumentSpec(
        filename="bambi fucktoy fantasy transcriptions.pdf",
        series="Bambi Fucktoy Fantasy",
        source_url="https://bambisleep.info/Bambi_Fucktoy_Fantasy",
        tracks=(
            track("01", "Blowup Pleasure Toy", r"^01 Blowup Pleasure Toy.*$"),
            track("02", "Perfect Bimbo Maid", r"^02 Perfect Bimbo Maid.*$"),
            track("03", "Restrained and Milked", r"^03 Restrained and Milked.*$"),
        ),
    ),
    DocumentSpec(
        filename="bambi fucktoy submission transcriptions.pdf",
        series="Bambi Fucktoy Submission",
        source_url="https://bambisleep.info/Bambi_Fucktoy_Submission",
        tracks=(
            track("01", "Bimbo Giggletime", r"^BIMBO GIGGLETIME$"),
            track(
                "02",
                "Mindlocked Cock Zombie",
                r"^MINDLOCKED COCK ZOMBIE$",
                aliases=("Mind Locked Cock Zombie",),
            ),
        ),
    ),
    DocumentSpec(
        filename="bambi mental makeover transcriptions.pdf",
        series="Bambi Mental Makeover",
        source_url="https://bambisleep.info/Bambi_Mental_Makeover",
        tracks=(
            track("01", "Sleepygirl Salon", r"^SLEEPYGIRL SALON.*$", "induction", "induction"),
            track("02", "Mentally Platinum Blonde", r"^02 Mentally Platinum Blonde.*$"),
            track("03", "Automatic Airhead", r"^03 Automatic Airhead.*$"),
            track("04", "Superficial Basic Bitch", r"^04 Superficial Basic Bitch.*$"),
            track("05", "Life Control Total Doll", r"^05 Life Control Total Doll.*$"),
            track("07", "Makeover Awakener", r"^07 Makeover Awakener$", "emergence", "emergence"),
        ),
    ),
    DocumentSpec(
        filename="(NEW) bambi slavedoll conditioning.pdf",
        series="Bimbo Slavedoll Conditioning",
        source_url="https://bambisleep.info/Bimbo_Slavedoll_Conditioning",
        tracks=(
            track("01", "Instant Bimbo Sleepdoll", r"^\s*01 Instant Bimbo Sleepdoll\s*$", "induction", "induction"),
            track("02", "Mindlock Bimbo Slavedoll", r"^\s*02 Mindlock Bimbo Slavedoll\s*$", "deepening", "deepening"),
            track("03", "Total Bimbo Wipeout Doll", r"^\s*03 Total Bimbo Wipeout Doll\s*$"),
            track(
                "08",
                "Bimbodoll Sleepener",
                r"^\s*07 Bimbodoll Sleepener\s*$",
                "support",
                "sleep",
                aliases=("07 Bimbodoll Sleepener",),
            ),
        ),
    ),
    DocumentSpec(
        filename="NEW FILE: 4 Blissful Bimbo Dumbdown Doll/04 - Blissful Bimbo Dumbdown Doll-1.pdf",
        series="Bimbo Slavedoll Conditioning",
        source_url="https://bambisleep.info/Bimbo_Slavedoll_Conditioning",
        tracks=(
            track("04", "Blissful Bimbo Dumbdown Doll", r"^04\s*-\s*Blissful Bimbo Dumbdown Doll$"),
        ),
    ),
)


GOLD_ONLY_TRACKS = (
    GoldOnlyTrackSpec(
        number="00",
        title="Bimbo Drone",
        series="Bambi Enforcement",
        source_url="https://bambisleep.info/Bambi_Enforcement",
        role="support",
        seed_profile="induction",
    ),
    GoldOnlyTrackSpec(
        number="00",
        title="Bimbodoll Trancetone",
        series="Bimbo Slavedoll Conditioning",
        source_url="https://bambisleep.info/Bimbo_Slavedoll_Conditioning",
        role="support",
        seed_profile="induction",
        source_kind="localAudioReview",
        source_document="Local audio-envelope review, 2026-07-24",
    ),
    GoldOnlyTrackSpec(
        number="05",
        title="Pleasurelock Bimbo Compliance Doll",
        series="Bimbo Slavedoll Conditioning",
        source_url="https://bambisleep.info/Bimbo_Slavedoll_Conditioning",
        role="suggestions",
        seed_profile="conditioning",
        source_kind="localAudioReview",
        source_document="Local WhisperKit base transcription review, 2026-07-24",
    ),
    GoldOnlyTrackSpec(
        number="01",
        title="Sleepyhead",
        series="Bambi Puppet Princess Loops",
        source_url="https://bambisleep.info/Bambi_Puppet_Princess_Loops",
        role="deepening",
        seed_profile="deepening",
        source_kind="localAudioReview",
        source_document="Local WhisperKit base transcription review, 2026-07-24",
    ),
    GoldOnlyTrackSpec(
        number="02",
        title="Bobblehead",
        series="Bambi Puppet Princess Loops",
        source_url="https://bambisleep.info/Bambi_Puppet_Princess_Loops",
        role="deepening",
        seed_profile="deepening",
        source_kind="localAudioReview",
        source_document="Local WhisperKit base transcription review, 2026-07-24",
    ),
    GoldOnlyTrackSpec(
        number="03",
        title="Bambidoll",
        series="Bambi Puppet Princess Loops",
        source_url="https://bambisleep.info/Bambi_Puppet_Princess_Loops",
        role="support",
        seed_profile="conditioning",
        source_kind="localAudioReview",
        source_document="Local WhisperKit base transcription review, 2026-07-24",
    ),
    GoldOnlyTrackSpec(
        number="04",
        title="Giggledoll",
        series="Bambi Puppet Princess Loops",
        source_url="https://bambisleep.info/Bambi_Puppet_Princess_Loops",
        role="support",
        seed_profile="conditioning",
        source_kind="localAudioReview",
        source_document="Local WhisperKit base transcription review, 2026-07-24",
    ),
    GoldOnlyTrackSpec(
        number="05",
        title="Ohmigod",
        series="Bambi Puppet Princess Loops",
        source_url="https://bambisleep.info/Bambi_Puppet_Princess_Loops",
        role="support",
        seed_profile="conditioning",
        source_kind="localAudioReview",
        source_document="Local WhisperKit base transcription review, 2026-07-24",
    ),
    GoldOnlyTrackSpec(
        number="06",
        title="Ziplock",
        series="Bambi Puppet Princess Loops",
        source_url="https://bambisleep.info/Bambi_Puppet_Princess_Loops",
        role="suggestions",
        seed_profile="conditioning",
        source_kind="localAudioReview",
        source_document="Local WhisperKit base transcription review, 2026-07-24",
    ),
)


def score_point(
    position: float,
    frequency: float,
    intensity: float,
    waveform: str,
    *,
    ramp_duration: float = 10.0,
    bilateral: bool | None = None,
    bilateral_transition_duration: float | None = None,
    color_temperature: float = 2800.0,
) -> dict[str, object]:
    return {
        "position": position,
        "frequency": frequency,
        "intensity": intensity,
        "waveform": waveform,
        "rampDuration": ramp_duration,
        "bilateral": bilateral,
        "bilateralTransitionDuration": bilateral_transition_duration,
        "colorTemperature": color_temperature,
    }


# Each template is a playlist transition contract expressed in normalized time.
# Intensities remain deliberately moderate; the runtime continues to enforce the
# app-wide flash-frequency clamp and user brightness controls.
GOLD_SCORE_TEMPLATES = {
    "nonverbalPrimer": (
        score_point(0.00, 10.0, 0.12, "sine", ramp_duration=6, color_temperature=4500),
        score_point(0.18, 9.2, 0.16, "sine", ramp_duration=7, color_temperature=4100),
        score_point(0.36, 8.4, 0.19, "sine", ramp_duration=8, color_temperature=3700),
        score_point(0.56, 7.6, 0.22, "soft_pulse", ramp_duration=8, color_temperature=3300),
        score_point(0.78, 6.9, 0.23, "soft_pulse", ramp_duration=8, color_temperature=3000),
        score_point(1.00, 6.4, 0.21, "sine", ramp_duration=8, color_temperature=2900),
    ),
    "delayedRapidInduction": (
        score_point(0.00, 10.0, 0.14, "sine", ramp_duration=6, color_temperature=4500),
        score_point(0.25, 9.3, 0.17, "sine", ramp_duration=8, color_temperature=4100),
        score_point(0.48, 8.4, 0.20, "sine", ramp_duration=8, color_temperature=3700),
        score_point(0.56, 7.1, 0.27, "soft_pulse", ramp_duration=4, color_temperature=3200),
        score_point(0.68, 5.5, 0.35, "soft_pulse", ramp_duration=4, bilateral=True, bilateral_transition_duration=3, color_temperature=2700),
        score_point(0.82, 4.3, 0.42, "noise_sine", ramp_duration=4, bilateral=True, color_temperature=2200),
        score_point(1.00, 4.8, 0.36, "sine", bilateral=True, color_temperature=2500),
    ),
    "rapidInduction": (
        score_point(0.00, 10.0, 0.18, "sine", ramp_duration=4, color_temperature=4600),
        score_point(0.05, 8.5, 0.24, "sine", ramp_duration=3, color_temperature=4000),
        score_point(0.13, 6.4, 0.31, "soft_pulse", ramp_duration=3, color_temperature=3300),
        score_point(0.26, 5.0, 0.38, "soft_pulse", ramp_duration=4, bilateral=True, bilateral_transition_duration=3, color_temperature=2700),
        score_point(0.55, 4.4, 0.41, "noise_sine", bilateral=True, color_temperature=2300),
        score_point(0.82, 4.2, 0.40, "noise_sine", bilateral=True, color_temperature=2200),
        score_point(1.00, 4.8, 0.36, "sine", bilateral=True, color_temperature=2500),
    ),
    "gradualInduction": (
        score_point(0.00, 10.0, 0.16, "sine", ramp_duration=8, color_temperature=4800),
        score_point(0.12, 9.0, 0.21, "sine", ramp_duration=12, color_temperature=4200),
        score_point(0.28, 7.6, 0.27, "sine", ramp_duration=14, color_temperature=3600),
        score_point(0.48, 6.2, 0.33, "soft_pulse", ramp_duration=16, color_temperature=3000),
        score_point(0.70, 5.1, 0.38, "soft_pulse", bilateral=True, bilateral_transition_duration=5, color_temperature=2600),
        score_point(0.88, 4.5, 0.40, "noise_sine", bilateral=True, color_temperature=2250),
        score_point(1.00, 4.7, 0.36, "sine", bilateral=True, color_temperature=2500),
    ),
    "fractionatedInduction": (
        score_point(0.00, 10.0, 0.17, "sine", ramp_duration=7, color_temperature=4700),
        score_point(0.12, 7.6, 0.28, "soft_pulse", ramp_duration=8, color_temperature=3400),
        score_point(0.25, 5.3, 0.39, "soft_pulse", ramp_duration=6, bilateral=True, bilateral_transition_duration=3, color_temperature=2600),
        score_point(0.36, 8.3, 0.27, "sine", ramp_duration=5, bilateral=False, color_temperature=3800),
        score_point(0.48, 4.8, 0.42, "soft_pulse", ramp_duration=5, bilateral=True, bilateral_transition_duration=2, color_temperature=2350),
        score_point(0.64, 7.2, 0.30, "sine", ramp_duration=5, bilateral=False, color_temperature=3300),
        score_point(0.76, 4.3, 0.43, "noise_sine", ramp_duration=5, bilateral=True, bilateral_transition_duration=2, color_temperature=2200),
        score_point(1.00, 4.7, 0.37, "sine", bilateral=True, color_temperature=2450),
    ),
    "deepener": (
        score_point(0.00, 5.8, 0.32, "sine", ramp_duration=8, bilateral=True, color_temperature=2850),
        score_point(0.16, 5.2, 0.36, "soft_pulse", ramp_duration=10, bilateral=True, color_temperature=2600),
        score_point(0.36, 4.6, 0.40, "soft_pulse", ramp_duration=12, bilateral=True, color_temperature=2350),
        score_point(0.58, 4.2, 0.42, "noise_sine", bilateral=True, color_temperature=2200),
        score_point(0.78, 4.0, 0.43, "noise_sine", bilateral=True, color_temperature=2100),
        score_point(0.92, 4.1, 0.41, "soft_pulse", bilateral=True, color_temperature=2200),
        score_point(1.00, 4.4, 0.36, "sine", bilateral=True, color_temperature=2450),
    ),
    "rapidDeepener": (
        score_point(0.00, 6.2, 0.30, "sine", ramp_duration=3, bilateral=True, color_temperature=3000),
        score_point(0.06, 5.1, 0.37, "triangle", ramp_duration=2, bilateral=True, bilateral_transition_duration=2, color_temperature=2600),
        score_point(0.16, 4.4, 0.42, "soft_pulse", ramp_duration=3, bilateral=True, color_temperature=2250),
        score_point(0.38, 4.0, 0.43, "noise_sine", bilateral=True, color_temperature=2100),
        score_point(0.65, 4.2, 0.42, "noise_sine", bilateral=True, color_temperature=2150),
        score_point(0.86, 4.0, 0.41, "soft_pulse", bilateral=True, color_temperature=2200),
        score_point(1.00, 4.4, 0.36, "sine", bilateral=True, color_temperature=2450),
    ),
    "conditioning": (
        score_point(0.00, 4.8, 0.34, "sine", ramp_duration=8, bilateral=True, color_temperature=2650),
        score_point(0.14, 4.5, 0.38, "soft_pulse", ramp_duration=10, bilateral=True, color_temperature=2450),
        score_point(0.34, 4.2, 0.41, "noise_sine", bilateral=True, color_temperature=2250),
        score_point(0.55, 4.5, 0.40, "noise_sine", bilateral=True, color_temperature=2300),
        score_point(0.74, 4.1, 0.42, "soft_pulse", bilateral=True, color_temperature=2150),
        score_point(0.90, 4.4, 0.39, "soft_pulse", bilateral=True, color_temperature=2350),
        score_point(1.00, 4.7, 0.34, "sine", bilateral=True, color_temperature=2600),
    ),
    "brainwashing": (
        score_point(0.00, 4.9, 0.34, "sine", ramp_duration=7, bilateral=True, color_temperature=2600),
        score_point(0.12, 4.4, 0.40, "soft_pulse", ramp_duration=8, bilateral=True, color_temperature=2350),
        score_point(0.30, 4.0, 0.43, "noise_sine", bilateral=True, color_temperature=2150),
        score_point(0.50, 3.8, 0.44, "noise_sine", bilateral=True, color_temperature=2050),
        score_point(0.70, 4.1, 0.43, "noise_sine", bilateral=True, color_temperature=2100),
        score_point(0.88, 4.0, 0.42, "soft_pulse", bilateral=True, color_temperature=2200),
        score_point(1.00, 4.6, 0.35, "sine", bilateral=True, color_temperature=2550),
    ),
    "reinforcement": (
        score_point(0.00, 4.9, 0.33, "sine", ramp_duration=7, bilateral=True, color_temperature=2650),
        score_point(0.16, 4.6, 0.37, "soft_pulse", ramp_duration=8, bilateral=True, color_temperature=2450),
        score_point(0.36, 4.3, 0.40, "noise_sine", bilateral=True, color_temperature=2300),
        score_point(0.58, 4.6, 0.39, "soft_pulse", bilateral=True, color_temperature=2350),
        score_point(0.78, 4.3, 0.40, "noise_sine", bilateral=True, color_temperature=2250),
        score_point(0.92, 4.7, 0.37, "soft_pulse", bilateral=True, color_temperature=2450),
        score_point(1.00, 5.1, 0.32, "sine", bilateral=True, color_temperature=2800),
    ),
    "eroticFantasy": (
        score_point(0.00, 5.1, 0.33, "sine", ramp_duration=7, bilateral=True, color_temperature=2600),
        score_point(0.14, 5.5, 0.37, "soft_pulse", ramp_duration=7, bilateral=True, color_temperature=2400),
        score_point(0.32, 5.0, 0.40, "soft_pulse", bilateral=True, color_temperature=2200),
        score_point(0.52, 5.8, 0.42, "soft_pulse", bilateral=True, color_temperature=2150),
        score_point(0.72, 5.2, 0.41, "noise_sine", bilateral=True, color_temperature=2100),
        score_point(0.90, 5.6, 0.38, "soft_pulse", bilateral=True, color_temperature=2300),
        score_point(1.00, 5.0, 0.33, "sine", bilateral=True, color_temperature=2650),
    ),
    "rhythmicConditioning": (
        score_point(0.00, 5.0, 0.33, "sine", ramp_duration=6, bilateral=True, color_temperature=2700),
        score_point(0.14, 6.2, 0.38, "soft_pulse", ramp_duration=5, bilateral=True, color_temperature=2550),
        score_point(0.30, 4.5, 0.41, "soft_pulse", ramp_duration=5, bilateral=True, color_temperature=2250),
        score_point(0.46, 6.0, 0.38, "soft_pulse", ramp_duration=5, bilateral=True, color_temperature=2500),
        score_point(0.62, 4.3, 0.42, "noise_sine", ramp_duration=5, bilateral=True, color_temperature=2150),
        score_point(0.80, 5.7, 0.38, "soft_pulse", ramp_duration=5, bilateral=True, color_temperature=2450),
        score_point(1.00, 4.8, 0.34, "sine", bilateral=True, color_temperature=2650),
    ),
    "fractionatedConditioning": (
        score_point(0.00, 4.9, 0.33, "sine", ramp_duration=7, bilateral=True, color_temperature=2650),
        score_point(0.15, 4.5, 0.38, "soft_pulse", ramp_duration=10, bilateral=True, color_temperature=2350),
        score_point(0.35, 5.2, 0.41, "soft_pulse", ramp_duration=8, bilateral=True, color_temperature=2250),
        score_point(0.55, 4.3, 0.42, "noise_sine", ramp_duration=10, bilateral=True, color_temperature=2150),
        score_point(0.72, 4.6, 0.39, "soft_pulse", ramp_duration=8, bilateral=True, color_temperature=2350),
        score_point(0.78, 6.4, 0.33, "sine", ramp_duration=8, bilateral=False, bilateral_transition_duration=5, color_temperature=3200),
        score_point(0.82, 9.6, 0.28, "sine", ramp_duration=6, bilateral=False, color_temperature=4200),
        score_point(0.87, 8.4, 0.29, "sine", ramp_duration=6, bilateral=False, color_temperature=3850),
        score_point(0.90, 5.0, 0.38, "soft_pulse", ramp_duration=5, bilateral=True, bilateral_transition_duration=3, color_temperature=2550),
        score_point(0.96, 4.1, 0.42, "noise_sine", ramp_duration=6, bilateral=True, color_temperature=2150),
        score_point(1.00, 4.8, 0.34, "sine", bilateral=True, color_temperature=2600),
    ),
    "lateEmergence": (
        score_point(0.00, 4.7, 0.34, "sine", ramp_duration=8, bilateral=True, color_temperature=2450),
        score_point(0.18, 4.5, 0.38, "soft_pulse", ramp_duration=10, bilateral=True, color_temperature=2300),
        score_point(0.42, 4.2, 0.41, "noise_sine", ramp_duration=12, bilateral=True, color_temperature=2150),
        score_point(0.68, 4.4, 0.39, "soft_pulse", ramp_duration=10, bilateral=True, color_temperature=2300),
        score_point(0.82, 5.2, 0.35, "sine", ramp_duration=10, bilateral=False, bilateral_transition_duration=5, color_temperature=2850),
        score_point(0.90, 7.2, 0.30, "sine", ramp_duration=8, bilateral=False, color_temperature=3500),
        score_point(0.96, 10.4, 0.24, "sine", ramp_duration=6, bilateral=False, color_temperature=4500),
        score_point(1.00, 12.0, 0.20, "sine", ramp_duration=5, bilateral=False, color_temperature=5200),
    ),
    "emergence": (
        score_point(0.00, 4.6, 0.35, "sine", ramp_duration=8, bilateral=True, color_temperature=2400),
        score_point(0.28, 4.8, 0.36, "soft_pulse", bilateral=True, color_temperature=2500),
        score_point(0.50, 5.5, 0.34, "sine", ramp_duration=10, bilateral=False, bilateral_transition_duration=5, color_temperature=2900),
        score_point(0.68, 7.0, 0.31, "sine", ramp_duration=10, bilateral=False, color_temperature=3400),
        score_point(0.82, 8.8, 0.28, "sine", ramp_duration=8, bilateral=False, color_temperature=4000),
        score_point(0.93, 10.5, 0.24, "sine", ramp_duration=6, bilateral=False, color_temperature=4600),
        score_point(1.00, 12.0, 0.20, "sine", ramp_duration=5, bilateral=False, color_temperature=5200),
    ),
    "sleepener": (
        score_point(0.00, 5.0, 0.31, "sine", ramp_duration=8, bilateral=True, color_temperature=2600),
        score_point(0.16, 4.5, 0.34, "soft_pulse", ramp_duration=10, bilateral=True, color_temperature=2350),
        score_point(0.36, 3.8, 0.36, "noise_sine", ramp_duration=12, bilateral=True, color_temperature=2150),
        score_point(0.58, 3.1, 0.34, "noise_sine", ramp_duration=14, bilateral=True, color_temperature=2000),
        score_point(0.78, 2.5, 0.30, "sine", ramp_duration=14, bilateral=False, bilateral_transition_duration=6, color_temperature=2000),
        score_point(0.92, 2.0, 0.25, "sine", ramp_duration=12, bilateral=False, color_temperature=2000),
        score_point(1.00, 1.5, 0.18, "sine", ramp_duration=10, bilateral=False, color_temperature=2000),
    ),
}


TIMESTAMP_PATTERN = re.compile(
    r"(?m)^[ \t]*\[?"
    r"(?P<first>\d{1,2}):(?P<second>\d{2})(?::(?P<third>\d{2}))?"
    r"(?:\s*[-–]\s*\d{1,2}:\d{2}(?::\d{2})?)?"
    r"\]?[ \t]*(?P<inline>[^\n]*)$"
)
GOLD_SCORE_NAMESPACE = uuid.UUID("d6f6410e-f3fa-45b9-97f3-37a377c18c61")


def timestamp_seconds(match: re.Match[str]) -> float:
    first = int(match.group("first"))
    second = int(match.group("second"))
    third = match.group("third")
    if third is None:
        return first * 60 + second
    return first * 3600 + second * 60 + int(third)


def transcript_accent_positions(
    transcript: str,
    accent_terms: tuple[str, ...],
    reference_duration: float | None,
) -> tuple[list[EvidenceAnchor], str, float | None]:
    matches = list(TIMESTAMP_PATTERN.finditer(transcript))
    if len(matches) < 2:
        return transcript_order_accent_positions(
            transcript,
            accent_terms,
            reference_duration,
        )

    timed_text: list[tuple[float, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(transcript)
        timed_text.append((
            timestamp_seconds(match),
            f"{match.group('inline')} {transcript[match.end():end]}".casefold(),
        ))

    final_marker = max(time for time, _ in timed_text)
    duration_basis = reference_duration or final_marker
    if duration_basis < 30:
        return [], "intentOnly", None

    bucket_width = max(20.0, min(60.0, duration_basis / 18.0))
    bucket_text: dict[int, list[str]] = {}
    for time, text in timed_text:
        bucket_text.setdefault(int(time / bucket_width), []).append(text)

    candidates: list[tuple[int, float, str]] = []
    for bucket, chunks in bucket_text.items():
        joined = " ".join(chunks)
        term_counts = [
            (joined.count(term.casefold()), term)
            for term in accent_terms
        ]
        score = sum(count for count, _ in term_counts)
        position = min((bucket + 0.5) * bucket_width / duration_basis, 0.96)
        if score > 0 and 0.05 < position < 0.95:
            cue = "/".join(
                term for count, term in sorted(term_counts, reverse=True)
                if count > 0
            )
            candidates.append((score, position, cue))

    maximum_count = max(2, min(6, int((duration_basis + 299) // 300)))
    selected: list[EvidenceAnchor] = []
    for _, position, cue in sorted(candidates, key=lambda item: (-item[0], item[1])):
        if all(abs(position - existing.position) >= 0.08 for existing in selected):
            selected.append(EvidenceAnchor(
                position=round(position, 4),
                cue=cue,
                source="timedTranscript",
            ))
        if len(selected) == maximum_count:
            break
    coverage = (
        round(final_marker / reference_duration, 4)
        if reference_duration
        else None
    )
    basis = "referenceAudio" if reference_duration else "transcriptMarkers"
    return sorted(selected, key=lambda item: item.position), basis, coverage


def transcript_order_accent_positions(
    transcript: str,
    accent_terms: tuple[str, ...],
    reference_duration: float | None,
) -> tuple[list[EvidenceAnchor], str, None]:
    normalized = transcript.casefold()
    if len(normalized) < 200 or not accent_terms:
        return [], "intentOnly", None

    bucket_count = 18
    bucket_size = max(1, len(normalized) // bucket_count)
    candidates: list[tuple[int, float, str]] = []
    for bucket in range(bucket_count):
        start = bucket * bucket_size
        end = len(normalized) if bucket == bucket_count - 1 else (bucket + 1) * bucket_size
        chunk = normalized[start:end]
        term_counts = [
            (chunk.count(term.casefold()), term)
            for term in accent_terms
        ]
        score = sum(count for count, _ in term_counts)
        position = (start + (end - start) / 2) / len(normalized)
        if score > 0 and 0.05 < position < 0.95:
            cue = "/".join(
                term for count, term in sorted(term_counts, reverse=True)
                if count > 0
            )
            candidates.append((score, position, cue))

    estimated_duration = reference_duration or max(30.0, len(normalized.split()) / 2.2)
    maximum_count = max(2, min(6, int((estimated_duration + 299) // 300)))
    selected: list[EvidenceAnchor] = []
    for _, position, cue in sorted(candidates, key=lambda item: (-item[0], item[1])):
        if all(abs(position - existing.position) >= 0.08 for existing in selected):
            selected.append(EvidenceAnchor(
                position=round(position, 4),
                cue=cue,
                source="transcriptOrder",
            ))
        if len(selected) == maximum_count:
            break
    return sorted(selected, key=lambda item: item.position), "transcriptOrder", None


def interpolated_value(
    moments: list[dict[str, object]],
    position: float,
    key: str,
) -> float:
    previous = moments[0]
    for current in moments[1:]:
        if float(current["position"]) >= position:
            span = float(current["position"]) - float(previous["position"])
            progress = 0 if span == 0 else (position - float(previous["position"])) / span
            return float(previous[key]) + (float(current[key]) - float(previous[key])) * progress
        previous = current
    return float(moments[-1][key])


def transcript_accent_point(
    template: str,
    moments: list[dict[str, object]],
    position: float,
) -> dict[str, object]:
    frequency = interpolated_value(moments, position, "frequency")
    intensity = interpolated_value(moments, position, "intensity")
    color_temperature = interpolated_value(moments, position, "colorTemperature")

    if template in {"emergence", "lateEmergence"}:
        return score_point(
            position, frequency + 0.45, min(intensity + 0.02, 0.46), "sine",
            ramp_duration=6, bilateral=False, color_temperature=min(color_temperature + 150, 5200),
        )
    if template in {"eroticFantasy", "rhythmicConditioning"}:
        return score_point(
            position, frequency + 0.30, min(intensity + 0.035, 0.46), "soft_pulse",
            ramp_duration=5, bilateral=True, color_temperature=max(color_temperature - 100, 2000),
        )
    if template == "sleepener":
        return score_point(
            position, max(frequency - 0.30, 1.5), min(intensity + 0.02, 0.40), "noise_sine",
            ramp_duration=8, bilateral=True, color_temperature=2000,
        )
    if template == "fractionatedConditioning":
        if 0.76 <= position <= 0.88:
            return score_point(
                position, min(frequency + 0.35, 10.5), max(intensity - 0.02, 0.20), "sine",
                ramp_duration=5, bilateral=False, color_temperature=min(color_temperature + 250, 4600),
            )
        return score_point(
            position, max(frequency - 0.20, 3.8), min(intensity + 0.03, 0.45), "noise_sine",
            ramp_duration=6, bilateral=True, color_temperature=max(color_temperature - 100, 2000),
        )
    if template in {"brainwashing", "deepener", "rapidDeepener"}:
        return score_point(
            position, max(frequency - 0.25, 3.5), min(intensity + 0.03, 0.46), "noise_sine",
            ramp_duration=6, bilateral=True, color_temperature=max(color_temperature - 100, 2000),
        )
    if template in {"rapidInduction", "delayedRapidInduction", "gradualInduction", "fractionatedInduction"}:
        return score_point(
            position, max(frequency - 0.20, 4.0), min(intensity + 0.03, 0.44), "soft_pulse",
            ramp_duration=6, bilateral=position >= 0.4, color_temperature=max(color_temperature - 100, 2100),
        )
    return score_point(
        position, max(frequency - 0.10, 4.0), min(intensity + 0.03, 0.45), "soft_pulse",
        ramp_duration=6, bilateral=True, color_temperature=max(color_temperature - 75, 2100),
    )


def build_gold_light_score(
    entry_id: str,
    spec: TrackSpec | GoldOnlyTrackSpec,
    transcript: str,
) -> dict[str, object]:
    gold_spec = GOLD_SCORE_SPECS.get(spec.title)
    if gold_spec is None:
        raise ValueError(f"Missing gold light-score specification for {spec.title!r}")

    template = GOLD_SCORE_TEMPLATES.get(gold_spec.template)
    if template is None:
        raise ValueError(f"Unknown gold light-score template {gold_spec.template!r}")

    moments = [dict(moment) for moment in template]
    reference = KNOWN_AUDIO_REFERENCES.get(spec.title)
    evidence_anchors, timing_basis, transcript_coverage = transcript_accent_positions(
        transcript,
        gold_spec.accent_terms,
        reference.duration if reference else None,
    )
    if gold_spec.reviewed_audio_timing:
        evidence_anchors = []
        timing_basis = "reviewedAudioTiming"
    reviewed_source = (
        "localModelTranscript"
        if gold_spec.reviewed_audio_timing
        or (
            isinstance(spec, GoldOnlyTrackSpec)
            and spec.source_kind == "localAudioReview"
        )
        else "reviewedIntent"
    )
    for reviewed in gold_spec.reviewed_anchors:
        candidate = EvidenceAnchor(
            position=reviewed.position,
            cue=reviewed.cue,
            source=reviewed_source,
        )
        if all(abs(candidate.position - existing.position) >= 0.04 for existing in evidence_anchors):
            evidence_anchors.append(candidate)
    evidence_anchors.sort(key=lambda item: item.position)
    if gold_spec.reviewed_anchors and (
        not transcript or gold_spec.reviewed_audio_timing
    ):
        timing_basis = "reviewedAudioTiming"

    for evidence_anchor in evidence_anchors:
        point = transcript_accent_point(
            gold_spec.template,
            moments,
            evidence_anchor.position,
        )
        existing_index = next(
            (
                index for index, moment in enumerate(moments)
                if abs(float(moment["position"]) - evidence_anchor.position) < 0.0001
            ),
            None,
        )
        if existing_index is None:
            moments.append(point)
        else:
            moments[existing_index] = point
    moments.sort(key=lambda moment: float(moment["position"]))

    positions = [float(moment["position"]) for moment in moments]
    if positions[0] != 0 or positions[-1] != 1:
        raise ValueError(f"Gold score for {spec.title!r} must cover normalized time 0...1")
    if any(current <= previous for previous, current in zip(positions, positions[1:])):
        raise ValueError(f"Gold score for {spec.title!r} contains duplicate or reversed moments")

    return {
        "scoreVersion": 2,
        "sessionID": str(uuid.uuid5(
            GOLD_SCORE_NAMESPACE,
            f"{entry_id}:gold-light-score:v2",
        )),
        "designIntent": gold_spec.design_intent,
        "playlistPlacement": gold_spec.playlist_placement,
        "evidenceKind": (
            "localAudioReview"
            if gold_spec.reviewed_audio_timing
            or (
                isinstance(spec, GoldOnlyTrackSpec)
                and spec.source_kind == "localAudioReview"
            )
            else "communityTranscript"
            if transcript
            else "catalogMetadata"
        ),
        "timingBasis": timing_basis,
        "referenceDuration": reference.duration if reference else None,
        "transcriptCoverage": transcript_coverage,
        "transcriptAnchorCount": len(evidence_anchors),
        "evidenceAnchors": [
            {
                "position": evidence_anchor.position,
                "cue": evidence_anchor.cue,
                "source": evidence_anchor.source,
            }
            for evidence_anchor in evidence_anchors
        ],
        "moments": moments,
    }


def extract_document_text(path: Path) -> str:
    document = pymupdf.open(path)
    return "\n".join(page.get_text("text", sort=True) for page in document)


def clean_transcript(text: str) -> str:
    text = text.replace("\u00ad", "").replace("\u00a0", " ")
    lines = [line.rstrip() for line in text.splitlines()]
    text = "\n".join(lines)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def slug(value: str) -> str:
    value = value.casefold()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


def aliases_for_values(
    series: str,
    number: str,
    title: str,
    additional_aliases: tuple[str, ...] = (),
) -> list[str]:
    aliases = {
        title,
        f"{number} {title}",
        f"{number} - {title}",
        f"{series} {number} {title}",
        *additional_aliases,
    }
    return sorted(aliases, key=lambda value: (len(value), value.casefold()))


def aliases_for(document: DocumentSpec, spec: TrackSpec) -> list[str]:
    return aliases_for_values(
        document.series,
        spec.number,
        spec.title,
        spec.aliases,
    )


def extract_tracks(document: DocumentSpec, text: str) -> list[dict[str, object]]:
    matches: list[tuple[TrackSpec, re.Match[str]]] = []
    for spec in document.tracks:
        match = re.search(spec.start_pattern, text, flags=re.MULTILINE | re.IGNORECASE)
        if match is None:
            raise ValueError(f"Could not find {spec.title!r} in {document.filename}")
        matches.append((spec, match))

    matches.sort(key=lambda item: item[1].start())
    entries: list[dict[str, object]] = []
    for index, (spec, start_match) in enumerate(matches):
        next_start = matches[index + 1][1].start() if index + 1 < len(matches) else len(text)
        if spec.end_pattern:
            end_match = re.search(
                spec.end_pattern,
                text[start_match.end():],
                flags=re.MULTILINE | re.IGNORECASE,
            )
            if end_match is None:
                raise ValueError(f"Could not find end marker for {spec.title!r}")
            end = start_match.end() + end_match.start()
        else:
            end = next_start

        transcript = clean_transcript(text[start_match.end():end])
        if len(transcript) < 200:
            raise ValueError(f"Transcript for {spec.title!r} is unexpectedly short")

        entry_id = f"{slug(document.series)}-{spec.number}-{slug(spec.title)}"
        reference = KNOWN_AUDIO_REFERENCES.get(spec.title)
        entries.append(
            {
                "id": entry_id,
                "series": document.series,
                "trackNumber": spec.number,
                "title": spec.title,
                "aliases": aliases_for(document, spec),
                "contentFingerprints": [reference.fingerprint] if reference else [],
                "role": spec.role,
                "seedProfile": spec.seed_profile,
                "creator": "Bambi Prime",
                "sourceKind": "communityTranscript",
                "sourceDocument": document.filename,
                "sourceURL": document.source_url,
                "transcript": transcript,
                "goldLightScore": build_gold_light_score(
                    entry_id,
                    spec,
                    transcript,
                ),
            }
        )
    return entries


def build_gold_only_entries() -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for spec in GOLD_ONLY_TRACKS:
        entry_id = f"{slug(spec.series)}-{spec.number}-{slug(spec.title)}"
        reference = KNOWN_AUDIO_REFERENCES.get(spec.title)
        entries.append({
            "id": entry_id,
            "series": spec.series,
            "trackNumber": spec.number,
            "title": spec.title,
            "aliases": aliases_for_values(
                spec.series,
                spec.number,
                spec.title,
                spec.aliases,
            ),
            "contentFingerprints": [reference.fingerprint] if reference else [],
            "role": spec.role,
            "seedProfile": spec.seed_profile,
            "creator": "Bambi Prime",
            "sourceKind": spec.source_kind,
            "sourceDocument": spec.source_document or spec.source_url,
            "sourceURL": spec.source_url,
            "transcript": "",
            "goldLightScore": build_gold_light_score(
                entry_id,
                spec,
                "",
            ),
        })
    return entries


def main() -> int:
    if not SOURCE_ROOT.exists():
        print(f"Source folder not found: {SOURCE_ROOT}", file=sys.stderr)
        return 1

    entries: list[dict[str, object]] = []
    for document in DOCUMENTS:
        path = TRANSCRIPT_ROOT / document.filename
        if not path.exists():
            print(f"Source PDF not found: {path}", file=sys.stderr)
            return 1
        entries.extend(extract_tracks(document, extract_document_text(path)))
    entries.extend(build_gold_only_entries())
    entries.sort(key=lambda entry: (
        str(entry["series"]),
        str(entry["trackNumber"]),
        str(entry["title"]),
    ))

    ids = [entry["id"] for entry in entries]
    if len(ids) != len(set(ids)):
        raise ValueError("Generated catalog contains duplicate IDs")
    fingerprints = [
        fingerprint
        for entry in entries
        for fingerprint in entry["contentFingerprints"]
    ]
    if len(fingerprints) != len(set(fingerprints)):
        raise ValueError("Generated catalog contains duplicate content fingerprints")
    if any(re.fullmatch(r"[0-9a-f]{64}", fingerprint) is None for fingerprint in fingerprints):
        raise ValueError("Generated catalog contains an invalid SHA-256 fingerprint")

    expected_titles = {
        spec.title
        for document in DOCUMENTS
        for spec in document.tracks
    } | {spec.title for spec in GOLD_ONLY_TRACKS}
    if expected_titles != set(GOLD_SCORE_SPECS):
        missing = sorted(expected_titles - set(GOLD_SCORE_SPECS))
        unexpected = sorted(set(GOLD_SCORE_SPECS) - expected_titles)
        raise ValueError(
            f"Gold-score specification mismatch; missing={missing}, unexpected={unexpected}"
        )

    payload = {
        "schemaVersion": 1,
        "sourceNotice": (
            "Community-maintained transcripts supplied by the app developer. "
            "They are not represented as official or verbatim. Versioned gold "
            "light scores are derived from reviewed track intent, transcript "
            "evidence, supplied reference-audio timing, and documented playlist "
            "placement. Local model transcripts used for review are not bundled."
        ),
        "entries": entries,
    }
    OUTPUT_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(entries)} entries to {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
