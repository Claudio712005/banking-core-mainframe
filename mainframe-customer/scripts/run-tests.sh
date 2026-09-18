#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run-tests.sh - regression tests for mainframe-customer (LAB environment).
#
# Each suite starts from a clean copy of the data and compares against the
# golden files in tests/expected/<suite>/ (RC, RSPOUT.txt, SYSOUT.txt).
#
# Usage: scripts/run-tests.sh [--update]
# -----------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

mkdir -p "$ROOT/build"
"$ROOT/scripts/build.sh" > "$ROOT/build/build.log" 2>&1 || { cat "$ROOT/build/build.log"; exit 1; }

failures=0

# run_suite NAME REQUEST_FILE [CREDIT_MASTER_OVERRIDE]
run_suite() {
    local name="$1" requests="$2" credit_override="${3:-}"
    local work="$ROOT/build/test/$name"
    local expected="$ROOT/tests/expected/$name"

    rm -rf "$work"; mkdir -p "$work/data" "$expected"
    cp "$ROOT/data/CUSTMAST.dat" "$work/data/CUSTMAST.dat"
    cp "$ROOT/data/CREDMAST.dat" "$work/data/CREDMAST.dat"
    [[ -n "$credit_override" ]] && cp "$credit_override" "$work/data/CREDMAST.dat"

    "$ROOT/scripts/run.sh" --data-dir "$work/data" "$requests" "$work/RSPOUT.txt" \
        > "$work/SYSOUT.txt" 2>&1
    echo "$?" > "$work/RC"

    if $UPDATE; then
        cp "$work"/{RC,RSPOUT.txt,SYSOUT.txt} "$expected/"
        echo "UPDATED $name"
        return
    fi

    local suite_ok=true artifact
    for artifact in RC RSPOUT.txt SYSOUT.txt; do
        if ! diff -u "$expected/$artifact" "$work/$artifact" > "$work/$artifact.diff"; then
            suite_ok=false
            echo "--- $name: $artifact differs"
            cat "$work/$artifact.diff"
        fi
    done
    if $suite_ok; then
        echo "PASS $name (rc=$(cat "$work/RC"))"
    else
        echo "FAIL $name"
        failures=$((failures + 1))
    fi
}

run_suite functional "$ROOT/tests/requests/functional.req"
run_suite failsafe   "$ROOT/tests/requests/failsafe.req" "$ROOT/tests/data/CREDMAST-CORRUPT.dat"

[[ $failures -eq 0 ]] && echo "ALL SUITES PASSED" || echo "$failures SUITE(S) FAILED"
exit "$failures"
