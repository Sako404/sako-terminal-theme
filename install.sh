#!/usr/bin/env bash
# SAKO Terminal Theme — universal installer.
# Copyright (C) 2026 Marcin Sakowski. SPDX-License-Identifier: AGPL-3.0-or-later
set -Eeuo pipefail

SAKO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
. "$SAKO_ROOT/lib/common.sh"
# shellcheck source=lib/detect.sh
. "$SAKO_ROOT/lib/detect.sh"
# shellcheck source=lib/deps.sh
. "$SAKO_ROOT/lib/deps.sh"
# shellcheck source=lib/engine.sh
. "$SAKO_ROOT/lib/engine.sh"
# shellcheck source=lib/terminals.sh
. "$SAKO_ROOT/lib/terminals.sh"
# shellcheck source=lib/verify.sh
. "$SAKO_ROOT/lib/verify.sh"

usage() {
	cat <<EOF
SAKO Terminal Theme $SAKO_VERSION — Build • Automate • Solve

Usage: ./install.sh [options]

Installs Fish + Starship (if missing), a Nerd Font (if needed), the SAKO prompt
and Fish colours, and optionally a colour scheme for your terminal emulator.
Existing files are backed up first. Safe to run again (idempotent).

Options:
  -h, --help            Show this help and exit
  -n, --dry-run         Show what would happen; change nothing
  -y, --yes             Do not ask for confirmation (safety checks still apply)
      --core-only       Only the core theme (Fish + Starship); no emulator changes
  -t, --terminal NAME   Configure this emulator: konsole, kitty, alacritty, wezterm.
                        Repeatable. Default: the emulator detected from the process
                        tree, if it is supported; otherwise none.
      --font            Install the Nerd Font even without a graphical session
      --no-font         Never install a font
      --no-deps         Do not install packages; fail if fish/starship are missing
      --force           Overwrite managed files you edited since the last install
                        (they are backed up first)
      --version         Print the version and exit

Personalise (slogan, colours, font): ~/.config/sako-terminal-theme/local.conf
Undo: ./uninstall.sh   or   scripts/restore.sh --list
EOF
}

DRY_RUN=0 CORE_ONLY=0 SKIP_DEPS=0 WANT_FONT=auto
SAKO_ASSUME_YES=0
TERMINALS=() TERM_NOTES=()
while (($#)); do
	case $1 in
	-h | --help) usage && exit 0 ;;
	--version) echo "$SAKO_VERSION" && exit 0 ;;
	-n | --dry-run) DRY_RUN=1 ;;
	-y | --yes) SAKO_ASSUME_YES=1 ;;
	--core-only) CORE_ONLY=1 ;;
	-t | --terminal)
		[[ $# -ge 2 ]] || die "--terminal needs a name (konsole, kitty, alacritty, wezterm)"
		TERMINALS+=("${2,,}")
		shift
		;;
	--terminal=*) TERMINALS+=("${1#*=}") ;;
	--font) WANT_FONT=yes ;;
	--no-font) WANT_FONT=no ;;
	--no-deps) SKIP_DEPS=1 ;;
	--force) SAKO_FORCE=1 ;;
	*) die "Unknown option: $1 (see --help)" ;;
	esac
	shift
done
export SAKO_ASSUME_YES

BUILD=''
cleanup() {
	local rc=$?
	[[ -n $BUILD && -d $BUILD ]] && rm -rf -- "$BUILD"
	if ((rc != 0 && rc != 130)) && [[ -n ${SAKO_CURRENT_BACKUP:-} && ${SAKO_ROLLED_BACK:-0} == 0 ]]; then
		err "Installation stopped with an error after changes were made."
		err "Your previous configuration is in backup $SAKO_CURRENT_BACKUP — restore it with:"
		err "  $SAKO_ROOT/scripts/restore.sh $SAKO_CURRENT_BACKUP"
	fi
	return "$rc"
}
on_interrupt() {
	err "Interrupted."
	if [[ -n ${SAKO_CURRENT_BACKUP:-} ]]; then
		err "Files changed so far can be restored with: $SAKO_ROOT/scripts/restore.sh $SAKO_CURRENT_BACKUP"
	else
		err "Nothing in your configuration was changed."
	fi
	exit 130
}
trap cleanup EXIT
trap on_interrupt INT TERM

# --------------------------------------------------------------------------
say "${_c_b}SAKO Terminal Theme $SAKO_VERSION${_c_r} — Build • Automate • Solve"
((DRY_RUN)) && say "(dry run — nothing will be changed)"

((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))) || die "bash >= 4.4 is required"
[[ -n ${HOME:-} && -d $HOME ]] || die "\$HOME is not set or does not exist"
if [[ ${EUID:-$(id -u)} -eq 0 && -n ${SUDO_USER:-} ]]; then
	die "Do not run the installer with sudo. Run it as your normal user; it asks for sudo only to install packages."
fi

