#!/usr/bin/env bash
# SAKO Terminal Theme — uninstaller. Removes only what the project manages.
# Copyright (C) 2026 Marcin Sakowski. SPDX-License-Identifier: AGPL-3.0-or-later
set -Eeuo pipefail

SAKO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
. "$SAKO_ROOT/lib/common.sh"

usage() {
	cat <<EOF
SAKO Terminal Theme $SAKO_VERSION — uninstall

Usage: ./uninstall.sh [options]

Removes the files and settings recorded in the install manifest:
  * unchanged managed files are removed, or replaced by the file that was
    there before the first install (from the backup),
  * Konsole settings are set back to their previous values,
  * marker blocks are removed from kitty.conf / alacritty.toml,
  * files you edited after installing are kept (see --force).
Fish, Starship, fonts and terminal emulators are NOT removed.
Everything is backed up first; backups are kept.

Options:
  -h, --help            Show this help
  -n, --dry-run         Show what would happen
  -y, --yes             Do not ask for confirmation
      --force           Also remove/restore managed files you have edited
                        (they are backed up first)
      --remove-downloads  Also delete the Starship binary and Nerd Font that
                        the installer downloaded into your home directory
EOF
}

DRY_RUN=0 FORCE=0 REMOVE_DL=0 SAKO_ASSUME_YES=0
while (($#)); do
	case $1 in
	-h | --help) usage && exit 0 ;;
	-n | --dry-run) DRY_RUN=1 ;;
	-y | --yes) SAKO_ASSUME_YES=1 ;;
	--force) FORCE=1 ;;
	--remove-downloads) REMOVE_DL=1 ;;
	*) die "Unknown option: $1 (see --help)" ;;
	esac
	shift
done
export SAKO_ASSUME_YES

say "${_c_b}SAKO Terminal Theme — uninstall${_c_r}"
if [[ ! -s $SAKO_MANIFEST ]]; then
	ok "Nothing to uninstall: no SAKO-managed files are recorded in ${SAKO_MANIFEST/#$HOME/\~}"
	exit 0
fi

# Plan ---------------------------------------------------------------------
ACT=() P=() X=() Y=() Z=() TARGETS=() KEPT=()
add() { ACT+=("$1") P+=("$2") X+=("${3-}") Y+=("${4-}") Z+=("${5-}"); }

while IFS= read -r line; do
	IFS=$'\t' read -r kind path a b c d <<<"$line"
	case $kind in
	file)
		real=$(real_target "$path")
		if [[ ! -e $real ]]; then
			add forget "$path" file
			continue
		fi
		if [[ $(sha256_of "$real") != "$a" && $FORCE == 0 ]]; then
			KEPT+=("$path (edited by you — kept)")
			add forget "$path" file
			continue
		fi
		if [[ $b == backup:* && -f $SAKO_BACKUP_DIR/${b#backup:}/files$path ]]; then
			add restore "$path" "${b#backup:}"
		else
			add remove "$path"
		fi
		TARGETS+=("$path")
		;;
	ini)
		cur=$(ini_get "$path" "$a" "$b" 2>/dev/null) || cur=$SAKO_ABSENT
		if [[ $cur == "$c" ]]; then
			add ini "$path" "$a" "$b" "${d:-}"
			TARGETS+=("$path")
		else
			KEPT+=("$path [$a] $b=$cur (changed by you — kept)")
			add forget "$path" ini "$a" "$b"
		fi
		;;
	block)
		if block_present "$path"; then
			add unblock "$path" "$a"
			TARGETS+=("$path")
		else
			add forget "$path" block
		fi
		;;
	fontdir | bin)
		if ((REMOVE_DL)) && [[ -e $path ]]; then
			add rmdl "$path" "$kind"
		else
			[[ -e $path ]] && KEPT+=("$path (downloaded $kind — kept; use --remove-downloads)")
			add forget "$path" "$kind"
		fi
		;;
	esac
done <"$SAKO_MANIFEST"

step "Plan"
for i in "${!ACT[@]}"; do
	p=${P[$i]/#$HOME/\~}
	case ${ACT[$i]} in
	restore) info "↺ restore the original $p (from backup ${X[$i]})" ;;
	remove) info "- remove $p" ;;
	ini) info "↺ $p [${X[$i]}] ${Y[$i]}=$([[ ${Z[$i]} == "$SAKO_ABSENT" ]] && echo '(unset)' || echo "${Z[$i]}")" ;;
	unblock) info "- remove the SAKO block from $p" ;;
	rmdl) info "- delete downloaded ${X[$i]} $p" ;;
	esac
done
for k in "${KEPT[@]}"; do warn "keep $k"; done
info "Not touched: fish, starship and font packages, your config.fish, other settings."

if ((DRY_RUN)); then
	step "Dry run finished — nothing was changed"
	exit 0
fi
confirm "Uninstall the SAKO theme as shown?" || die "Cancelled. Nothing was changed."

# Apply ----------------------------------------------------------------------
if ((${#TARGETS[@]})); then
	backup_create "uninstall" "${TARGETS[@]}"
	ok "Backup created: ${SAKO_BACKUP_DIR/#$HOME/\~}/$BACKUP_ID"
fi
for i in "${!ACT[@]}"; do
	path=${P[$i]}
	case ${ACT[$i]} in
	restore)
		atomic_write "$SAKO_BACKUP_DIR/${X[$i]}/files$path" "$path"
		ok "restored original $path"
		manifest_del file "$path"
		;;
	remove)
		rm -f -- "$(real_target "$path")"
		[[ -L $path ]] && rm -f -- "$path"
		rmdir -- "$(dirname -- "$path")" 2>/dev/null || true
		ok "removed $path"
		manifest_del file "$path"
		;;
	ini)
		tmp=$(mktemp)
		ini_render "$path" "${X[$i]}" "${Y[$i]}" "${Z[$i]}" "$tmp"
		atomic_write "$tmp" "$path"
		rm -f -- "$tmp"
		ok "reset ${Y[$i]} in $path"
		manifest_del ini "$path" "${X[$i]}" "${Y[$i]}"
		;;
	unblock)
		tmp=$(mktemp)
		block_strip "$path" "$tmp"
		if [[ ${X[$i]} == absent && -z $(tr -d '[:space:]' <"$tmp") ]]; then
			rm -f -- "$(real_target "$path")"
			ok "removed $path (it only contained the SAKO block)"
		else
			atomic_write "$tmp" "$path"
			ok "removed the SAKO block from $path"
		fi
		rm -f -- "$tmp"
		manifest_del block "$path"
		;;
	rmdl)
		rm -rf -- "$path"
		ok "deleted $path"
		[[ ${X[$i]} == fontdir ]] && command -v fc-cache >/dev/null && fc-cache -f >/dev/null 2>&1 || true
		manifest_del "${X[$i]}" "$path"
		;;
	forget)
		manifest_del "${X[$i]}" "$path" "${Y[$i]}" "${Z[$i]}"
		;;
	esac
done
rm -f -- "$SAKO_STATE_DIR/installed"

step "Done"
ok "SAKO Terminal Theme removed. Open a new terminal (or run: exec fish) to see the result."
info "Backups are kept in ${SAKO_BACKUP_DIR/#$HOME/\~} — scripts/restore.sh --list"
if [[ -f $SAKO_LOCAL_CONF ]]; then info "Your personal settings stay in ${SAKO_LOCAL_CONF/#$HOME/\~}"; fi
