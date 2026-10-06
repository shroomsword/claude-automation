#!/usr/bin/env bash
# Test new-unit.sh and remove-unit.sh against a copy of the repository in a temporary directory, with HOME and
# XDG_CONFIG_HOME pointed at temporary directories and systemctl replaced by a stub that logs its arguments, so the real
# systemd/, README.md, installed units, user manager, and linger setting are never touched.
set -euo pipefail

cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/scripts" "$repo/systemd" "$tmp/bin" "$tmp/home/src/delve" "$tmp/other dir/100%"
cp scripts/new-unit.sh scripts/remove-unit.sh "$repo/scripts/"
cp systemd/claude-rc@.service systemd/claude-rc@delve.service "$repo/systemd/"
# The fixture README lists only the template and delve, so re-adding delve (appended last) restores it exactly.
grep -v '^| `systemd/claude-rc@' README.md > "$tmp/README.base"
{ grep -F '| `systemd/claude-rc@.service`' README.md; grep -F '| `systemd/claude-rc@delve.service`' README.md; } > "$tmp/rows"
awk -v rows="$tmp/rows" '{ print } /^\|---\|---\|$/ { while ((getline l < rows) > 0) print l }' "$tmp/README.base" > "$repo/README.md"
cp "$repo/README.md" "$tmp/README.expected"
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
installed="$XDG_CONFIG_HOME/systemd/user"
wants="$installed/default.target.wants"

# STUB_NO_MANAGER: no user manager is reachable. STUB_ACTIVE: every unit is active. STUB_FAIL: this subcommand fails.
cat > "$tmp/bin/systemctl" <<STUB
#!/bin/sh
echo "\$*" >> "$tmp/systemctl.log"
[ "\$1" = --user ] || exit 99
case "\$2" in
show-environment) [ -z "\$STUB_NO_MANAGER" ] ;;
is-active) [ -n "\$STUB_ACTIVE" ] ;;
"\$STUB_FAIL") exit 1 ;;
esac
STUB
# STUB_LINGER: the linger setting loginctl reports.
cat > "$tmp/bin/loginctl" <<STUB
#!/bin/sh
echo "loginctl \$*" >> "$tmp/systemctl.log"
case "\$1" in
show-user) echo "\${STUB_LINGER:-no}" ;;
"\$STUB_FAIL") exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/systemctl" "$tmp/bin/loginctl"
export PATH="$tmp/bin:$PATH"

status=0
fail() {
    echo "FAIL: $*" >&2
    status=1
}

# Runs a script in the copy with a fresh systemctl log; succeeds only if the exit status matches the second argument.
expect() {
    local script=$1 want=$2
    shift 2
    local got=0
    : > "$tmp/systemctl.log"
    "$repo/scripts/$script" "$@" > "$tmp/stdout" 2> "$tmp/stderr" || got=$?
    if [[ "$want" == ok && "$got" -ne 0 ]] || [[ "$want" == err && "$got" -eq 0 ]]; then
        fail "$script $* exited $got, expected $want: $(cat "$tmp/stderr")"
        return 1
    fi
}

# Checks the mutating systemctl and loginctl calls of the last run, ignoring the read-only checks.
expect_calls() {
    local actual
    actual=$(grep -vE '^(--user (show-environment|is-active)|loginctl show-user)' "$tmp/systemctl.log" || true)
    [[ "$actual" == "$1" ]] || fail "systemctl calls: expected '$1', got '$actual'"
}

# Snapshot of everything the scripts may change, to check that a failed run changed nothing.
snapshot() {
    (cd "$tmp" && find repo config -type f -print0 | sort -z | xargs -0 sha256sum)
}

unchanged() {
    [[ "$(snapshot)" == "$before" ]] || fail "$1 changed files"
}

# remove-unit.sh on an installed unit disables and stops it, then removes it everywhere.
mkdir -p "$installed"
cp systemd/claude-rc@delve.service "$installed/"
if STUB_LINGER=yes expect remove-unit.sh ok delve; then
    expect_calls $'--user disable --now claude-rc@delve.service\n--user daemon-reload\nloginctl disable-linger'
    [[ ! -e "$installed/claude-rc@delve.service" ]] || fail "installed delve unit not removed"
    [[ ! -e "$repo/systemd/claude-rc@delve.service" ]] || fail "delve unit not removed from systemd/"
    ! grep -qF 'claude-rc@delve.service` |' "$repo/README.md" || fail "delve row not removed from README.md"
fi

