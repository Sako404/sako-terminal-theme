#!/usr/bin/env bash
# SAKO Terminal Theme — list and restore backups.
# Copyright (C) 2026 Marcin Sakowski. SPDX-License-Identifier: AGPL-3.0-or-later
set -Eeuo pipefail
SAKO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/common.sh
. "$SAKO_ROOT/lib/common.sh"

usage() {
	cat <<USAGE
Usage: scripts/restore.sh [--list | --latest | --show ID | ID] [--yes]

  (no argument)  list backups and ask which one to restore
  --list         list backups (newest last)
  --show ID      show the files in a backup
  --latest       restore the newest backup
  ID             restore that backup
  -y, --yes      do not ask for confirmation

Every file in the backup is put back exactly as it was (content, mode);
files that did not exist at backup time are removed. A "pre-restore"
backup is taken first, so a restore can itself be undone.
USAGE
}

SAKO_ASSUME_YES=0 ID='' MODE=pick
while (($#)); do
	case $1 in
	-h | --help) usage && exit 0 ;;
	-y | --yes) SAKO_ASSUME_YES=1 ;;
	--list) MODE=list ;;
	--latest) MODE=latest ;;
	--show)
		MODE=show
		ID=${2-}
		shift
		;;
	-*) die "Unknown option: $1" ;;
	*) MODE=id ID=$1 ;;
	esac
	shift
done
export SAKO_ASSUME_YES

mapfile -t rows < <(backup_list)
if ((${#rows[@]} == 0)); then
	info "No backups in ${SAKO_BACKUP_DIR/#$HOME/\~}"
	exit 0
fi
print_rows() {
	local i
	for i in "${!rows[@]}"; do
		IFS=$'\t' read -r id date n reason <<<"${rows[$i]}"
		printf '  %2d) %-20s %-26s %-9s %s\n' "$((i + 1))" "$id" "$date" "$n" "$reason"
	done
}
show() {
	local f=$SAKO_BACKUP_DIR/$1/backup.tsv
	[[ -f $f ]] || die "Backup '$1' not found"
	awk -F'\t' '{ printf "    %-8s %s\n", $2, $1 }' "$f"
}

case $MODE in
list)
	print_rows
	exit 0
	;;
show)
	show "$ID"
	exit 0
	;;
latest) IFS=$'\t' read -r ID _ <<<"${rows[-1]}" ;;
pick)
	print_rows
	if [[ $SAKO_ASSUME_YES == 1 || ! -t 0 ]]; then
		info "Choose one: scripts/restore.sh <ID>"
		exit 0
	fi
	read -r -p "Restore which backup (number, empty to cancel)? " n
	[[ $n =~ ^[0-9]+$ && $n -ge 1 && $n -le ${#rows[@]} ]] || die "Cancelled."
	IFS=$'\t' read -r ID _ <<<"${rows[$((n - 1))]}"
	;;
esac

[[ $ID =~ ^[0-9A-Za-z._-]+$ ]] || die "Invalid backup id '$ID'"
step "Backup $ID"
show "$ID"
confirm "Restore these files to the state of backup $ID?" || die "Cancelled. Nothing was changed."
if backup_restore "$ID"; then
	ok "Restore complete and verified (checksums match). Open a new terminal to see it."
else
	die "Restore finished with errors (see above)."
fi
