#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run.sh - executes the batch driver CUSTDRV locally (LAB environment).
#
# Binds the logical DD names to files through DD_<name> environment variables,
# the same way the JCL would on z/OS.
#
# Usage:
#   scripts/run.sh [--reset] [--data-dir DIR] REQUEST_FILE RESPONSE_FILE
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
        -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
        *)          break ;;
    esac
done

if [[ $# -ne 2 ]]; then
    echo "usage: $0 [--reset] [--data-dir DIR] REQUEST_FILE RESPONSE_FILE" >&2
    exit 16
fi
REQUEST_FILE="$1"
RESPONSE_FILE="$2"

[[ -x "$BIN/CUSTDRV" ]] || { echo "ERROR: build first (scripts/build.sh)" >&2; exit 16; }
[[ -f "$REQUEST_FILE" ]] || { echo "ERROR: request file not found: $REQUEST_FILE" >&2; exit 16; }

mkdir -p "$DATA_DIR"
if $RESET || [[ ! -f "$DATA_DIR/CUSTMAST.dat" ]]; then
    cp "$ROOT/data/CUSTMAST.dat" "$DATA_DIR/CUSTMAST.dat"
    cp "$ROOT/data/CREDMAST.dat" "$DATA_DIR/CREDMAST.dat"
fi
mkdir -p "$(dirname "$RESPONSE_FILE")"

export COB_LIBRARY_PATH="$BIN"
export COB_LS_SPLIT=FALSE
export DD_CUSTMAST="$DATA_DIR/CUSTMAST.dat"
export DD_CREDMAST="$DATA_DIR/CREDMAST.dat"
export DD_REQIN="$REQUEST_FILE"
export DD_RSPOUT="$RESPONSE_FILE"

"$BIN/CUSTDRV"
