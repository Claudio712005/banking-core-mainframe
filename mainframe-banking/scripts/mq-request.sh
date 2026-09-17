#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# mq-request.sh - sends 200-byte request lines to a BANKCORE queue through
# IBM MQ and prints the COBOL replies (runs BKMQREQ inside the running
# mainframe-banking container started by docker compose).
#
# Usage: scripts/mq-request.sh OPERATION [REQUEST_FILE]
#   OPERATION     ACCTINQ | ACCTDEP | ACCTWDR | TRXINQ (selects the queue)
#   REQUEST_FILE  one request per line (default: stdin)
# -----------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
operation="${1:?usage: $0 ACCTINQ|ACCTDEP|ACCTWDR|TRXINQ [REQUEST_FILE]}"
input="${2:-/dev/stdin}"

case "$operation" in
    ACCTINQ|ACCTDEP|ACCTWDR|TRXINQ) ;;
    *) echo "unknown operation: $operation" >&2; exit 2 ;;
esac

docker compose -f "$ROOT/docker-compose.yaml" exec -T \
    -e BK_TARGET_QUEUE="BANKCORE.${operation}.REQUEST" \
    -e BK_REPLY_QUEUE="${BK_REPLY_QUEUE:-BANKCORE.REPLY.BANKSVC}" \
    -e DD_REQIN=/dev/stdin \
    mainframe-banking /opt/bankcore/bin/BKMQREQ < "$input"
