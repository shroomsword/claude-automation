#!/usr/bin/env bash
# Statically verify every unit in systemd/ with systemd-analyze.
#
# Units reference claude at ~/.local/bin/claude, which must exist (a stub is enough).
set -euo pipefail

cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for unit in systemd/*.service; do
    name=$(basename "$unit")
    # A template cannot be verified directly; verify an instance of it instead.
    if [[ "$name" == *@.service ]]; then
        cp "$unit" "$tmp/${name%@.service}@verify.service"
        unit="$tmp/${name%@.service}@verify.service"
    fi
    echo "verify: $name"
    systemd-analyze verify "$unit"
done
