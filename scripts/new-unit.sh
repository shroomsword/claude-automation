#!/usr/bin/env bash
# Create systemd/claude-rc@<name>.service from the claude-rc@ template, running `claude rc` in <directory>, list it in
# README.md, install it as a user unit, and enable and start it. Lingering is enabled for the user, if it is not already,
# so the unit runs without a login session.
#
# Usage: scripts/new-unit.sh <name> <directory>
#
# The directory must exist; a relative one is made absolute. A directory under $HOME is written with %h, so the unit
# works for whoever installs it. Everything is checked before anything is written: the unit must not exist in systemd/
# or the user unit directory, and must not be active. scripts/remove-unit.sh undoes this script.
set -euo pipefail

usage() {
    echo "usage: $0 <name> <directory>" >&2
    exit 2
}

die() {
    echo "$0: $*" >&2
    exit 1
}

[[ $# -eq 2 ]] || usage
name=$1
dir=$2

# Restricted to characters systemd accepts in a unit name that need no escaping in the unit file.
[[ "$name" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "invalid name '$name': use only letters, digits, '_', '.', ':' and '-'"
# A newline breaks the unit file, a backslash may be read as an escape, and | or ` break the README table row.
[[ "$dir" != *[$'\n'\\\|\`]* ]] || die "directory '$dir' contains a newline, '\\', '|' or '\`', which are not supported"
[[ -d "$dir" ]] || die "directory '$dir' does not exist"
dir=$(cd "$dir" && pwd)

shown=$dir
working_dir=${dir//%/%%}
if [[ "$dir" == "$HOME" || "$dir" == "$HOME"/* ]]; then
    shown="~${dir#"$HOME"}"
    working_dir="%h${working_dir#"${HOME//%/%%}"}"
fi

cd "$(dirname "$0")/.."
template=systemd/claude-rc@.service
unit_name=claude-rc@$name.service
unit=systemd/$unit_name
install_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
row="| \`$unit\` | \`$shown\` |"

[[ ! -e "$unit" ]] || die "$unit already exists"
[[ ! -e "$install_dir/$unit_name" ]] || die "$install_dir/$unit_name already exists"
# Sessions started without logind (su, sudo, some ssh/cron setups) lack these; the user manager's socket is at a fixed path.
if [[ -z "${XDG_RUNTIME_DIR-}" && -d "/run/user/$(id -u)" ]]; then
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
fi
systemctl --user show-environment > /dev/null || die "cannot reach the user manager"
! systemctl --user is-active --quiet "$unit_name" || die "$unit_name is already running; stop it first"
last_row=$(grep -n '^| `systemd/' README.md | tail -n 1 | cut -d: -f1)
[[ -n "$last_row" ]] || die "README.md has no unit table to add $unit_name to"

tmp_unit=$(mktemp "$unit.tmp.XXXXXX")
tmp_readme=$(mktemp README.md.tmp.XXXXXX)
trap 'rm -f "$tmp_unit" "$tmp_readme"' EXIT

# Replace the template's header comment, swap its CLAUDE_RC_ROOT lookup for WorkingDirectory=, and run claude by its
# absolute path, since ExecStart= without a shell does not search the PATH set in the unit.
NAME=$name SHOWN=$shown WORKING_DIR=$working_dir awk '
    NR == 1 && /^#/ { header = 1 }
    header {
        if (/^#/) next
        header = 0
        print "# Runs `claude rc` in " ENVIRON["SHOWN"] "."
        print "#"
        print "# Usage: systemctl --user enable --now claude-rc@" ENVIRON["NAME"] ".service"
    }
    /^Environment=CLAUDE_RC_ROOT=/ { print "WorkingDirectory=" ENVIRON["WORKING_DIR"]; root = 1; next }
    /^EnvironmentFile=/ || /^# WorkingDirectory=/ { next }
    /^ExecStart=/ { print "ExecStart=%h/.local/bin/claude rc"; exec = 1; next }
    { gsub(/%i/, ENVIRON["NAME"]); print }
    END { if (!root || !exec) exit 1 }
' "$template" > "$tmp_unit" || die "$template no longer has the CLAUDE_RC_ROOT and ExecStart= lines this script replaces"
ROW=$row LAST=$last_row awk '{ print } NR == ENVIRON["LAST"] { print ENVIRON["ROW"] }' README.md > "$tmp_readme"
chmod 644 "$tmp_unit" "$tmp_readme"

mv "$tmp_unit" "$unit"
mv "$tmp_readme" README.md
echo "created $unit and added it to README.md"

{
    mkdir -p "$install_dir" &&
        cp "$unit" "$install_dir/" &&
        systemctl --user daemon-reload &&
        systemctl --user enable --now "$unit_name"
} || die "installing $unit_name failed; fix the cause and rerun, after undoing with: scripts/remove-unit.sh $name"
echo "installed, enabled and started $unit_name"

if [[ "$(loginctl show-user "$(id -un)" --property=Linger --value)" != yes ]]; then
    loginctl enable-linger || die "enabling lingering failed; $unit_name only runs while you are logged in"
    echo "enabled lingering for $(id -un)"
fi
