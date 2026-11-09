#!/usr/bin/env bash
# Run tests/distro-test.sh in fresh containers of the supported distributions.
#   tests/docker.sh                  all images
#   tests/docker.sh ubuntu:24.04     one image
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
IMAGES=("$@")
((${#IMAGES[@]})) || IMAGES=(archlinux:latest ubuntu:24.04 ubuntu:22.04 debian:13 debian:12 fedora:latest)
declare -A RESULT=()
for img in "${IMAGES[@]}"; do
	case $img in
	archlinux*) prep='pacman -Sy --noconfirm >/dev/null' ;; # sync db only; the installer never runs -Sy itself
	fedora*) prep='dnf -q -y install util-linux >/dev/null' ;; # su for the non-root test
	*) prep=true ;;
	esac
	echo "=== $img"
	if docker run --rm -e CI=1 -v "$ROOT:/src:ro" "$img" bash -c "$prep && /src/tests/distro-test.sh" >"${TMPDIR:-/tmp}/sako-docker-${img//[:\/]/_}.log" 2>&1; then
		RESULT[$img]=PASS
	else
		RESULT[$img]=FAIL
		tail -n 25 "${TMPDIR:-/tmp}/sako-docker-${img//[:\/]/_}.log"
	fi
	echo "    ${RESULT[$img]}  (log: ${TMPDIR:-/tmp}/sako-docker-${img//[:\/]/_}.log)"
done
echo
rc=0
for img in "${IMAGES[@]}"; do
	printf '%-20s %s\n' "$img" "${RESULT[$img]}"
	[[ ${RESULT[$img]} == PASS ]] || rc=1
done
exit $rc
