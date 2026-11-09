#!/usr/bin/env bash
# SAKO Terminal Theme — read-only diagnostics. Exit code 1 if a check fails.
# Copyright (C) 2026 Marcin Sakowski. SPDX-License-Identifier: AGPL-3.0-or-later
set -Euo pipefail
SAKO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/common.sh
. "$SAKO_ROOT/lib/common.sh"
# shellcheck source=../lib/detect.sh
. "$SAKO_ROOT/lib/detect.sh"
# shellcheck source=../lib/verify.sh
. "$SAKO_ROOT/lib/verify.sh"

[[ ${1-} == -h || ${1-} == --help ]] && {
	echo "Usage: scripts/doctor.sh — checks the installed SAKO theme; changes nothing."
	exit 0
}

FAIL=0
bad() {
	err "$*"
	FAIL=1
}

say "${_c_b}SAKO Terminal Theme doctor${_c_r} (checkout $SAKO_VERSION)"
load_config

step "System"
detect_distro
detect_pkg_manager
detect_session
info "Distribution: $DISTRO_NAME ($DISTRO_ID / $DISTRO_FAMILY), package manager: $PKG_MANAGER"
info "Terminal: $(detect_terminal), session: $([[ $SESSION_SSH == 1 ]] && echo SSH || echo local) $([[ $SESSION_GUI == 1 ]] && echo '+ GUI')"
info "Login shell: $(getent passwd "$(id -un)" | cut -d: -f7)"
inst=$(sed -n 's/^version=//p;' "$SAKO_STATE_DIR/installed" 2>/dev/null || true)
if [[ -n $inst ]]; then ok "Installed theme version: $inst ($(sed -n 's/^date=//p' "$SAKO_STATE_DIR/installed"))"; else warn "Theme is not installed (no ${SAKO_STATE_DIR/#$HOME/\~}/installed)"; fi

step "Programs"
if have fish; then ok "$(fish --version)"; else bad "fish is not installed"; fi
if have starship; then ok "$(starship --version | head -n1) ($(command -v starship))"; else bad "starship is not installed"; fi
if nerd_font_present; then ok "Nerd Font available: $(fc-list : family | grep -iE 'nerd font' | head -n1 | cut -d, -f1)"
elif [[ $SESSION_GUI == 0 ]]; then info "No Nerd Font here — fine over SSH/TTY if the client terminal has one"
else warn "No Nerd Font found — icons will show as boxes"; fi

step "Starship"
target=$(starship_target)
info "Active config: ${target/#$HOME/\~}$([[ -n ${STARSHIP_CONFIG:-} ]] && echo ' (from $STARSHIP_CONFIG)')"
if [[ ! -f $target ]]; then
	bad "Starship config does not exist"
else
	if entry=$(manifest_lookup file "$target"); then
		if [[ $(sha256_of "$(real_target "$target")") == "$(cut -f3 <<<"$entry")" ]]; then ok "Managed by SAKO, unmodified"
		else warn "Managed by SAKO but edited by hand (install.sh will not overwrite it without --force)"; fi
	else
		warn "Not managed by SAKO (not installed, or replaced by something else)"
	fi
	if validate_starship "$target"; then ok "Starship parses it without warnings"; else bad "Starship reports problems (see above)"; fi
	prompt=$(render_prompt "$target")
	if check_branding "$prompt"; then ok "Branding: $(sed -n 1p <<<"$prompt")"; else bad "Unexpected line 1: $(sed -n 1p <<<"$prompt")"; fi
	if grep -qF -- "$SAKO_OLD_SLOGAN" "$target"; then bad "Old slogan '$SAKO_OLD_SLOGAN' is still in the config"; else ok "Old slogan not present"; fi
	n=$(grep -c '' <<<"$prompt")
	if ((n == 3)); then ok "Prompt has 3 lines"; else bad "Prompt has $n lines (expected 3)"; fi
	if have git; then
		tmp=$(mktemp -d)
		(cd "$tmp" && git init -q -b sako-doctor && git -c user.name=d -c user.email=d@localhost commit -q --allow-empty -m init && echo x >untracked) >/dev/null 2>&1
		gp=$(render_prompt "$target" "$tmp")
		rm -rf -- "$tmp"
		if [[ $gp == *sako-doctor* && $gp == *'[?]'* ]]; then ok "Git branch and status render (temporary test repository)"; else bad "Git segment missing in a test repository: $(sed -n 2p <<<"$gp")"; fi
	fi
