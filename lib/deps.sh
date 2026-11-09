# shellcheck shell=bash
# shellcheck disable=SC2034 # globals defined here are used by the scripts that source this file
# SAKO Terminal Theme — dependency planning and installation.
#
# Policy:
#  * official distribution repositories first (no AUR, no COPR, no PPAs),
#  * fallback downloads only from the projects' GitHub releases, pinned to a
#    version and verified against a SHA-256 stored in this file,
#  * never `curl | bash`, never install terminal emulators.

STARSHIP_VERSION=1.27.0
declare -gA STARSHIP_SHA256=(
	[x86_64]=10c8eb4cb3b761d9bf59ea828444c2dab36c900b7d69a69e08814b286969df89
	[aarch64]=341f5cbf24699fa0b27ec88965ad25f862ea09e15d35a543fd6ffdff1d2aa00d
)
NERDFONT_VERSION=3.5.1
NERDFONT_ARCHIVE=JetBrainsMono.tar.xz
NERDFONT_SHA256=04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf
NERDFONT_GLOB='JetBrainsMonoNLNerdFont-*.ttf'
SAKO_FONT_DIR="$SAKO_XDG_DATA/fonts/sako-terminal-theme"

# Logical tool -> package name per package manager.
pkg_name() { # MANAGER TOOL
	case "$1:$2" in
	*:fish) echo fish ;;
	*:starship) echo starship ;;
	*:curl) echo curl ;;
	*:tar) echo tar ;;
	*:gzip) echo gzip ;;
	*:fontconfig) echo fontconfig ;;
	pacman:xz | dnf:xz) echo xz ;;
	apt:xz) echo xz-utils ;;
	apt:ca-certificates) echo ca-certificates ;;
	pacman:nerdfont) echo ttf-jetbrains-mono-nerd ;;
	*) return 1 ;;
	esac
}

# deps_plan — decide what is missing. Sets:
#   DEP_PKGS     tools to install with the package manager
#   DEP_STARSHIP pkg | pkg-or-download | download | present
#   DEP_FONT     pkg | download | present | skip-headless | skip
#   DEP_PROBLEMS human-readable blockers
# Inputs: WANT_FONT (auto|yes|no), SKIP_DEPS (0/1)
deps_plan() {
	DEP_PKGS=() DEP_PROBLEMS=() DEP_STARSHIP=present DEP_FONT=skip
	local can_pkg=0
	[[ $PKG_MANAGER != none && $CAN_ROOT == 1 && ${SKIP_DEPS:-0} == 0 ]] && can_pkg=1

	if ! have fish; then
		if ((can_pkg)); then
			DEP_PKGS+=(fish)
		else
			DEP_PROBLEMS+=("fish is not installed and cannot be installed automatically ($(deps_why_not)). Install the 'fish' package, then re-run.")
		fi
	fi

	if ! have starship; then
		if ((can_pkg)); then
			case $PKG_MANAGER in
			pacman) DEP_STARSHIP=pkg DEP_PKGS+=(starship) ;;
			*) DEP_STARSHIP=pkg-or-download ;; # resolved after the index refresh
			esac
		else
			DEP_STARSHIP=download
		fi
	fi

	case ${WANT_FONT:-auto} in
	no) DEP_FONT=skip ;;
	*)
		if nerd_font_present; then
			DEP_FONT=present
		elif [[ ${WANT_FONT:-auto} == auto && $SESSION_GUI == 0 ]]; then
			# Over SSH/TTY the glyphs are drawn by the client's font.
			DEP_FONT=skip-headless
		elif ((can_pkg)) && [[ $PKG_MANAGER == pacman ]]; then
			DEP_FONT=pkg DEP_PKGS+=(nerdfont)
		else
			DEP_FONT=download
		fi
		;;
	esac

	# Helper tools needed by downloads.
	local need_dl=0
	[[ $DEP_STARSHIP == download || $DEP_STARSHIP == pkg-or-download || $DEP_FONT == download ]] && need_dl=1
	if ((need_dl)); then
		local t
		local -a helpers=(curl tar)
		[[ $DEP_STARSHIP == download || $DEP_STARSHIP == pkg-or-download ]] && helpers+=(gzip)
		[[ $DEP_FONT == download ]] && helpers+=(xz)
		for t in "${helpers[@]}"; do
			have "$t" && continue
			if ((can_pkg)); then
				# pkg-or-download only needs helpers if the download happens;
				# they are cheap and part of every base system anyway.
				DEP_PKGS+=("$t")
			elif [[ $DEP_STARSHIP == download || $DEP_FONT == download ]]; then
				DEP_PROBLEMS+=("'$t' is required to download $(deps_dl_what) but is missing ($(deps_why_not)).")
			fi
		done
		if [[ $PKG_MANAGER == apt ]] && ((can_pkg)) && [[ ! -e /etc/ssl/certs/ca-certificates.crt ]]; then
			DEP_PKGS+=(ca-certificates)
		fi
	fi
	if [[ $DEP_FONT == download || $DEP_FONT == pkg ]] && ! have fc-cache && ((can_pkg)); then
		DEP_PKGS+=(fontconfig)
	fi
	return 0
}

