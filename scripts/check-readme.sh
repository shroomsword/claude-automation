#!/usr/bin/env bash
# Check that README.md documents every unit in systemd/.
set -euo pipefail

cd "$(dirname "$0")/.."
status=0
for unit in systemd/*.service; do
    name=$(basename "$unit")
    if ! grep -qF "$name" README.md; then
        echo "README.md does not mention $name" >&2
        status=1
    fi
done
exit $status