fi

step "Fish"
if [[ -f $SAKO_FISH_MODULE ]]; then
	ok "Module: ${SAKO_FISH_MODULE/#$HOME/\~}"
	fish -n "$SAKO_FISH_MODULE" && ok "Module syntax OK" || bad "Module has a syntax error"
else
	bad "Module missing: ${SAKO_FISH_MODULE/#$HOME/\~}"
fi
if have fish; then
	got=$(fish_autosuggestion_now || true)
	if [[ $got == "${RENDER[SAKO_FISH_AUTOSUGGESTION_HEX]}" ]]; then ok "fish_color_autosuggestion in a new fish: $got"
	else bad "fish_color_autosuggestion in a new fish: '$got' (expected ${RENDER[SAKO_FISH_AUTOSUGGESTION_HEX]})"; fi
	uv=$(fish -c 'set -qU fish_color_autosuggestion; and printf "%s" "$fish_color_autosuggestion"' 2>/dev/null </dev/null || true)
	[[ -n $uv ]] && info "A universal fish_color_autosuggestion ($uv) also exists; the SAKO global value shadows it"
	if fish_prompt_uses_starship; then ok "fish_prompt comes from Starship"; else bad "fish_prompt is not Starship's in a new fish"; fi
	sites=$(starship_init_sites)
	if ((sites <= 1)); then ok "Starship initialised once ($([[ $sites == 1 ]] && echo 'config.fish' || echo 'SAKO module'))"
	else bad "$sites 'starship init fish' lines in config.fish/conf.d — duplicates"; fi
fi

step "Terminal integrations"
any=0
while IFS= read -r line; do
	IFS=$'\t' read -r kind path a b c _ <<<"$line"
	any=1
	case $kind in
	file) [[ $(sha256_of "$(real_target "$path")") == "$a" ]] && ok "file  ${path/#$HOME/\~}" || warn "file  ${path/#$HOME/\~} (missing or edited)" ;;
	ini) [[ $(ini_get "$path" "$a" "$b" 2>/dev/null) == "$c" ]] && ok "ini   ${path/#$HOME/\~} [$a] $b=$c" || warn "ini   ${path/#$HOME/\~} [$a] $b changed" ;;
	block) block_present "$path" && ok "block ${path/#$HOME/\~}" || warn "block ${path/#$HOME/\~} missing" ;;
	fontdir | bin) [[ -e $path ]] && ok "$kind ${path/#$HOME/\~}" || warn "$kind ${path/#$HOME/\~} missing" ;;
	esac
done < <(cat "$SAKO_MANIFEST" 2>/dev/null || true)
((any)) || info "Nothing recorded in the manifest."

step "Contrast (WCAG)"
for pair in "SAKO_USER_FG SAKO_NAVY username" "SAKO_DIR_FG SAKO_CYAN directory" "SAKO_GREY SAKO_TERM_BG branding" \
	"SAKO_GIT_ORANGE SAKO_TERM_BG git" "SAKO_FISH_AUTOSUGGESTION SAKO_TERM_BG autosuggestion"; do
	read -r f b label <<<"$pair"
	r=$(contrast "${CFG[$f]}" "${CFG[$b]}")
	if awk -v r="$r" 'BEGIN { exit !(r >= 4.5) }'; then ok "$label: $r:1"; else warn "$label: $r:1 (below 4.5:1)"; fi
done

step "Backups"
nb=$(backup_list | grep -c '' || true)
info "$nb backup(s) in ${SAKO_BACKUP_DIR/#$HOME/\~}"

say ""
if ((FAIL)); then err "Some checks failed."; exit 1; fi
ok "All checks passed."
