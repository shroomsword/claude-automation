# claude-automation

[![CI](https://github.com/shroomsword/claude-automation/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/shroomsword/claude-automation/actions/workflows/ci.yml?query=branch%3Amain)

systemd user units that keep `claude rc` (Claude Code remote control) running in project directories, so sessions can
be started from claude.ai or the Claude mobile app.

## Units

| Unit | Runs `claude rc` in |
|---|---|
| `systemd/claude-rc@.service` | `$CLAUDE_RC_ROOT/<instance>`, where `CLAUDE_RC_ROOT` defaults to `~/src` |
| `systemd/claude-rc@delve.service` | `~/src/delve` |

All units expect `claude` at `~/.local/bin/claude`, restart 10 seconds after a failure, and start with the user manager.

To use a different project root for the template, set it in `~/.config/claude-rc/env`:

```sh
CLAUDE_RC_ROOT=/path/to/projects
```

A concrete unit such as `claude-rc@delve.service` takes precedence over the template for its instance name, so the
template's root setting does not apply to it.

## Adding a project

To give a project its own unit instead of using the template:

```sh
scripts/new-unit.sh myproject ~/src/myproject
```

This creates `systemd/claude-rc@myproject.service` from the template, adds it to the table above, copies it to
`~/.config/systemd/user/`, enables and starts it, and enables lingering so it keeps running without a login session.
The directory must exist. A directory under your home is written
with `%h`, so the unit works for any user who installs it. The script stops without changing anything if the unit
already exists or is running, or if the user manager can't be reached.

`scripts/remove-unit.sh myproject` undoes it: it stops, disables, and uninstalls the unit, then removes the unit file
and its table row. It disables lingering only when no other `claude-rc@` unit is still enabled; any other user services
that rely on lingering would stop too, so re-enable it with `loginctl enable-linger` if you need it.

## Install

```sh
mkdir -p ~/.config/systemd/user
cp systemd/*.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now claude-rc@delve.service    # or claude-rc@<project>.service
loginctl enable-linger "$USER"                           # keep running without a login session
```

Check on a unit with `systemctl --user status claude-rc@delve.service` and
`journalctl --user -u claude-rc@delve.service`.

## Checks

The CI checks are scripts that also run locally:

```sh
scripts/verify-units.sh       # systemd-analyze verify (needs ~/.local/bin/claude)
scripts/test-template.sh      # starts a template instance with a stub claude (needs a user manager)
scripts/check-readme.sh       # every unit is documented here
scripts/test-unit-scripts.sh  # new-unit.sh and remove-unit.sh, with a stub systemctl
```