deps_dl_what() {
	local w=()
	[[ $DEP_STARSHIP == download ]] && w+=(Starship)
	[[ $DEP_FONT == download ]] && w+=("the Nerd Font")
	local IFS=' '
	echo "${w[*]:-files}"
}

deps_why_not() {
	if [[ ${SKIP_DEPS:-0} == 1 ]]; then echo "--no-deps given"
	elif [[ $PKG_MANAGER == none ]]; then echo "no supported package manager for '$DISTRO_ID'"
	elif [[ $CAN_ROOT == 0 ]]; then echo "not root and sudo is not available"
	else echo "unknown reason"
	fi
}

deps_print_plan() {
	local t names=()
	for t in "${DEP_PKGS[@]}"; do names+=("$(pkg_name "$PKG_MANAGER" "$t")"); done
	if ((${#names[@]})); then
		info "Install with $PKG_MANAGER${SUDO:+ (via sudo)}: ${names[*]}"
	fi
	case $DEP_STARSHIP in
	present) info "starship: already installed ($(starship --version 2>/dev/null | head -n1))" ;;
	pkg) info "starship: package from the official $PKG_MANAGER repositories" ;;
	pkg-or-download) info "starship: $PKG_MANAGER package if the official repositories have it, otherwise the verified v$STARSHIP_VERSION release into ~/.local/bin" ;;
	download) info "starship: verified v$STARSHIP_VERSION release (SHA-256 pinned) into ~/.local/bin" ;;
	esac
	have fish && info "fish: already installed ($(fish --version 2>/dev/null))"
	case $DEP_FONT in
	present) info "Nerd Font: already installed" ;;
	pkg) info "Nerd Font: ttf-jetbrains-mono-nerd from the official repositories" ;;
	download) info "Nerd Font: JetBrains Mono Nerd Font v$NERDFONT_VERSION (SHA-256 pinned) into ${SAKO_FONT_DIR/#$HOME/\~}" ;;
	skip-headless) info "Nerd Font: skipped — no graphical session (over SSH the font must be installed on the client); use --font to force" ;;
	skip) info "Nerd Font: skipped (--no-font)" ;;
	esac
	local p
	for p in "${DEP_PROBLEMS[@]}"; do err "$p"; done
}

pkg_refresh() {
	case $PKG_MANAGER in
	apt) $SUDO apt-get update -q ;;
	*) return 0 ;; # pacman: never -Sy (partial upgrades); dnf refreshes itself
	esac
}

pkg_available() { # TOOL
	local n
	n=$(pkg_name "$PKG_MANAGER" "$1") || return 1
	case $PKG_MANAGER in
	pacman) pacman -Si -- "$n" >/dev/null 2>&1 ;;
	apt)
		local pol
		pol=$(apt-cache policy -- "$n" 2>/dev/null) || return 1
		grep -q 'Candidate: [^(]' <<<"$pol"
		;;
	dnf) dnf -q info -- "$n" >/dev/null 2>&1 ;;
	*) return 1 ;;
	esac
}

pkg_install() { # TOOL...
	local t names=()
	for t in "$@"; do names+=("$(pkg_name "$PKG_MANAGER" "$t")"); done
	((${#names[@]})) || return 0
	info "Installing: ${names[*]}"
	local y=()
	case $PKG_MANAGER in
	pacman)
		[[ ${SAKO_ASSUME_YES:-0} == 1 ]] && y=(--noconfirm)
		$SUDO pacman -S --needed "${y[@]}" -- "${names[@]}"
		;;
	apt)
		local fe=${DEBIAN_FRONTEND:-}
		[[ ${SAKO_ASSUME_YES:-0} == 1 ]] && y=(-y) fe=noninteractive
		$SUDO env DEBIAN_FRONTEND="$fe" apt-get install --no-install-recommends "${y[@]}" -- "${names[@]}"
		;;
	dnf)
		[[ ${SAKO_ASSUME_YES:-0} == 1 ]] && y=(-y)
		$SUDO dnf install "${y[@]}" -- "${names[@]}"
		;;
	esac
}

