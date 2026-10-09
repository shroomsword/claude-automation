#!/usr/bin/env bash
# Undo scripts/new-unit.sh: stop and disable claude-rc@<name>.service, remove it from the user unit directory, and
# remove systemd/claude-rc@<name>.service and its README.md row.
#
# Usage: scripts/remove-unit.sh <name>
#
# The unit must exist in systemd/. If it is not installed, only the repository files are changed. Nothing is removed if
# the user manager cannot be reached or stopping the unit fails. Lingering is disabled once no other claude-rc unit is
# enabled, since lingering is per user and the others still need it.
set -euo pipefail

usage() {
    echo "usage: $0 <name>" >&2
    exit 2
}

die() {
    echo "$0: $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || usage
name=$1
[[ "$name" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "invalid name '$name': use only letters, digits, '_', '.', ':' and '-'"

cd "$(dirname "$0")/.."
unit_name=claude-rc@$name.service
unit=systemd/$unit_name
install_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
installed=$install_dir/$unit_name

[[ -f "$unit" ]] || die "$unit does not exist"
# Sessions started without logind (su, sudo, some ssh/cron setups) lack these; the user manager's socket is at a fixed path.
if [[ -z "${XDG_RUNTIME_DIR-}" && -d "/run/user/$(id -u)" ]]; then
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
fi
systemctl --user show-environment > /dev/null || die "cannot reach the user manager"

if [[ -e "$installed" ]]; then
    systemctl --user disable --now "$unit_name" || die "stopping and disabling $unit_name failed"
    rm "$installed"
    systemctl --user daemon-reload
    echo "stopped, disabled and uninstalled $unit_name"

    # The units are WantedBy=default.target, so an enabled one has a link here.
    others=("$install_dir"/default.target.wants/claude-rc@*.service)
    if [[ ! -e "${others[0]}" && ! -L "${others[0]}" ]] \
        && [[ "$(loginctl show-user "$(id -un)" --property=Linger --value)" == yes ]]; then
        if loginctl disable-linger; then
            echo "disabled lingering for $(id -un)"
        else
            # Finish removing the unit anyway: a rerun would no longer reach this step.
            echo "$0: disabling lingering failed; run 'loginctl disable-linger' yourself" >&2
            linger_failed=1
        fi
    fi
fi

tmp_readme=$(mktemp README.md.tmp.XXXXXX)
trap 'rm -f "$tmp_readme"' EXIT
PREFIX="| \`$unit\` |" awk 'index($0, ENVIRON["PREFIX"]) != 1' README.md > "$tmp_readme"
chmod 644 "$tmp_readme"
rm "$unit"
mv "$tmp_readme" README.md
echo "removed $unit and its README.md row"
[[ -z "${linger_failed-}" ]]
