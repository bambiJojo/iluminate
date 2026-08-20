#!/usr/bin/env bash
#
# run-all-tests.sh — every test target in the project, in one command.
#
# The repository builds two apps from one project, and each has its own scheme.
# `Scripts/run-tests.sh` defaults to the Ilumionate scheme, which contains only
# IlumionateTests — so a green run there says nothing about LumeLabel. That gap
# went unnoticed long enough for LumeLabel to stop building entirely and take its
# 25 tests with it (ERR-018, ERR-019).
#
# LumeLabelTests cannot simply be added to the Ilumionate scheme: linking it
# there fails with "cannot link directly with 'SwiftUICore' because product being
# built is not an allowed client of it". Two schemes, one command.
#
# Usage — arguments are passed to every scheme, so a destination applies to all:
#
#   Scripts/run-all-tests.sh -destination 'platform=macOS,arch=arm64'
#

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
schemes=(Ilumionate LumeLabel)
failed=()

for scheme in "${schemes[@]}"; do
    echo ""
    echo "──────── ${scheme} ────────"
    if ! "${here}/run-tests.sh" -scheme "${scheme}" "$@"; then
        failed+=("${scheme}")
    fi
done

echo ""
if [ "${#failed[@]}" -eq 0 ]; then
    echo "All schemes passed: ${schemes[*]}"
    exit 0
fi

echo "Failed: ${failed[*]}" >&2
exit 1
