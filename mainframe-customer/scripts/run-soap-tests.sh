#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run-soap-tests.sh - end-to-end tests of the SOAP service.
#
# Requires the container to be running (docker compose up -d mainframe-customer).
# Compares status + body of every envelope in tests/soap/envelopes with the
# golden files in tests/soap/expected.
#
# Usage: scripts/run-soap-tests.sh [--update]
# Env:   CUSTOMER_SERVICE_URL (default http://localhost:8081/customer-service)
# -----------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL="${CUSTOMER_SERVICE_URL:-http://localhost:8081/customer-service}"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

curl -fsS -o /dev/null "${URL}.wsdl" || { echo "ERROR: service not reachable at $URL"; exit 1; }

failures=0
work="$ROOT/build/soap"
mkdir -p "$work" "$ROOT/tests/soap/expected"

# case name : SOAPAction : envelope (defaults to <name>.xml)
CASES="
customer-active:GetCustomer:
customer-blocked:GetCustomer:
customer-not-found:GetCustomer:
customer-invalid-id:GetCustomer:
customer-namespaced:GetCustomer:
credit-available:GetCreditLimit:
credit-customer-blocked:GetCreditLimit:
credit-exhausted:GetCreditLimit:
credit-no-line:GetCreditLimit:
credit-usd:GetCreditLimit:
malformed-body:GetCustomer:
unknown-action:DeleteCustomer:customer-active
"

for entry in $CASES; do
    name="${entry%%:*}"
    rest="${entry#*:}"
    action="${rest%%:*}"
    envelope_name="${rest#*:}"
    [[ -n "$envelope_name" ]] || envelope_name="$name"
    envelope="$ROOT/tests/soap/envelopes/${envelope_name}.xml"

    {
        curl -sS -o "$work/$name.body" -w 'HTTP %{http_code}\n' \
            -H "SOAPAction: \"${action}\"" \
            -H 'Content-Type: text/xml; charset=utf-8' \
            --data-binary "@${envelope}" "$URL"
        cat "$work/$name.body"
    } > "$work/$name.out" 2>&1
    rm -f "$work/$name.body"

    if $UPDATE; then
        cp "$work/$name.out" "$ROOT/tests/soap/expected/$name.out"
        echo "UPDATED $name"
        continue
    fi
    if diff -u "$ROOT/tests/soap/expected/$name.out" "$work/$name.out" > "$work/$name.diff"; then
        echo "PASS $name"
    else
        echo "FAIL $name"
        cat "$work/$name.diff"
        failures=$((failures + 1))
    fi
done

# Transport rules enforced by the web server, not by COBOL.
check_status() {
    local name="$1" expected="$2"; shift 2
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' "$@")"
    if [[ "$code" == "$expected" ]]; then
        echo "PASS $name (HTTP $code)"
    else
        echo "FAIL $name (HTTP $code, expected $expected)"
        failures=$((failures + 1))
    fi
}

python3 - "$work" <<'PY'
import sys, pathlib
out = pathlib.Path(sys.argv[1]) / "oversized.xml"
out.write_text("<Envelope><Body><GetCustomer><customerId>0000000001</customerId>"
               "<padding>" + "x" * 9000 + "</padding></GetCustomer></Body></Envelope>")
PY

check_status get-not-allowed 403 "$URL"
check_status oversized-body 413 -X POST -H 'SOAPAction: "GetCustomer"' \
    -H 'Content-Type: text/xml' --data-binary "@$work/oversized.xml" "$URL"

if [[ $failures -eq 0 ]]; then
    echo "ALL SOAP TESTS PASSED"
else
    echo "$failures SOAP TEST(S) FAILED"
fi
exit "$failures"
