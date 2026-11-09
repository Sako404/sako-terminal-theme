# Customisation

All theme values live in one canonical file, `config/theme.conf`. Every
generated file (Starship, Fish, Konsole, Kitty, Alacritty, WezTerm) is
rendered from it. Do not edit the generated files: the next install would
treat them as "edited by you" and stop updating them.

## Your overrides: `local.conf`

`~/.config/sako-terminal-theme/local.conf` is created on the first install
with every common setting commented out. Uncomment and change what you want,
then re-run the installer:

```ini
SAKO_SLOGAN=Ship • Measure • Repeat
SAKO_FISH_AUTOSUGGESTION=#8A96A3
```

```bash
./install.sh
```

Rules:

* `KEY=value`, one per line, optional `"double"` or `'single'` quotes.
* No inline comments — colours contain `#`.
* Only keys that exist in `config/theme.conf` are accepted; a typo stops the
  installer before anything is changed.
* The file is parsed, never executed.
* Install, update and uninstall never overwrite it once you have edited it.

## Settings

| Key | Default | Used for |
|---|---|---|
| `SAKO_URL` | `https://marcinsakowski.com` | Prompt line 1 |
| `SAKO_SLOGAN` | `Build • Automate • Solve` | Prompt line 1 |
| `SAKO_TIME_FORMAT` | `%T` (HH:MM:SS) | Clock at the end of line 1 (strftime) |
| `SAKO_NAVY` | `#0D567A` | Username segment, first separator |
| `SAKO_CYAN` | `#00A6C8` | Directory segment, `❯`, language modules |
| `SAKO_GREY` | `#94A3B8` | Branding line and clock |
| `SAKO_GIT_ORANGE` | `#FCA17D` | Git branch and status |
| `SAKO_USER_FG` | `#FFFFFF` | Text on the navy segment |
| `SAKO_DIR_FG` | `#0B1118` | Text on the cyan segment |
| `SAKO_FISH_AUTOSUGGESTION` | `#7F8C9A` | Fish autosuggestions |
| `SAKO_TERM_*`, `SAKO_COLOR0`–`15` | from the original Konsole scheme | Emulator background, foreground, cursor, selection, 16 ANSI colours |
| `SAKO_FONT_FAMILY`, `SAKO_FONT_SIZE` | `JetBrainsMonoNL Nerd Font`, `11` | Emulator integrations |

Text in `SAKO_SLOGAN` and `SAKO_URL` is escaped for Starship and TOML, so
characters like `[ ] ( ) $ \ "` are shown literally.

### Why the directory text is dark

White on `#00A6C8` has a contrast ratio of 2.9:1, below the WCAG minimum
(4.5:1 for normal text, 3:1 for large text). `#0B1118` on the same cyan
gives 6.6:1. The segment colours themselves are unchanged. To get the
original white text back:

```ini
SAKO_DIR_FG=#FFFFFF
```

`scripts/doctor.sh` prints the contrast of every text/background pair.

## Changing the layout

The prompt layout is `config/templates/starship.toml.tmpl` (Starship
syntax, with `@@KEY@@` placeholders). Changing it means changing the
project: edit the template in your fork, run `tests/run.sh`, then
`./install.sh`.

The Node.js, Rust and Go module styles are kept from the original
configuration. They are not part of the `format` string, so Starship does
not show them; add `$nodejs$rust$golang` to the format in the template if you
want them.
