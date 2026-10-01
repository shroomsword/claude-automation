#!/usr/bin/env bash
# Start an instance of claude-rc@.service under the user manager and check that it runs `claude rc` in
# $CLAUDE_RC_ROOT/<instance>.
#
# The template is installed under a separate name in the runtime unit directory, with a drop-in that points PATH at a
# stub claude and CLAUDE_RC_ROOT at a temporary directory, so an installed claude-rc@ unit and the real claude are
# never touched. Requires a running user manager (XDG_RUNTIME_DIR set).
set -euo pipefail

cd "$(dirname "$0")/.."
: "${XDG_RUNTIME_DIR:?no user manager: XDG_RUNTIME_DIR is not set}"

name=claude-rc-test
instance=project
unit_dir="$XDG_RUNTIME_DIR/systemd/user"
tmp=$(mktemp -d)

cleanup() {
    systemctl --user stop "$name@$instance.service" 2>/dev/null || true
    rm -rf "$unit_dir/$name@.service" "$unit_dir/$name@$instance.service.d" "$tmp"
    systemctl --user daemon-reload
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/root/$instance" "$unit_dir/$name@$instance.service.d"
cat > "$tmp/bin/claude" <<STUB
#!/bin/sh
echo "\$PWD \$*" > "$tmp/out"
exec sleep infinity
STUB
chmod +x "$tmp/bin/claude"

cp systemd/claude-rc@.service "$unit_dir/$name@.service"
cat > "$unit_dir/$name@$instance.service.d/test.conf" <<CONF
[Service]
EnvironmentFile=
Environment=CLAUDE_RC_ROOT=$tmp/root
Environment=PATH=$tmp/bin:/usr/bin:/bin
CONF
systemctl --user daemon-reload
systemctl --user start "$name@$instance.service"

for _ in $(seq 50); do
    [[ -s "$tmp/out" ]] && break
    sleep 0.2
done

expected="$tmp/root/$instance rc"
actual=$(cat "$tmp/out" 2>/dev/null || true)
if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected '$expected', got '$actual'" >&2
    systemctl --user status "$name@$instance.service" --no-pager >&2 || true
    exit 1
fi
systemctl --user is-active --quiet "$name@$instance.service"
echo "ok: claude rc ran in \$CLAUDE_RC_ROOT/$instance"
