#!/usr/bin/env bash
# SAKO Terminal Theme — manual backup of every file the theme can touch.
# Copyright (C) 2026 Marcin Sakowski. SPDX-License-Identifier: AGPL-3.0-or-later
set -Eeuo pipefail
SAKO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/common.sh
. "$SAKO_ROOT/lib/common.sh"
# shellcheck source=../lib/verify.sh
. "$SAKO_ROOT/lib/verify.sh"

case ${1-} in
-h | --help)
	cat <<USAGE
Usage: scripts/backup.sh [REASON]

Copies every file SAKO Terminal Theme may change (Starship, Fish, Konsole,
Kitty, Alacritty, WezTerm settings and your local.conf) into
${SAKO_BACKUP_DIR/#$HOME/\~}/<timestamp>/, with a manifest of checksums and
permissions. Files that do not exist are recorded as absent, so a restore
recreates the exact state. Nothing leaves this computer.
USAGE
	exit 0
	;;
esac

C=$SAKO_XDG_CONFIG D=$SAKO_XDG_DATA
paths=(
	"$(starship_target)" "$C/starship.toml" "$SAKO_FISH_MODULE" "$C/fish/config.fish" "$SAKO_LOCAL_CONF"
	"$C/konsolerc" "$D/konsole/SAKO.colorscheme" "$D/konsole/SAKO.profile"
	"$C/kitty/kitty.conf" "$C/kitty/sako-theme.conf"
	"$C/alacritty/alacritty.toml" "$C/alacritty/sako-theme.toml"
	"$C/wezterm/wezterm.lua" "$C/wezterm/colors/SAKO.toml"
)
prof=$(ini_get "$C/konsolerc" "Desktop Entry" DefaultProfile 2>/dev/null || true)
[[ -n $prof && $prof != */* ]] && paths+=("$D/konsole/$prof")
backup_create "${1:-manual}" "${paths[@]}"
ok "Backup $BACKUP_ID created in ${SAKO_BACKUP_DIR/#$HOME/\~}/$BACKUP_ID"
awk -F'\t' '{ printf "    %-8s %s\n", $2, $1 }' "$SAKO_BACKUP_DIR/$BACKUP_ID/backup.tsv"
