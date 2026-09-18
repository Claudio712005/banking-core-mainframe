#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build.sh - compiles mainframe-customer with GnuCOBOL (LAB environment).
#
#   Subprograms -> dynamically loadable modules (build/bin/*.so|*.dylib)
#   CUSTDRV     -> batch driver used by the regression suite
#
# The SOAP adapter (CSTSOAP) needs the CGI wiring and is built by the
# container image, not here.
#
# Usage: scripts/build.sh
# Env:   COBC      compiler binary   (default: cobc)
#        COBC_STD  GnuCOBOL dialect  (default: ibm)
# -----------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/bin"
COBC="${COBC:-cobc}"
COBC_STD="${COBC_STD:-ibm}"
COBC_FLAGS=(-std="$COBC_STD" -Wall -fixed -I "$ROOT/copybooks")

command -v "$COBC" >/dev/null || { echo "ERROR: $COBC not found (install GnuCOBOL 3.x)"; exit 1; }

long_lines="$(awk 'length($0) > 72 { printf "%s:%d: %d columns\n", FILENAME, FNR, length($0) }' \
    "$ROOT"/copybooks/*.cpy "$ROOT"/programs/*/*.cbl)"
if [[ -n "$long_lines" ]]; then
    echo "ERROR: source lines beyond column 72:"
    echo "$long_lines"
    exit 1
fi

MODULE_EXT="$("$COBC" --info | awk -F': *' '/COB_MODULE_EXT/ { print $2; exit }')"
MODULE_EXT="${MODULE_EXT:-so}"

mkdir -p "$BIN"
rm -f "$BIN"/*

MODULES=(
    programs/common/CSTVAL.cbl
    programs/common/CSTRESP.cbl
    programs/common/CUSTDAO.cbl
    programs/common/CREDDAO.cbl
    programs/customer/CUSTINQ.cbl
    programs/credit/CRDINQ.cbl
)

for src in "${MODULES[@]}"; do
    name="$(basename "$src" .cbl)"
    echo "cobc -m  $src"
    "$COBC" -m "${COBC_FLAGS[@]}" -o "$BIN/$name.$MODULE_EXT" "$ROOT/$src"
done

echo "cobc -x  programs/driver/CUSTDRV.cbl"
"$COBC" -x "${COBC_FLAGS[@]}" -o "$BIN/CUSTDRV" "$ROOT/programs/driver/CUSTDRV.cbl"

echo "BUILD OK -> $BIN"