# verified_download URL SHA256 OUT
verified_download() {
	local url=$1 sum=$2 out=$3 got
	have curl || die "curl is required to download $url"
	info "Downloading $url"
	if ! curl -fL --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 15 -o "$out" -- "$url"; then
		die "Download failed (no internet access?): $url"
	fi
	got=$(sha256_of "$out")
	if [[ $got != "$sum" ]]; then
		rm -f -- "$out"
		die "SHA-256 mismatch for $url (expected $sum, got $got). Nothing was installed."
	fi
	ok "SHA-256 verified"
}

install_starship_release() {
	local arch tmp
	arch=$(uname -m)
	[[ -n ${STARSHIP_SHA256[$arch]+x} ]] || die "No verified Starship build for architecture '$arch'. Install starship manually."
	tmp=$(mktemp -d)
	verified_download \
		"https://github.com/starship/starship/releases/download/v$STARSHIP_VERSION/starship-$arch-unknown-linux-musl.tar.gz" \
		"${STARSHIP_SHA256[$arch]}" "$tmp/starship.tar.gz"
	tar -xzf "$tmp/starship.tar.gz" -C "$tmp" starship || die "Cannot unpack Starship archive"
	mkdir -p -- "$HOME/.local/bin"
	install -m 755 -- "$tmp/starship" "$HOME/.local/bin/starship"
	rm -rf -- "$tmp"
	manifest_put bin "$HOME/.local/bin/starship"
	case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
	ok "Starship $STARSHIP_VERSION installed to ~/.local/bin/starship"
}

install_font_release() {
	local tmp
	tmp=$(mktemp -d)
	verified_download \
		"https://github.com/ryanoasis/nerd-fonts/releases/download/v$NERDFONT_VERSION/$NERDFONT_ARCHIVE" \
		"$NERDFONT_SHA256" "$tmp/font.tar.xz"
	mkdir -p -- "$tmp/x" "$SAKO_FONT_DIR"
	tar -xJf "$tmp/font.tar.xz" -C "$tmp/x" --wildcards "$NERDFONT_GLOB" OFL.txt || die "Cannot unpack font archive"
	install -m 644 -- "$tmp"/x/*.ttf "$tmp/x/OFL.txt" "$SAKO_FONT_DIR/"
	rm -rf -- "$tmp"
	manifest_put fontdir "$SAKO_FONT_DIR"
	if have fc-cache; then fc-cache -f "$SAKO_FONT_DIR" >/dev/null 2>&1 || warn "fc-cache failed"; fi
	ok "JetBrains Mono Nerd Font installed to ${SAKO_FONT_DIR/#$HOME/\~}"
}

# deps_apply — run the plan made by deps_plan.
deps_apply() {
	local -a pkgs=("${DEP_PKGS[@]}")
	if [[ $DEP_STARSHIP == pkg-or-download ]]; then
		pkg_refresh || die "Refreshing the $PKG_MANAGER package index failed"
		if pkg_available starship; then
			DEP_STARSHIP=pkg
			pkgs+=(starship)
		else
			info "starship is not in the official $PKG_MANAGER repositories here — using the verified release"
			DEP_STARSHIP=download
		fi
	elif ((${#pkgs[@]})); then
		pkg_refresh || die "Refreshing the $PKG_MANAGER package index failed"
	fi
	if ((${#pkgs[@]})); then
		pkg_install "${pkgs[@]}" || die "Package installation failed. Nothing in your configuration was changed. On Arch-based systems run 'sudo pacman -Syu' first if the package database is outdated."
		hash -r
	fi
	[[ $DEP_STARSHIP == download ]] && install_starship_release
	[[ $DEP_FONT == download ]] && install_font_release
	if [[ $DEP_FONT == pkg ]] && have fc-cache; then fc-cache >/dev/null 2>&1 || true; fi
	have fish || die "fish is still not available after installation"
	have starship || die "starship is still not available after installation"
	ok "Dependencies ready: $(fish --version), $(starship --version | head -n1)"
}
