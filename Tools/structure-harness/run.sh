#!/bin/sh
# Compiles the real Structure sources with the harness shim and runs them.
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
out=$(mktemp -d)
swiftc -O -o "$out/harness" \
    "$root"/Ilumionate/Structure/*.swift \
    "$root"/Tools/structure-harness/Shim.swift \
    "$root"/Tools/structure-harness/main.swift
"$out/harness" "$@"
