#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# soap-request.sh - sends one SOAP envelope to the customer service and prints
# the HTTP status followed by the response body.
#
# Usage: scripts/soap-request.sh ACTION ENVELOPE_FILE
#   ACTION         GetCustomer | GetCreditLimit (sent as SOAPAction)
#   ENVELOPE_FILE  SOAP envelope (default: stdin)
# Env: CUSTOMER_SERVICE_URL (default http://localhost:8081/customer-service)
# -----------------------------------------------------------------------------
set -uo pipefail

url="${CUSTOMER_SERVICE_URL:-http://localhost:8081/customer-service}"
action="${1:?usage: $0 ACTION [ENVELOPE_FILE]}"
envelope="${2:-/dev/stdin}"

curl -sS -o /tmp/soap-response.$$ -w 'HTTP %{http_code}\n' \
    -H "SOAPAction: \"${action}\"" \
    -H 'Content-Type: text/xml; charset=utf-8' \
    --data-binary "@${envelope}" \
    "$url"
status=$?
cat /tmp/soap-response.$$
rm -f /tmp/soap-response.$$
exit $status
