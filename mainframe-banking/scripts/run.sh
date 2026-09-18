#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run.sh - executes the batch driver BKBATDRV locally (LAB environment).
#
# This script plays the role of the JCL: it binds logical DD names to files
# through DD_<name> environment variables, which GnuCOBOL resolves for
# "ASSIGN TO <name>".
#
# Usage:
#   scripts/run.sh [--reset] [--data-dir DIR] REQUEST_FILE RESPONSE_FILE
#
#   --reset         copy the baseline data (data/) into DIR before running
#   --data-dir DIR  runtime data directory (default: build/data). The baseline
#                   in data/ is never modified.
#
# Exit status: the driver return code (0, 4, 12, 16).
# -----------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/bin"
DATA_DIR="$ROOT/build/data"
RESET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reset)    RESET=true; shift ;;
        --data-dir) DATA_DIR="$2"; shift 2 ;;
        -h|--help)  sed -n '2,17p' "$0"; exit 0 ;;
        *)          break ;;
    esac
done

if [[ $# -ne 2 ]]; then
    echo "usage: $0 [--reset] [--data-dir DIR] REQUEST_FILE RESPONSE_FILE" >&2
    exit 16
fi
REQUEST_FILE="$1"
RESPONSE_FILE="$2"

[[ -x "$BIN/BKBATDRV" ]] || { echo "ERROR: build first (scripts/build.sh)" >&2; exit 16; }
[[ -f "$REQUEST_FILE" ]] || { echo "ERROR: request file not found: $REQUEST_FILE" >&2; exit 16; }

mkdir -p "$DATA_DIR"
if $RESET || [[ ! -f "$DATA_DIR/ACCTMAST.dat" ]]; then
    cp "$ROOT/data/accounts/ACCTMAST.dat"     "$DATA_DIR/ACCTMAST.dat"
    cp "$ROOT/data/transactions/TRXJRNL.dat"  "$DATA_DIR/TRXJRNL.dat"
fi
mkdir -p "$(dirname "$RESPONSE_FILE")"

# Module search path (equivalent of STEPLIB / JOBLIB).
export COB_LIBRARY_PATH="$BIN"

# A line longer than the record is ONE malformed record (status 04, rejected
# with 1001). Never let GnuCOBOL split its tail into an extra "request".
export COB_LS_SPLIT=FALSE

# DD statements. ACCTWORK must live on the same file system as ACCTMAST so
# the rename that commits an update is atomic.
export DD_ACCTMAST="$DATA_DIR/ACCTMAST.dat"
export DD_ACCTWORK="$DATA_DIR/ACCTMAST.new"
export DD_TRXJRNL="$DATA_DIR/TRXJRNL.dat"
export DD_REQIN="$REQUEST_FILE"
export DD_RSPOUT="$RESPONSE_FILE"

"$BIN/BKBATDRV"
