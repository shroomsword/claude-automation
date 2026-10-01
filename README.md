# claude-automation

[![CI](https://github.com/shroomsword/claude-automation/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/shroomsword/claude-automation/actions/workflows/ci.yml?query=branch%3Amain)

systemd user units that keep `claude rc` (Claude Code remote control) running in project directories, so sessions can
be started from claude.ai or the Claude mobile app.

## Units

| Unit | Runs `claude rc` in |
|---|---|
| `systemd/claude-rc@.service` | `$CLAUDE_RC_ROOT/<instance>`, where `CLAUDE_RC_ROOT` defaults to `~/src` |
| `systemd/claude-rc@delve.service` | `~/src/delve` |

Both expect `claude` at `~/.local/bin/claude`, restart 10 seconds after a failure, and start with the user manager.

To use a different project root for the template, set it in `~/.config/claude-rc/env`:

```sh
CLAUDE_RC_ROOT=/path/to/projects
```

A concrete unit such as `claude-rc@delve.service` takes precedence over the template for its instance name, so the
template's root setting does not apply to it.

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
scripts/verify-units.sh     # systemd-analyze verify (needs ~/.local/bin/claude)
scripts/test-template.sh    # starts a template instance with a stub claude (needs a user manager)
scripts/check-readme.sh     # every unit is documented here
```
