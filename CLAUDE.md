# CLAUDE.md — SAKO Terminal Theme

Portable Fish + Starship theme with a Bash installer. Public repo
`Sako404/sako-terminal-theme`, AGPL-3.0-or-later.

## Rules

* **Single source of truth:** all colours/branding/font live in
  `config/theme.conf`. Templates in `config/templates/` use `@@KEY@@`
  placeholders. Never hard-code a palette value in a template or script.
* Generated files on the user's machine are artefacts; never commit
  rendered output.
* Installer = plan → confirm once → install deps → validate → backup →
  apply → verify in a fresh fish → auto-restore on failure. Keep that order.
* Never: `curl | bash`, AUR/COPR/PPA, `pacman -Sy`, changing the login
  shell, background services, telemetry, overwriting user-edited managed
  files without `--force`.
* Downloads only with a pinned version + SHA-256 in `lib/deps.sh`. When
  bumping, verify the hash against the upstream release checksum.
* Config files are parsed (`cfg_parse`), never `source`d.
* Write through symlinks (`atomic_write`), never replace them.

## Tests

```bash
tests/run.sh                       # unit/integration, isolated $HOME
SAKO_SHELLCHECK_DOCKER=1 tests/run.sh shellcheck
tests/docker.sh                    # real installs in distro containers
```

Tests must never write to the real `$HOME`. `tests/distro-test.sh` refuses
to run outside a container/CI.
