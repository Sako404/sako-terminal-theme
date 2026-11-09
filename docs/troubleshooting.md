# Troubleshooting

Start with:

```bash
scripts/doctor.sh
```

## Icons show as boxes or question marks

The terminal font has no Nerd Font glyphs.

* Local desktop: `./install.sh --font` installs JetBrains Mono Nerd Font,
  then pick it in the terminal (or use `--terminal NAME` to do that for you).
* Over SSH: the font must be installed on the computer you connect **from**;
  installing it on the server changes nothing.
* Check: `fc-list : family | grep -i nerd`.

## The prompt still shows the old slogan

```bash
scripts/doctor.sh          # "Active config" shows which file Starship reads
echo $STARSHIP_CONFIG      # in fish
```

If `STARSHIP_CONFIG` points elsewhere, the installer writes to that file;
re-run it from the same environment. If doctor says the file is "edited by
you", the installer left it alone on purpose: `./install.sh --force` backs it
up and replaces it.

## Autosuggestions are still hard to read

```fish
set -S fish_color_autosuggestion
```

The SAKO value is a **global** set in `conf.d/sako-theme.fish`. If
`config.fish` (which runs later) sets the variable too, it wins — the
installer warns about that and shows the line. Remove it, or set your colour
via `SAKO_FISH_AUTOSUGGESTION` in `local.conf`. Universal variables are not
removed; the global value simply shadows them.

## Starship runs twice / prompt is slow

`scripts/doctor.sh` counts `starship init fish` lines. The SAKO module skips
its own init when `config.fish` already has one, so at most one line should
exist in your files.

## Konsole did not change

Konsole reads profiles when a tab or window opens: open a new one. Check
*Settings → Edit Current Profile → Appearance*: the scheme should be **SAKO**.
The installer changes the profile named in `~/.config/konsolerc`
(`DefaultProfile`); if you use another profile, select the SAKO scheme there.

## Alacritty colours did not change

Alacritty loads `general.import` files first and the main `alacritty.toml`
last, so `[colors]` or `[font]` sections in the main file override the
theme. The installer warns about them; comment them out to use the SAKO
palette.

## "Cannot continue … fish is not installed"

The installer could not install packages: no `sudo`, an unsupported
distribution, or `--no-deps`. Install `fish` with your package manager and
run it again.

## Package installation failed on Arch-based systems

The installer never runs `pacman -Sy`. If the package database is stale
(404 errors), run `sudo pacman -Syu` and try again.

## No internet / checksum mismatch

Downloads stop with a clear error and nothing is changed. A SHA-256 mismatch
means the downloaded file is not the expected release — do not work around
it; try again later or install the package manually.

## Something went wrong — go back

```bash
scripts/restore.sh --list
scripts/restore.sh <ID>
```

or remove the theme entirely with `./uninstall.sh`.
