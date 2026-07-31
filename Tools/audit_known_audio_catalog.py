#!/usr/bin/env python3
"""Fail-fast quality gates for the bundled known-audio gold catalog.

Run from the repository root:

    python3 Tools/audit_known_audio_catalog.py

The audit is intentionally independent from the catalog builder. It checks the
generated resource, resolves every supplied local audio file by both canonical
name and SHA-256 fingerprint, compares reference and media durations, and
enforces the evidence, timeline, safety, and playlist-transition contracts that
qualify a score as gold.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import subprocess
import sys
import unicodedata
import uuid
from collections import Counter, defaultdict
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPOSITORY_ROOT / "Ilumionate" / "KnownAudioCatalog.json"
AUDIO_ROOT = REPOSITORY_ROOT / "doc"
EXPECTED_SCORE_VERSION = 2
MAX_FLASH_HZ = 40.0


class Audit:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def require(self, condition: bool, message: str) -> None:
        if not condition:
            self.failures.append(message)


def normalized_name(value: str) -> str:
    stem = Path(value).stem
    stem = (
        unicodedata.normalize("NFKD", stem)
        .encode("ascii", "ignore")
        .decode("ascii")
        .lower()
    )
    tokens = re.sub(r"[^a-z0-9]+", " ", stem).split()
    if tokens and tokens[0].isdigit() and 0 <= int(tokens[0]) <= 99:
        tokens.pop(0)
    disposable_suffixes = {
        "audio", "final", "hq", "official", "remastered",
        "mp3", "m4a", "wav", "v2", "320kbps",
    }
    while tokens and tokens[-1] in disposable_suffixes:
        tokens.pop()
    return " ".join(tokens)


def match_confidence(candidate: str, alias: str) -> float:
    if not alias:
        return 0
    if candidate == alias:
        return 1
    alias_tokens = alias.split()
    if len(alias_tokens) >= 3 and candidate.endswith(f" {alias}"):
        return 0.98
    candidate_tokens = set(candidate.split())
    expected_tokens = set(alias_tokens)
    if len(expected_tokens) < 3:
        return 0
    coverage = len(candidate_tokens & expected_tokens) / len(expected_tokens)
    extra_count = len(candidate_tokens - expected_tokens)
    return 0.92 if coverage == 1 and extra_count <= 4 else 0


def filename_matches(filename: str, entries: list[dict[str, object]]) -> list[dict[str, object]]:
    candidate = normalized_name(filename)
    matches = []
    for entry in entries:
        aliases = list(entry["aliases"]) + [entry["title"]]
        if any(match_confidence(candidate, normalized_name(alias)) >= 0.90 for alias in aliases):
            matches.append(entry)
    return matches


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def media_duration(path: Path) -> float:
    output = subprocess.check_output(
        [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=nw=1:nk=1",
            str(path),
        ],
        text=True,
    )
    return float(output.strip())


def finite_number(value: object) -> bool:
    return isinstance(value, (int, float)) and math.isfinite(float(value))


def audit_entry(entry: dict[str, object], audit: Audit) -> None:
    title = str(entry["title"])
    score = entry["goldLightScore"]
    moments = score["moments"]
    anchors = score["evidenceAnchors"]
    positions = [float(moment["position"]) for moment in moments]

    audit.require(score["scoreVersion"] == EXPECTED_SCORE_VERSION, f"{title}: stale score version")
    try:
        uuid.UUID(str(score["sessionID"]))
    except ValueError:
        audit.require(False, f"{title}: invalid score UUID")
    audit.require(bool(str(score["designIntent"]).strip()), f"{title}: empty design intent")
    audit.require(len(moments) >= 6, f"{title}: fewer than six control points")
    audit.require(positions[0] == 0 and positions[-1] == 1, f"{title}: timeline does not cover 0...1")
    audit.require(
        positions == sorted(positions) and len(positions) == len(set(positions)),
        f"{title}: moment positions are not strictly ordered",
    )

    for index, moment in enumerate(moments):
        prefix = f"{title}: moment {index}"
        frequency = moment["frequency"]
        intensity = moment["intensity"]
        audit.require(
            finite_number(frequency) and 0.1 <= float(frequency) <= MAX_FLASH_HZ,
            f"{prefix} frequency is outside 0.1...{MAX_FLASH_HZ} Hz",
        )
        audit.require(
            finite_number(intensity) and 0 <= float(intensity) <= 1,
            f"{prefix} intensity is outside 0...1",
        )
        if moment["rampDuration"] is not None:
            audit.require(
                finite_number(moment["rampDuration"]) and 0 <= float(moment["rampDuration"]) <= 30,
                f"{prefix} ramp duration is outside 0...30 seconds",
            )
        if moment["colorTemperature"] is not None:
            audit.require(
                finite_number(moment["colorTemperature"])
                and 2000 <= float(moment["colorTemperature"]) <= 6500,
                f"{prefix} color temperature is outside 2000...6500 K",
            )

    audit.require(
        score["transcriptAnchorCount"] == len(anchors),
        f"{title}: anchor count does not match evidence list",
    )
    for anchor in anchors:
        anchor_position = float(anchor["position"])
        audit.require(0 < anchor_position < 1, f"{title}: evidence anchor is outside the timeline")
        audit.require(bool(str(anchor["cue"]).strip()), f"{title}: evidence anchor has no cue")
        audit.require(
            any(abs(anchor_position - position) < 0.0001 for position in positions),
            f"{title}: evidence anchor has no matching control point",
        )

    evidence_kind = score["evidenceKind"]
    timing_basis = score["timingBasis"]
    if evidence_kind == "communityTranscript":
        audit.require(bool(str(entry["transcript"]).strip()), f"{title}: transcript evidence is empty")
        audit.require(len(anchors) >= 2, f"{title}: transcript-backed score has fewer than two anchors")
        audit.require(
            timing_basis in {"referenceAudio", "transcriptMarkers", "transcriptOrder"},
            f"{title}: transcript-backed score has an invalid timing basis",
        )
    elif evidence_kind == "localAudioReview":
        audit.require(len(anchors) >= 1, f"{title}: local audio review has no reviewed anchor")
        audit.require(
            timing_basis == "reviewedAudioTiming",
            f"{title}: local audio review is not tied to reviewed audio timing",
        )
    elif evidence_kind == "catalogMetadata":
        audit.require(timing_basis == "intentOnly", f"{title}: metadata-only score claims timed evidence")
        audit.require(not anchors, f"{title}: metadata-only score contains unsupported anchors")
    else:
        audit.require(False, f"{title}: unknown evidence kind {evidence_kind!r}")

    first_frequency = float(moments[0]["frequency"])
    last_frequency = float(moments[-1]["frequency"])
    placement = score["playlistPlacement"]
    if placement == "entry":
        audit.require(first_frequency >= 8, f"{title}: entry score does not start alert enough")
        audit.require(last_frequency <= 6.5, f"{title}: entry score does not hand off deep")
    elif placement in {"early", "earlyOrMiddle", "middle", "late"}:
        audit.require(first_frequency <= 7, f"{title}: middle score starts too alert")
        audit.require(last_frequency <= 7, f"{title}: middle score ends too alert")
    elif placement == "exit":
        audit.require(first_frequency <= 7, f"{title}: exit score does not accept a deep handoff")
        audit.require(last_frequency >= 10, f"{title}: exit score does not end alert")
    elif placement == "sleepExit":
        audit.require(last_frequency < 4, f"{title}: sleep exit does not end in delta")
    else:
        audit.require(False, f"{title}: unknown playlist placement {placement!r}")


def main() -> int:
    audit = Audit()
    document = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    entries = document["entries"]

    audit.require(document["schemaVersion"] == 1, "Unsupported catalog schema")
    ids = [entry["id"] for entry in entries]
    titles = [entry["title"] for entry in entries]
    session_ids = [entry["goldLightScore"]["sessionID"] for entry in entries]
    fingerprints = [
        fingerprint
        for entry in entries
        for fingerprint in entry["contentFingerprints"]
    ]
    audit.require(len(ids) == len(set(ids)), "Duplicate catalog IDs")
    audit.require(len(titles) == len(set(titles)), "Duplicate catalog titles")
    audit.require(len(session_ids) == len(set(session_ids)), "Duplicate gold score IDs")
    audit.require(len(fingerprints) == len(set(fingerprints)), "Duplicate content fingerprints")
    audit.require(
        all(re.fullmatch(r"[0-9a-f]{64}", fingerprint) for fingerprint in fingerprints),
        "Invalid SHA-256 content fingerprint",
    )

    for entry in entries:
        audit_entry(entry, audit)

    signature_groups: dict[str, list[str]] = defaultdict(list)
    for entry in entries:
        signature = json.dumps(
            entry["goldLightScore"]["moments"],
            sort_keys=True,
            separators=(",", ":"),
        )
        signature_groups[signature].append(entry["title"])
    duplicate_groups = [titles for titles in signature_groups.values() if len(titles) > 1]
    audit.require(not duplicate_groups, f"Distinct tracks share identical timelines: {duplicate_groups}")

    audio_files = sorted(AUDIO_ROOT.glob("*/*.mp3"))
    audit.require(bool(audio_files), f"No reference audio found under {AUDIO_ROOT}")
    fingerprint_index = {
        fingerprint: entry
        for entry in entries
        for fingerprint in entry["contentFingerprints"]
    }
    for audio_file in audio_files:
        digest = sha256(audio_file)
        fingerprint_entry = fingerprint_index.get(digest)
        name_matches = filename_matches(audio_file.name, entries)
        audit.require(
            fingerprint_entry is not None,
            f"{audio_file.relative_to(REPOSITORY_ROOT)}: fingerprint is absent from catalog",
        )
        audit.require(
            len(name_matches) == 1,
            f"{audio_file.relative_to(REPOSITORY_ROOT)}: filename resolves to {len(name_matches)} entries",
        )
        if fingerprint_entry is None or len(name_matches) != 1:
            continue
        audit.require(
            fingerprint_entry["id"] == name_matches[0]["id"],
            f"{audio_file.relative_to(REPOSITORY_ROOT)}: name and fingerprint resolve differently",
        )
        audit.require(
            fingerprint_entry["goldLightScore"]["evidenceKind"] != "catalogMetadata",
            f"{audio_file.relative_to(REPOSITORY_ROOT)}: supplied audio still has metadata-only evidence",
        )
        reference_duration = fingerprint_entry["goldLightScore"]["referenceDuration"]
        actual_duration = media_duration(audio_file)
        audit.require(
            reference_duration is not None and abs(float(reference_duration) - actual_duration) <= 0.25,
            f"{audio_file.relative_to(REPOSITORY_ROOT)}: reference duration differs from media",
        )

    if audit.failures:
        print(f"Gold catalog audit FAILED with {len(audit.failures)} issue(s):", file=sys.stderr)
        for failure in audit.failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    evidence_counts = Counter(
        entry["goldLightScore"]["evidenceKind"] for entry in entries
    )
    print(
        "Gold catalog audit passed: "
        f"{len(entries)} entries, {len(audio_files)} supplied audio files, "
        f"{len(fingerprints)} fingerprinted encodes, evidence={dict(evidence_counts)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
