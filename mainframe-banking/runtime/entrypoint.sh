#!/usr/bin/env bash
set -euo pipefail

data_dir="${BANKCORE_DATA_DIR:-/var/lib/bankcore}"
mkdir -p "$data_dir" "${MQ_OVERRIDE_DATA_PATH:-/tmp/mqclient}"

for dataset in accounts/ACCTMAST transactions/TRXJRNL; do
    target="$data_dir/$(basename "$dataset").dat"
    if [[ ! -f "$target" ]]; then
        cp "/opt/bankcore/baseline/$dataset.dat" "$target"
        echo "entrypoint: initialized $(basename "$target") from baseline"
    fi
done

export DD_ACCTMAST="$data_dir/ACCTMAST.dat"
export DD_ACCTWORK="$data_dir/ACCTMAST.new"
export DD_TRXJRNL="$data_dir/TRXJRNL.dat"

exec /opt/bankcore/bin/BKMQLSN
