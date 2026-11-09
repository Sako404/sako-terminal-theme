# Supported systems and terminals

"Tested" below means an automated or manual run actually happened on that
system. Everything else is "expected to work" and is labelled as such.

## Distributions

| Distribution | Package manager | Status | How it was checked |
|---|---|---|---|
| CachyOS | pacman | **Tested** | Real desktop install (KDE Plasma, Konsole, fish 4.9, Starship 1.27) |
| Arch Linux | pacman | **Tested** | `archlinux:latest` container: fish + starship installed from the official repos, verify, re-run, non-root, uninstall |
| Ubuntu 24.04 | apt | **Tested** | container; Starship is not in the 24.04 archive → verified release |
| Ubuntu 22.04 | apt | **Tested** | container; fish 3.3 |
| Debian 13 (trixie) | apt | **Tested** | container; Starship from the Debian archive |
| Debian 12 (bookworm) | apt | **Tested** | container; Starship → verified release |
| Fedora (latest) | dnf | **Tested** | container; Starship → verified release |
| EndeavourOS, Manjaro | pacman | Expected to work | Detection is unit-tested; uses the same Arch packages |
| Linux Mint | apt | Expected to work | Detection is unit-tested; same packages as its Ubuntu base. No official container image to test with |
| Other distributions | — | Core theme only | If fish and starship are already installed the installer works; it does not install packages for unknown systems (or uses `ID_LIKE` when it says arch/debian/ubuntu/fedora, with a warning) |

Container tests run as root and as an unprivileged user without sudo; they
cover installing with missing dependencies, verification, idempotent re-run
and uninstall. They do not cover graphical output.

The minimum shell versions seen in tests: bash 5.1, fish 3.3.

## Terminal emulators

| Emulator | Integration | Status |
|---|---|---|
| KDE Konsole | `SAKO.colorscheme`; sets `ColorScheme` (and `Font`, if the current one is not a Nerd Font) in your default profile, keeps every other profile setting | **Tested** on CachyOS (visual check) and in isolated tests |
| Kitty | `sako-theme.conf` + an `include` block in `kitty.conf` | File generation and editing tested; not run in a real Kitty |
| Alacritty (≥ 0.14) | `sako-theme.toml` + a `general.import` block; refuses to edit an existing `import` list; warns when your `[colors]`/`[font]` override it | File generation, TOML validity and editing tested; not visually checked |
| WezTerm | `colors/SAKO.toml`; creates `wezterm.lua` only if you have none (Lua is never edited) | File generation tested; not run in a real WezTerm |
| GNOME Terminal, Ptyxis, Tilix, XFCE Terminal, Foot | **No integration** | They are detected and reported; the core theme works in them with a Nerd Font set by hand |

GNOME Terminal, Ptyxis and Tilix store colours in dconf profiles; changing
them safely and reversibly needs more than this project wants to maintain
right now, so there is no half-working integration for them.

## Sessions

| Situation | Behaviour |
|---|---|
| Local desktop | Core theme, detected emulator integration, Nerd Font if missing |
| SSH | Core theme only, no emulator integration, no font (the client draws the glyphs) |
| Linux TTY | Core theme; the console font has no Nerd glyphs, so icons show as boxes |
| No sudo | Works if fish is installed; Starship and the font go into your home directory |
| Invoked from bash, zsh or fish | Same result: the installer is a bash script and does not depend on the calling shell |
