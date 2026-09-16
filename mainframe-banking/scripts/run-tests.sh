#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run-tests.sh - regression tests for mainframe-banking (LAB environment).
#
# Each suite starts from a clean copy of the data, runs BKBATDRV with a fixed
# clock and compares against golden files in tests/expected/<suite>/:
#   RC            expected driver return code
#   RSPOUT.txt    response messages
#   SYSOUT.txt    driver/technical log output
#   ACCTMAST.dat  account master after the run
#   TRXJRNL.dat   transaction journal after the run
#
# Usage: scripts/run-tests.sh [--update]
#   --update  rewrite the golden files from the current output (review the
#             diff with git before committing!)
# -----------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

# GnuCOBOL test hook: FUNCTION CURRENT-DATE returns this fixed instant, so
# timestamps in responses and data files are reproducible.
export COB_CURRENT_DATE="2026/09/16 10:30:00.00"

mkdir -p "$ROOT/build"
"$ROOT/scripts/build.sh" > "$ROOT/build/build.log" 2>&1 || { cat "$ROOT/build/build.log"; exit 1; }

failures=0

# run_suite NAME REQUEST_FILE [ACCOUNT_MASTER_OVERRIDE]
run_suite() {
    local name="$1" requests="$2" master_override="${3:-}"
    local work="$ROOT/build/test/$name"
    local expected="$ROOT/tests/expected/$name"

    rm -rf "$work"; mkdir -p "$work/data" "$expected"
    cp "$ROOT/data/accounts/ACCTMAST.dat"    "$work/data/ACCTMAST.dat"
    cp "$ROOT/data/customers/CUSTMAST.dat"   "$work/data/CUSTMAST.dat"
    cp "$ROOT/data/transactions/TRXJRNL.dat" "$work/data/TRXJRNL.dat"
    [[ -n "$master_override" ]] && cp "$master_override" "$work/data/ACCTMAST.dat"

    "$ROOT/scripts/run.sh" --data-dir "$work/data" "$requests" "$work/RSPOUT.txt" \
        > "$work/SYSOUT.txt" 2>&1
    echo "$?" > "$work/RC"
    cp "$work/data/ACCTMAST.dat" "$work/data/TRXJRNL.dat" "$work/"

    if $UPDATE; then
        cp "$work"/{RC,RSPOUT.txt,SYSOUT.txt,ACCTMAST.dat,TRXJRNL.dat} "$expected/"
        echo "UPDATED $name"
        return
    fi

    local suite_ok=true artifact
    for artifact in RC RSPOUT.txt SYSOUT.txt ACCTMAST.dat TRXJRNL.dat; do
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
run_suite failsafe   "$ROOT/tests/requests/failsafe.req" "$ROOT/tests/data/ACCTMAST-CORRUPT.dat"

[[ $failures -eq 0 ]] && echo "ALL SUITES PASSED" || echo "$failures SUITE(S) FAILED"
exit "$failures"
