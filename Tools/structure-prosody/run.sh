#!/bin/sh
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
out=$(mktemp -d)
swiftc -O -o "$out/prosody" \
    "$root"/Ilumionate/Structure/*.swift \
    "$root"/Ilumionate/ProsodyAnalyzer.swift \
    "$root"/Ilumionate/ProsodyAnalyzer+PauseDetection.swift \
    "$root"/Tools/structure-harness/Shim.swift \
    "$root"/Tools/structure-prosody/main.swift
"$out/prosody" "$@"
