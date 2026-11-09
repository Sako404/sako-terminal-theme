#!/usr/bin/env bash
# SAKO Terminal Theme — end-to-end test inside a fresh distribution container.
# Runs as root in a throw-away container (see tests/docker.sh and CI).
# Installs real packages, so never run it on a normal machine.
set -Eeuo pipefail
[[ -f /.dockerenv || -n ${CI:-} || -n ${container:-} ]] || {
	echo "Refusing to run outside a container/CI." >&2
	exit 2
}
src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
work=/tmp/sako src_copy="/tmp/sako src"
rm -rf -- "$src_copy"
cp -r -- "$src" "$src_copy" # path with a space on purpose
export NO_COLOR=1
fail() {
	echo "FAIL: $*" >&2
	exit 1
}
t() { printf '\n######## %s\n' "$*"; }
cd /

. /etc/os-release
t "distribution: $PRETTY_NAME"
command -v fish >/dev/null && fail "fish is preinstalled; the test needs missing dependencies"
command -v starship >/dev/null && fail "starship is preinstalled"

t "1. install with missing dependencies (as root)"
"$src_copy/install.sh" --yes --core-only | tee "$work.1.log"
grep -q 'is active' "$work.1.log" || fail "install did not finish"
command -v fish || fail "fish missing after install"
export PATH="$HOME/.local/bin:$PATH" # where a downloaded starship lives
command -v starship || fail "starship missing after install"

t "2. doctor"
"$src_copy/scripts/doctor.sh"

t "3. branding, autosuggestion, no old slogan"
grep -q 'Build • Automate • Solve' ~/.config/starship.toml || fail "slogan"
! grep -q 'Empowering Property Growth' ~/.config/starship.toml || fail "old slogan"
got=$(fish -i -c 'printf %s $fish_color_autosuggestion' </dev/null 2>/dev/null)
[[ $got == 7f8c9a ]] || fail "autosuggestion is '$got'"
echo "fish $(fish --version | awk '{print $3}') autosuggestion=$got"

t "4. re-run is idempotent and installs nothing"
"$src_copy/install.sh" --yes --core-only | tee "$work.2.log"
grep -q 'Nothing to change' "$work.2.log" || fail "second run changed something"
! grep -q 'Install with' "$work.2.log" || fail "second run wanted to install packages"

t "5. non-root user without sudo (dependencies already present)"
useradd -m sakotest
su sakotest -s /bin/bash -c "cd / && NO_COLOR=1 '$src_copy/install.sh' --yes --core-only" | tee "$work.3.log"
grep -q 'is active' "$work.3.log" || fail "non-root install"
su sakotest -s /bin/bash -c "'$src_copy/uninstall.sh' --yes" >/dev/null || fail "non-root uninstall"
[[ ! -e /home/sakotest/.config/starship.toml ]] || fail "non-root uninstall left starship.toml"

t "6. uninstall (root)"
"$src_copy/uninstall.sh" --yes
[[ ! -e ~/.config/starship.toml && ! -e ~/.config/fish/conf.d/sako-theme.fish ]] || fail "uninstall left files"
command -v fish >/dev/null || fail "uninstall removed fish"

t "ALL DISTRO TESTS PASSED on $PRETTY_NAME"
