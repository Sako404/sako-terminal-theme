# shellcheck shell=bash
# shellcheck disable=SC2034 # globals defined here are used by the scripts that source this file
# SAKO Terminal Theme — system detection.

# Test hook: point at a fake os-release file.
SAKO_OS_RELEASE=${SAKO_OS_RELEASE:-/etc/os-release}

SAKO_SUPPORTED_TERMINALS=(konsole kitty alacritty wezterm)

# detect_distro — sets DISTRO_ID, DISTRO_NAME, DISTRO_FAMILY (arch|debian|fedora|unknown)
detect_distro() {
	DISTRO_ID=unknown DISTRO_NAME=unknown DISTRO_FAMILY=unknown
	[[ -r $SAKO_OS_RELEASE ]] || return 0
	local line key val id_like=''
	while IFS= read -r line || [[ -n $line ]]; do
		[[ $line =~ ^([A-Z_]+)=(.*)$ ]] || continue
		key=${BASH_REMATCH[1]}
		val=${BASH_REMATCH[2]}
		val=${val#\"}
		val=${val%\"}
		val=${val#\'}
		val=${val%\'}
		case $key in
		ID) DISTRO_ID=${val,,} ;;
		ID_LIKE) id_like=${val,,} ;;
		PRETTY_NAME) DISTRO_NAME=$val ;;
		esac
	done <"$SAKO_OS_RELEASE"
	case $DISTRO_ID in
	cachyos | arch | endeavouros | manjaro) DISTRO_FAMILY=arch ;;
	ubuntu | debian | linuxmint) DISTRO_FAMILY=debian ;;
	fedora) DISTRO_FAMILY=fedora ;;
	*)
		case " $id_like " in
		*" arch "*) DISTRO_FAMILY=arch ;;
		*" ubuntu "* | *" debian "*) DISTRO_FAMILY=debian ;;
		*" fedora "*) DISTRO_FAMILY=fedora ;;
		esac
		;;
	esac
	case $DISTRO_ID in
	cachyos | arch | endeavouros | manjaro | ubuntu | debian | linuxmint | fedora) DISTRO_SUPPORTED=1 ;;
	*) DISTRO_SUPPORTED=0 ;;
	esac
}

# detect_pkg_manager — sets PKG_MANAGER (pacman|apt|dnf|none), checking that
# the binary matching the distro family really exists.
detect_pkg_manager() {
	PKG_MANAGER=none
	case $DISTRO_FAMILY in
	arch) have pacman && PKG_MANAGER=pacman ;;
	debian) have apt-get && PKG_MANAGER=apt ;;
	fedora) have dnf && PKG_MANAGER=dnf ;;
	esac
}

# detect_privilege — sets SUDO ('' when root) and CAN_ROOT (1/0).
# Never prompts: only checks that sudo exists.
detect_privilege() {
	if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
		SUDO='' CAN_ROOT=1
	elif have sudo; then
		SUDO='sudo' CAN_ROOT=1
	else
		SUDO='' CAN_ROOT=0
	fi
}

# detect_session — sets SESSION_SSH, SESSION_GUI (1/0)
detect_session() {
	SESSION_SSH=0 SESSION_GUI=0
	[[ -n ${SSH_CONNECTION:-}${SSH_TTY:-} ]] && SESSION_SSH=1
	[[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} && $SESSION_SSH == 0 ]] && SESSION_GUI=1
	return 0
}

# detect_terminal — prints the emulator that hosts this process, by walking
# the process tree. Prints "ssh", "tty" or "unknown" when there is no
# emulator, or another name for emulators without an integration.
# $TERM is deliberately not used: most emulators claim xterm-256color.
detect_terminal() {
	local pid=${1:-$$} comm depth=0
	while [[ $pid =~ ^[0-9]+$ && $pid -gt 1 && $depth -lt 40 ]]; do
		comm=$(cat "/proc/$pid/comm" 2>/dev/null) || break
		case $comm in
		konsole) echo konsole && return ;;
		kitty) echo kitty && return ;;
		alacritty) echo alacritty && return ;;
		wezterm-gui | wezterm) echo wezterm && return ;;
		gnome-terminal-*) echo gnome-terminal && return ;;
		ptyxis*) echo ptyxis && return ;;
		tilix) echo tilix && return ;;
		xfce4-terminal) echo xfce4-terminal && return ;;
		foot | footclient) echo foot && return ;;
		sshd | sshd-session | sshd-*) echo ssh && return ;;
		login | agetty) echo tty && return ;;
		esac
		pid=$(awk '/^PPid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null) || break
		depth=$((depth + 1))
	done
	echo unknown
}

terminal_supported() {
	local t
	for t in "${SAKO_SUPPORTED_TERMINALS[@]}"; do [[ $t == "$1" ]] && return 0; done
	return 1
}

nerd_font_present() {
	have fc-list || return 1
	local fams
	fams=$(fc-list : family 2>/dev/null) || return 1
	grep -qiE 'nerd font|(^|[ ,])[A-Za-z]+ ?NF([ ,]|$)' <<<"$fams"
}
