#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build.sh - compiles mainframe-banking with GnuCOBOL (LAB environment).
#
#   Subprograms -> dynamically loadable modules (build/bin/*.so|*.dylib),
#                  the local equivalent of a z/OS load library with DYNAM.
#   BKBATDRV    -> executable main program (build/bin/BKBATDRV).
#
# Usage: scripts/build.sh
# Env:   COBC      compiler binary      (default: cobc)
#        COBC_STD  GnuCOBOL dialect     (default: ibm)
# -----------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/bin"
COBC="${COBC:-cobc}"
COBC_STD="${COBC_STD:-ibm}"
COBC_FLAGS=(-std="$COBC_STD" -Wall -fixed -I "$ROOT/copybooks")

command -v "$COBC" >/dev/null || { echo "ERROR: $COBC not found (install GnuCOBOL 3.x)"; exit 1; }

# Fixed-format source must not use columns 73-80 (ignored by the compiler on
# z/OS and silently truncated). Fail fast instead of producing wrong code.
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

# Order is irrelevant for dynamic calls; listed bottom-up for readability.
MODULES=(
    programs/common/BKVALID.cbl
    programs/common/BKRESP.cbl
    programs/common/ACCTDAO.cbl
    programs/common/TRXDAO.cbl
    programs/common/ACCTPOST.cbl
    programs/account/ACCTINQ.cbl
    programs/account/ACCTDEP.cbl
    programs/account/ACCTWDR.cbl
    programs/transaction/TRXINQ.cbl
)

for src in "${MODULES[@]}"; do
    name="$(basename "$src" .cbl)"
    echo "cobc -m  $src"
    "$COBC" -m "${COBC_FLAGS[@]}" -o "$BIN/$name.$MODULE_EXT" "$ROOT/$src"
done

echo "cobc -x  programs/driver/BKBATDRV.cbl"
"$COBC" -x "${COBC_FLAGS[@]}" -o "$BIN/BKBATDRV" "$ROOT/programs/driver/BKBATDRV.cbl"

echo "BUILD OK -> $BIN"