# new-unit.sh recreates exactly what was removed: the delve unit, its README row, and the installed copy.
if expect new-unit.sh ok delve "$HOME/src/delve"; then
    expect_calls $'--user daemon-reload\n--user enable --now claude-rc@delve.service\nloginctl enable-linger'
    diff -u systemd/claude-rc@delve.service "$repo/systemd/claude-rc@delve.service" || fail "delve unit differs"
    diff -u systemd/claude-rc@delve.service "$installed/claude-rc@delve.service" || fail "installed delve unit differs"
    diff -u "$tmp/README.expected" "$repo/README.md" || fail "README.md differs"
fi

# A relative directory is made absolute; spaces are kept and % is escaped as %% in the unit but not in the README.
if (cd "$tmp" && STUB_LINGER=yes expect new-unit.sh ok other "other dir/100%"); then
    expect_calls $'--user daemon-reload\n--user enable --now claude-rc@other.service'
    grep -qxF "WorkingDirectory=$tmp/other dir/100%%" "$repo/systemd/claude-rc@other.service" \
        || fail "WorkingDirectory not absolute or not escaped"
    grep -qxF "| \`systemd/claude-rc@other.service\` | \`$tmp/other dir/100%\` |" "$repo/README.md" \
        || fail "README row for other missing or wrong"
fi

# remove-unit.sh keeps lingering while another claude-rc unit is enabled.
mkdir -p "$wants"
ln -s ../claude-rc@delve.service "$wants/claude-rc@delve.service"
if STUB_LINGER=yes expect remove-unit.sh ok other; then
    expect_calls $'--user disable --now claude-rc@other.service\n--user daemon-reload'
fi
expect new-unit.sh ok other "$tmp/other dir/100%"

# remove-unit.sh on a unit that was never installed only removes it from the repository.
rm "$installed/claude-rc@other.service"
if STUB_LINGER=yes expect remove-unit.sh ok other; then
    expect_calls ''
    [[ ! -e "$repo/systemd/claude-rc@other.service" ]] || fail "other unit not removed from systemd/"
    ! grep -qF 'claude-rc@other.service' "$repo/README.md" || fail "other row not removed from README.md"
fi

# Failures before anything is written change nothing.
mkdir "$tmp/back\\slash" "$tmp/pi|pe" "$tmp/back\`tick" "$tmp/new"$'\n'"line"
before=$(snapshot)
for args in "" "onlyname" "a $HOME extra" "a/b $HOME" "a%i $HOME" "missing $tmp/does-not-exist" \
    "x $tmp/back\\slash" "x $tmp/pi|pe" "x $tmp/back\`tick"; do
    # shellcheck disable=SC2086 # split into arguments on purpose; none of these contain spaces
    expect new-unit.sh err $args
done
expect new-unit.sh err "" "$HOME"
expect new-unit.sh err "a b" "$HOME"
expect new-unit.sh err x "$tmp/new"$'\n'"line"
expect new-unit.sh err delve "$HOME/src/delve"
cp systemd/claude-rc@delve.service "$installed/claude-rc@stray.service"
before=$(snapshot)
expect new-unit.sh err stray "$HOME"
STUB_NO_MANAGER=1 expect new-unit.sh err fresh "$HOME"
STUB_ACTIVE=1 expect new-unit.sh err fresh "$HOME"
expect remove-unit.sh err
expect remove-unit.sh err a b
expect remove-unit.sh err "a/b"
expect remove-unit.sh err missing
expect remove-unit.sh err ""
STUB_NO_MANAGER=1 expect remove-unit.sh err delve
STUB_FAIL=disable expect remove-unit.sh err delve
unchanged "failed runs"
[[ -z "$(find "$repo" -name '*.tmp*')" ]] || fail "temporary files left behind"

# A lingering failure is reported, but the unit is still removed everywhere.
expect new-unit.sh ok solo "$HOME"
rm "$wants/claude-rc@delve.service"
if STUB_LINGER=yes STUB_FAIL=disable-linger expect remove-unit.sh err solo; then
    expect_calls $'--user disable --now claude-rc@solo.service\n--user daemon-reload\nloginctl disable-linger'
    unchanged "remove-unit.sh with a lingering failure"
fi
ln -s ../claude-rc@delve.service "$wants/claude-rc@delve.service"

# A systemctl failure after the unit is written is reported, and remove-unit.sh cleans up the result.
if STUB_FAIL=enable expect new-unit.sh err late "$HOME"; then
    grep -qF 'remove-unit.sh late' "$tmp/stderr" || fail "failed new-unit.sh does not point at remove-unit.sh"
    expect remove-unit.sh ok late
    unchanged "new-unit.sh then remove-unit.sh"
fi

[[ $status -eq 0 ]] && echo "ok: new-unit.sh and remove-unit.sh"
exit $status
