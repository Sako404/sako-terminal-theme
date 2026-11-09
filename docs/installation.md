# Installation, update, restore, uninstall

## Install

```bash
git clone https://github.com/Sako404/sako-terminal-theme.git
cd sako-terminal-theme
./install.sh            # or: ./install.sh --dry-run   to only see the plan
```

Run it as your normal user. It calls `sudo` only to install packages and
refuses to run under `sudo ./install.sh`.

What happens, in order:

1. Detects the distribution (`/etc/os-release`), package manager, privileges,
   session (local / SSH, GUI / no GUI) and the terminal emulator (process tree).
2. Works out what is missing: `fish`, `starship`, a Nerd Font, and helper tools
   (`curl`, `tar`, `gzip`, `xz`, `fontconfig`) only if a download is needed.
3. Renders the theme files from `config/theme.conf` (+ your `local.conf`).
4. Shows the whole plan and asks **once** (`--yes` skips the question).
5. Installs missing packages from the official repositories.
6. Validates the generated Starship config (TOML + Starship's own parser)
   and the Fish module syntax — before touching any file.
7. Backs up every file it is about to change, then writes the files atomically.
8. Verifies the result in a **new** Fish process: branding line, three
   prompt lines, autosuggestion colour, Starship prompt, single initialisation.
   If verification fails, the backup is restored automatically.

Installed files:

| File | Purpose |
|---|---|
| `~/.config/starship.toml` (or `$STARSHIP_CONFIG`) | The prompt |
| `~/.config/fish/conf.d/sako-theme.fish` | Autosuggestion colour, Starship init if `config.fish` does not do it |
| `~/.config/sako-terminal-theme/local.conf` | Your overrides (created once, never overwritten) |
| Konsole: `~/.local/share/konsole/SAKO.colorscheme` + `ColorScheme`/`Font` keys in your default profile | optional |
| Kitty: `~/.config/kitty/sako-theme.conf` + an `include` block in `kitty.conf` | optional |
| Alacritty: `~/.config/alacritty/sako-theme.toml` + `general.import` block | optional |
| WezTerm: `~/.config/wezterm/colors/SAKO.toml` (+ `wezterm.lua` only if you had none) | optional |

State (manifest, backups, installed version): `~/.local/state/sako-terminal-theme/`.

### Dependencies per distribution

| Family | Fish | Starship | Nerd Font |
|---|---|---|---|
| CachyOS, Arch, EndeavourOS, Manjaro (`pacman`) | `fish` | `starship` | `ttf-jetbrains-mono-nerd` |
| Debian, Ubuntu, Mint (`apt`) | `fish` | `starship` if the release has it, else the verified release | verified release → `~/.local/share/fonts/sako-terminal-theme` |
| Fedora (`dnf`) | `fish` | `starship` if available, else the verified release | verified release |

No AUR, COPR or PPA is ever used. The installer never runs `pacman -Sy`
(partial upgrades); if the package database is too old, run `sudo pacman -Syu`
first. Without `sudo`, Starship and the font can still be installed into your
home directory; Fish cannot, so the installer stops and tells you what to install.

### Nerd Font

JetBrains Mono Nerd Font, *NL* variant (no ligatures). Reasons: it is in the
official Arch repositories, it is one of the most widely used Nerd Fonts, it
has every glyph the prompt uses (Powerline separators, Font Awesome and
Material Design icons), and it was already the font of the original SAKO
Konsole profile.

The font is skipped when there is no graphical session: over SSH the glyphs
are drawn by the **client's** terminal, so install a Nerd Font on the machine
you connect from. `--font` forces installation, `--no-font` disables it.

## Without git

Download a release archive and its checksum file with `curl` (or `wget`),
check it, unpack it — only `tar` and `gzip` are needed:

```bash
v=1.0.0
curl -fLO "https://github.com/Sako404/sako-terminal-theme/releases/download/v$v/sako-terminal-theme-$v.tar.gz"
curl -fLO "https://github.com/Sako404/sako-terminal-theme/releases/download/v$v/SHA256SUMS"
sha256sum -c SHA256SUMS
tar -xzf "sako-terminal-theme-$v.tar.gz"
cd "sako-terminal-theme-$v"
./install.sh
```

The checksum detects a corrupted or truncated download. It comes from the
same GitHub release, so it does not protect against a compromised GitHub
account; compare it with the sum shown on the release page if that matters.
A copy installed this way cannot run `update.sh`: download the next release
the same way and run its `./install.sh` (your `local.conf` and backups stay
in your home directory).

## Update

```bash
cd sako-terminal-theme
./update.sh            # --check only reports; --yes passes --yes to install.sh
```

The updater stops if the checkout has local changes, fetches, fast-forwards
only (no merges, no `reset --hard`), then runs `install.sh`, which backs up
and updates the managed files and keeps your `local.conf` and any managed
file you edited. If installing fails, the checkout is moved back to the
previous commit with `git reset --keep`. Nothing runs automatically in the
background.

## Diagnose

```bash
scripts/doctor.sh
```

Read-only. Checks the programs, the active Starship config, the branding,
the old slogan, the three-line layout, Git segments in a temporary
repository, the autosuggestion colour in a new Fish process, duplicate
Starship initialisation, managed files and colour contrast.

## Backup and restore

```bash
scripts/backup.sh               # manual snapshot of every file the theme may touch
scripts/restore.sh --list       # backups, newest last
scripts/restore.sh --show ID    # files inside one backup
scripts/restore.sh ID           # restore it (asks first; --yes to skip)
scripts/restore.sh --latest
```

A restore puts every file back exactly (content and mode) and removes files
that did not exist when the backup was taken. It first takes a
`pre-restore` backup, so a restore can be undone too. Backups never leave the
machine and are kept until you delete them.

## Uninstall

```bash
./uninstall.sh            # --dry-run to preview, --yes to skip the question
```

* Unchanged managed files are removed, or replaced by the file that existed
  before the first install (e.g. your previous `starship.toml`).
* Konsole keys get their previous values back; marker blocks are removed
  from `kitty.conf` / `alacritty.toml`.
* Files you edited are kept (`--force` removes them too, after a backup).
* Fish, Starship and fonts stay installed. `--remove-downloads` deletes only
  the Starship binary / font the installer downloaded into your home.

## Fish as the login shell (optional)

```bash
scripts/set-default-shell.sh
```

Never done by `install.sh`. The script shows the current and new shell,
asks, and uses `chsh`. Undo with `chsh -s /bin/bash` (or your previous shell).
