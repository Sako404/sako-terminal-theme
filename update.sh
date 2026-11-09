#!/usr/bin/env bash
# SAKO Terminal Theme — updater. Never runs in the background, never uses
# `git reset --hard`, never touches local edits in the project checkout.
# Copyright (C) 2026 Marcin Sakowski. SPDX-License-Identifier: AGPL-3.0-or-later
set -Eeuo pipefail

SAKO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
. "$SAKO_ROOT/lib/common.sh"

usage() {
	cat <<EOF
SAKO Terminal Theme $SAKO_VERSION — update

Usage: ./update.sh [options] [-- install options]

  1. checks the project checkout for local changes (stops if there are any),
  2. fetches the remote and fast-forwards (no merges, no resets),
  3. re-runs install.sh, which backs up and updates the managed files and
     keeps your local.conf and files you edited,
  4. if installing fails, moves the checkout back to the previous commit.

Options:
  -h, --help       Show this help
  -n, --check      Only report whether an update is available
  -y, --yes        Pass --yes to install.sh
      --reapply    Re-run install.sh even if there is no new version
Anything after -- is passed to install.sh (e.g. -- --terminal kitty).
EOF
}

CHECK_ONLY=0 REAPPLY=0 INSTALL_ARGS=()
while (($#)); do
	case $1 in
	-h | --help) usage && exit 0 ;;
	-n | --check) CHECK_ONLY=1 ;;
	-y | --yes) INSTALL_ARGS+=(--yes) ;;
	--reapply) REAPPLY=1 ;;
	--)
		shift
		INSTALL_ARGS+=("$@")
		break
		;;
	*) die "Unknown option: $1 (see --help)" ;;
	esac
	shift
done

say "${_c_b}SAKO Terminal Theme — update${_c_r}"
installed=$(sed -n 's/^version=//p' "$SAKO_STATE_DIR/installed" 2>/dev/null || true)
info "Project checkout: $SAKO_ROOT (version $SAKO_VERSION)"
info "Installed theme:  ${installed:-not installed}"

if ! have git || ! git -C "$SAKO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	warn "This copy is not a git checkout, so it cannot update itself."
	info "Download the latest release (see docs/installation.md), unpack it and run ./install.sh from there."
	exit 1
fi

g() { git -C "$SAKO_ROOT" "$@"; }

if [[ -n $(g status --porcelain) ]]; then
	g status --short >&2
	die "The project checkout has local changes (above). Commit or stash them first — personal settings belong in ${SAKO_LOCAL_CONF/#$HOME/\~}, not in the repository."
fi
branch=$(g symbolic-ref --quiet --short HEAD) || die "The checkout is on a detached HEAD; switch to a branch (git switch main) first."
upstream=$(g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || die "Branch '$branch' has no upstream to update from."

step "Checking $upstream"
g fetch --quiet --tags "${upstream%%/*}" || die "git fetch failed (no internet access?). Nothing was changed."
read -r ahead behind < <(g rev-list --left-right --count "HEAD...@{u}")
if ((ahead > 0 && behind > 0)); then
	die "Your branch and $upstream have diverged ($ahead local, $behind remote commits). Resolve that manually; nothing was changed."
elif ((ahead > 0)); then
	warn "Your branch is $ahead commit(s) ahead of $upstream; nothing to pull."
fi
if ((behind == 0)); then
	ok "Already up to date ($(g rev-parse --short HEAD))."
	((CHECK_ONLY)) && exit 0
	if ((REAPPLY == 0)); then
		[[ $installed == "$SAKO_VERSION" ]] && exit 0
		info "Installed theme differs from the checkout — re-applying."
	fi
else
	info "$behind new commit(s):"
	g log --oneline "HEAD..@{u}" | sed 's/^/      /'
	((CHECK_ONLY)) && exit 0
	prev=$(g rev-parse HEAD)
	g merge --ff-only --quiet "@{u}" || die "Fast-forward failed; nothing was changed."
	ok "Updated $(g rev-parse --short "$prev") → $(g rev-parse --short HEAD) (version $(tr -d '[:space:]' <"$SAKO_ROOT/VERSION"))"
fi

step "Applying the updated theme"
if ! "$SAKO_ROOT/install.sh" "${INSTALL_ARGS[@]}"; then
	if [[ -n ${prev:-} ]]; then
		err "install.sh failed — moving the checkout back to $(g rev-parse --short "$prev")."
		g reset --keep "$prev" && ok "Checkout restored. Your terminal configuration was rolled back by install.sh or left unchanged."
	fi
	exit 1
fi
