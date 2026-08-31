#!/usr/bin/env bash
#
# run-tests.sh — xcodebuild test, but the two silent failure modes are loud:
# a filter that matches nothing fails, and an unresolvable destination fails
# instead of hanging forever.
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

# A -destination naming a device that does not exist is not an error to
# xcodebuild — it waits for a matching device to appear, at 0% CPU, forever.
# Observed cost on first encounter: 52 minutes before anyone noticed. Bounding
# resolution turns that silent hang into a failure with a message. See
# ERRORS.md ERR-026.
#
# This bounds *resolving* the destination, not building or running, so it is
# safe to keep well below a real build's duration.
case " ${args[*]} " in
    *" -destination "*)
        case " ${args[*]} " in
            *" -destination-timeout "*) ;;
            *) args+=(-destination-timeout 120) ;;
        esac
        ;;
esac

# Simulator clones contend heavily for the same MainActor- and ML-driven
# pipeline tests. On this project parallel iOS runs abort after a rotating test
# hits its one-minute limit, while the complete serial suite finishes in under
# a minute. Respect an explicit caller choice; otherwise use the reliable
# default only for iOS Simulator destinations. See ERRORS.md ERR-028.
case " ${args[*]} " in
    *"platform=iOS Simulator"*)
        case " ${args[*]} " in
            *" -parallel-testing-enabled "*) ;;
            *) args+=(-parallel-testing-enabled NO) ;;
        esac
        ;;
esac

log="$(mktemp -t ilumionate-tests.XXXXXX)"
trap 'rm -f "$log"' EXIT

xcodebuild "${args[@]}" test 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"

# Two mutually exclusive output formats. Parallel runs print XCTest-style
# "Test case ..." lines; serial runs (-parallel-testing-enabled NO) print Swift
# Testing's own summary instead and no "Test case" lines at all. Counting only
# the first made every serial run look like it executed nothing, which tripped
# the zero-test guard below on a fully passing suite. See ERRORS.md ERR-030.
executed="$(grep -c '^Test case ' "$log" || true)"
swift_testing="$(sed -n 's/.*Test run with \([0-9]\{1,\}\) tests\{0,1\} in .*/\1/p' "$log" | tail -1)"
if [ -n "$swift_testing" ]; then
    executed=$((executed + swift_testing))
fi

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

if [ "$status" -ne 0 ] && grep -q "Unable to find a device matching\|Timed out waiting for a destination" "$log"; then
    cat >&2 <<'EOF'

error: no device matched -destination, and xcodebuild gave up waiting.

Several simulators share one name across runtimes, so pin OS= explicitly.
List what this machine actually has:

    xcrun simctl list devices available | grep iPhone
EOF
fi

echo "Executed ${executed} test case(s)."
exit "$status"
