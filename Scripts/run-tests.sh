#!/usr/bin/env bash
#
# run-tests.sh — xcodebuild test, but a filter that matches nothing fails.
#
# `xcodebuild -only-testing:` with a Swift Testing function name that is missing
# its trailing "()" matches no tests, runs none, and still exits 0 printing
# "** TEST SUCCEEDED **". A failing test then reads as passing, which is how a
# red TDD step gets accepted as green. See ERRORS.md ERR-002.
#
# Swift Testing identifiers end in "()"; XCTest method names do not:
#
#   -only-testing:IlumionateTests/MyTests/myTest()   runs the test
#   -only-testing:IlumionateTests/MyTests/myTest     matches nothing, "succeeds"
#
# Suite-level filters (…/MyTests) always work and are the safer habit.
#
# Usage — any xcodebuild test arguments are passed straight through. The
# project and scheme default to this repo's, and are only added when absent:
#
#   Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' \
#       -only-testing:IlumionateTests
#

set -uo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: $0 [xcodebuild test arguments]" >&2
    exit 64
fi

args=("$@")

case " ${args[*]} " in
    *" -project "*|*" -workspace "*) ;;
    *) args=(-project Ilumionate.xcodeproj "${args[@]}") ;;
esac

case " ${args[*]} " in
    *" -scheme "*) ;;
    *) args=(-scheme Ilumionate "${args[@]}") ;;
esac

log="$(mktemp -t ilumionate-tests.XXXXXX)"
trap 'rm -f "$log"' EXIT

xcodebuild "${args[@]}" test 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"

executed="$(grep -c '^Test case ' "$log" || true)"

if [ "$status" -eq 0 ] && [ "$executed" -eq 0 ]; then
    cat >&2 <<'EOF'

error: xcodebuild reported success but ran 0 test cases.

A -only-testing filter almost certainly matched nothing. Swift Testing
identifiers end in "()":

    -only-testing:IlumionateTests/MyTests/myTest()   runs the test
    -only-testing:IlumionateTests/MyTests/myTest     matches nothing

Filtering at suite level (-only-testing:IlumionateTests/MyTests) always works.
EOF
    exit 1
fi

echo "Executed ${executed} test case(s)."
exit "$status"
