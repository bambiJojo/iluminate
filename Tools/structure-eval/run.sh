#!/bin/sh
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
out=$(mktemp -d)
swiftc -O -o "$out/eval" \
    "$root"/Ilumionate/Structure/*.swift \
    "$root"/Tools/structure-harness/Shim.swift \
    "$root"/Tools/structure-eval/main.swift
"$out/eval" "$@"