step "System"
detect_distro
detect_pkg_manager
detect_privilege
detect_session
DETECTED_TERMINAL=${SAKO_DETECTED_TERMINAL:-$(detect_terminal)} # env var = test hook
info "Distribution:     $DISTRO_NAME (id: $DISTRO_ID, family: $DISTRO_FAMILY)"
info "Package manager:  $PKG_MANAGER"
info "Privileges:       $([[ ${EUID:-$(id -u)} -eq 0 ]] && echo root || { [[ $CAN_ROOT == 1 ]] && echo 'sudo available' || echo 'no sudo'; })"
info "Session:          $([[ $SESSION_SSH == 1 ]] && echo SSH || echo local), $([[ $SESSION_GUI == 1 ]] && echo graphical || echo 'no GUI')"
info "Terminal:         $DETECTED_TERMINAL (from the process tree)"
LOGIN_SHELL=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)
LOGIN_SHELL=${LOGIN_SHELL:-${SHELL:-unknown}}
info "Login shell:      $LOGIN_SHELL; installer runs in bash $BASH_VERSION"
if [[ $DISTRO_SUPPORTED == 0 ]]; then
	if [[ $PKG_MANAGER != none ]]; then
		warn "'$DISTRO_ID' is not on the tested list; using $PKG_MANAGER because it looks like a $DISTRO_FAMILY system."
	else
		warn "'$DISTRO_ID' is not supported for automatic package installation. Fish and Starship must already be installed."
	fi
fi

step "Theme settings"
load_config
info "Branding:  $SAKO_BRANDING_LINE<time>"
info "Fish autosuggestion colour: ${RENDER[SAKO_FISH_AUTOSUGGESTION_HEX]}"
((SAKO_LOCAL_CONF_USED)) && info "Personal overrides: ${SAKO_LOCAL_CONF/#$HOME/\~}"
STARSHIP_TARGET=$(starship_target)
check_path "$STARSHIP_TARGET"
info "Starship config: ${STARSHIP_TARGET/#$HOME/\~}"

# Terminal selection
SELECTED=()
if ((CORE_ONLY)); then
	info "Terminal integration: none (--core-only)"
