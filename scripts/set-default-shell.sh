#!/usr/bin/env bash
# SAKO Terminal Theme — optionally make fish the login shell. Never run by
# install.sh; it changes a system setting, so it always asks first.
# Copyright (C) 2026 Marcin Sakowski. SPDX-License-Identifier: AGPL-3.0-or-later
set -Eeuo pipefail
SAKO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/common.sh
. "$SAKO_ROOT/lib/common.sh"

[[ ${1-} == -h || ${1-} == --help ]] && {
	echo "Usage: scripts/set-default-shell.sh — sets fish as your login shell with chsh (asks first)."
	exit 0
}
have fish || die "fish is not installed. Run ./install.sh first."
fish_path=$(command -v fish)
current=$(getent passwd "$(id -un)" | cut -d: -f7)
if [[ $current == "$fish_path" ]]; then
	ok "fish ($fish_path) is already your login shell."
	exit 0
fi
info "Current login shell: $current"
info "New login shell:     $fish_path"
info "Undo later with:     chsh -s $current"
if ! grep -qxF -- "$fish_path" /etc/shells; then
	warn "$fish_path is not listed in /etc/shells; chsh would refuse it."
	confirm "Add $fish_path to /etc/shells with sudo?" || die "Cancelled."
	printf '%s\n' "$fish_path" | sudo tee -a /etc/shells >/dev/null
fi
confirm "Change your login shell to fish?" || die "Cancelled. Nothing was changed."
chsh -s "$fish_path"
ok "Done. Log out and back in for it to take effect everywhere."
