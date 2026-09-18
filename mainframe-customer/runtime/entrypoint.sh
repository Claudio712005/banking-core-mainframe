#!/usr/bin/env bash
set -euo pipefail

data_dir="${CUSTCORE_DATA_DIR:-/var/lib/custcore}"
mkdir -p "$data_dir"

for dataset in CUSTMAST CREDMAST; do
    target="$data_dir/$dataset.dat"
    if [[ ! -f "$target" ]]; then
        cp "/opt/custcore/baseline/$dataset.dat" "$target"
        echo "entrypoint: initialized $dataset.dat from baseline"
    fi
done

export DD_CUSTMAST="$data_dir/CUSTMAST.dat"
export DD_CREDMAST="$data_dir/CREDMAST.dat"

exec apache2 -f /opt/custcore/httpd.conf -DFOREGROUND