elif ((${#TERMINALS[@]})); then
	for t in "${TERMINALS[@]}"; do
		terminal_supported "$t" || die "Unsupported terminal '$t'. Supported: ${SAKO_SUPPORTED_TERMINALS[*]}"
		[[ " ${SELECTED[*]} " == *" $t "* ]] || SELECTED+=("$t")
	done
	info "Terminal integration: ${SELECTED[*]}"
elif terminal_supported "$DETECTED_TERMINAL"; then
	SELECTED=("$DETECTED_TERMINAL")
	info "Terminal integration: $DETECTED_TERMINAL (detected; use --core-only to skip)"
else
	info "Terminal integration: none — '$DETECTED_TERMINAL' has no integration or could not be detected reliably."
	info "Core theme only. Pick one explicitly with --terminal NAME if you want it."
fi

step "Dependencies"
deps_plan
deps_print_plan
if ((${#DEP_PROBLEMS[@]})); then
	die "Cannot continue until the problems above are solved."
fi

step "Files"
BUILD=$(mktemp -d)
render_template "$SAKO_TEMPLATES/starship.toml.tmpl" "$BUILD/starship.toml"
render_template "$SAKO_TEMPLATES/sako-theme.fish.tmpl" "$BUILD/sako-theme.fish"
op_reset
op_file "$BUILD/starship.toml" "$STARSHIP_TARGET" "Starship prompt"
op_file "$BUILD/sako-theme.fish" "$SAKO_FISH_MODULE" "Fish module"
if [[ ! -e $SAKO_LOCAL_CONF ]]; then
	op_file "$SAKO_ROOT/config/local.conf.example" "$SAKO_LOCAL_CONF" "Personalisation file"
fi
for t in "${SELECTED[@]}"; do "term_$t"; done
ops_plan
ops_print
PENDING=$(ops_pending)

NEED_DEPS=0
[[ ${#DEP_PKGS[@]} -gt 0 || $DEP_STARSHIP == download || $DEP_STARSHIP == pkg-or-download || $DEP_FONT == download ]] && NEED_DEPS=1

if ((DRY_RUN)); then
	step "Dry run finished"
	info "$PENDING file change(s) and $([[ $NEED_DEPS == 1 ]] && echo 'dependency installation' || echo 'no dependency changes') would be made."
	exit 0
fi

if ((PENDING == 0 && NEED_DEPS == 0)); then
	step "Nothing to change — the SAKO theme is already installed and current"
else
	say ""
	confirm "Apply this plan?" || die "Cancelled. Nothing was changed."
fi

if ((NEED_DEPS)); then
	step "Installing dependencies"
	deps_apply
fi

step "Validating generated configuration"
if validate_toml "$BUILD/starship.toml"; then ok "starship.toml is valid TOML"; else
	rc=$?
	((rc == 2)) && info "TOML check skipped (python3 >= 3.11 not available)" || die "Generated starship.toml is not valid TOML"
fi
validate_starship "$BUILD/starship.toml" || die "Starship rejected the generated configuration (see above). Nothing was changed."
ok "Starship accepts the configuration"
fish -n "$BUILD/sako-theme.fish" || die "Generated Fish module has a syntax error. Nothing was changed."
ok "Fish module syntax OK"
for f in "$BUILD"/alacritty/sako-theme.toml "$BUILD"/wezterm/SAKO.toml; do
	[[ -f $f ]] || continue
	if validate_toml "$f"; then ok "$(basename -- "$f") is valid TOML"; elif (($? == 1)); then die "$f is not valid TOML"; fi
done
for i in "${!OP_KIND[@]}"; do
	if [[ ${OP_KIND[$i]} == block && ${OP_TARGET[$i]} == *.toml && ${OP_STATUS[$i]} != unchanged ]]; then
		tmp=$(mktemp)
		block_render "${OP_TARGET[$i]}" "${OP_A[$i]}" "${OP_B[$i]}" "$tmp" "${OP_C[$i]}"
		if validate_toml "$tmp"; then ok "$(basename -- "${OP_TARGET[$i]}") stays valid TOML after the edit"
		elif (($? == 1)); then rm -f -- "$tmp"; die "Editing ${OP_TARGET[$i]} would make it invalid TOML. Nothing was changed."; fi
		rm -f -- "$tmp"
	fi
done

if ((PENDING)); then
	step "Applying"
	ops_apply
fi

step "Verifying the installed theme"
VERIFY_FAIL=0
if validate_starship "$STARSHIP_TARGET"; then ok "Starship loads ${STARSHIP_TARGET/#$HOME/\~} without warnings"; else
	err "Starship reports problems with ${STARSHIP_TARGET/#$HOME/\~}"
	VERIFY_FAIL=1
fi
PROMPT_TEXT=$(render_prompt "$STARSHIP_TARGET")
if check_branding "$PROMPT_TEXT"; then ok "Line 1: $(sed -n 1p <<<"$PROMPT_TEXT")"; else
	err "Prompt line 1 does not show the expected branding. Got: $(sed -n 1p <<<"$PROMPT_TEXT")"
	VERIFY_FAIL=1
fi
LINES_N=$(grep -c '' <<<"$PROMPT_TEXT" || true)
if ((LINES_N == 3)); then ok "Prompt has 3 lines"; else
	err "Prompt has $LINES_N lines, expected 3"
	VERIFY_FAIL=1
fi
GOT=$(fish_autosuggestion_now || true)
if [[ $GOT == "${RENDER[SAKO_FISH_AUTOSUGGESTION_HEX]}" ]]; then
	ok "New fish process: fish_color_autosuggestion = $GOT"
elif grep -nE '^[^#]*set .*fish_color_autosuggestion' "$SAKO_XDG_CONFIG/fish/config.fish" 2>/dev/null; then
	warn "config.fish sets fish_color_autosuggestion itself (line above) and runs after conf.d, so it wins ($GOT). Remove that line to use the SAKO colour."
else
	err "New fish process reports fish_color_autosuggestion = '${GOT}', expected ${RENDER[SAKO_FISH_AUTOSUGGESTION_HEX]}"
	VERIFY_FAIL=1
fi
if fish_prompt_uses_starship; then ok "fish_prompt is provided by Starship"; else
	err "fish_prompt in a new fish process is not Starship's"
	VERIFY_FAIL=1
fi
SITES=$(starship_init_sites)
if ((SITES <= 1)); then ok "Starship is initialised exactly once ($([[ $SITES == 1 ]] && echo 'by your config.fish; the SAKO module skips its own init' || echo 'by the SAKO module'))"; else
	warn "Found $SITES 'starship init fish' lines in config.fish/conf.d — remove the duplicates."
fi

if ((VERIFY_FAIL)); then
	if [[ -n ${SAKO_CURRENT_BACKUP:-} ]]; then
		err "Verification failed — restoring the previous configuration from backup $SAKO_CURRENT_BACKUP"
		backup_restore "$SAKO_CURRENT_BACKUP" || true
		SAKO_ROLLED_BACK=1
	fi
	die "Installation verification failed. Your prompt was left as it was before."
fi

manifest_init
{
	printf 'version=%s\n' "$SAKO_VERSION"
	printf 'commit=%s\n' "$(git -C "$SAKO_ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
	printf 'source=%s\n' "$SAKO_ROOT"
	printf 'date=%s\n' "$(date -Iseconds)"
} >"$SAKO_STATE_DIR/installed"

step "Done"
ok "SAKO Terminal Theme $SAKO_VERSION is active."
[[ -n ${BACKUP_ID:-} ]] && info "Backup of the previous files: ${SAKO_BACKUP_DIR/#$HOME/\~}/$BACKUP_ID"
for n in "${TERM_NOTES[@]}"; do info "$n"; done
if [[ $(basename -- "$LOGIN_SHELL") != fish ]]; then
	info "Your login shell is $(basename -- "$LOGIN_SHELL"). Try the theme with: fish"
	info "Make fish your default shell (optional): $SAKO_ROOT/scripts/set-default-shell.sh"
fi
info "See it now in a fresh shell:  exec fish"
info "Diagnostics: $SAKO_ROOT/scripts/doctor.sh"
((SAKO_WARNINGS)) && info "$SAKO_WARNINGS warning(s) above."
exit 0
