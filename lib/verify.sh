# shellcheck shell=bash
# shellcheck disable=SC2034 # globals defined here are used by the scripts that source this file
# SAKO Terminal Theme — checks shared by install.sh (before/after applying)
# and scripts/doctor.sh. All checks are read-only.

strip_ansi() { sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g; s/\x1b\\][^\x07]*\x07//g'; }

# validate_toml FILE — 0 ok, 1 invalid, 2 no validator available
validate_toml() {
	have python3 || return 2
	python3 - "$1" <<'PY' 2>/dev/null
import sys
try:
    import tomllib
except ImportError:
    sys.exit(2)
with open(sys.argv[1], "rb") as f:
    try:
        tomllib.load(f)
    except Exception as e:
        print(e, file=sys.stderr)
        sys.exit(1)
PY
}

# validate_starship FILE — 0 when Starship parses it without errors/warnings.
# (Starship exits 0 even for broken configs; its log output is the signal.)
validate_starship() {
	local out
	have starship || return 2
	out=$(STARSHIP_CONFIG=$1 STARSHIP_LOG=warn starship print-config 2>&1 >/dev/null) || return 1
	if grep -qE 'ERROR|WARN' <<<"$out"; then
		printf '%s\n' "$out" | strip_ansi >&2
		return 1
	fi
}

# render_prompt CONFIG [DIR] — the prompt as plain text
render_prompt() {
	local cfg=$1 dir=${2:-$HOME}
	(cd -- "$dir" && STARSHIP_CONFIG=$cfg STARSHIP_SHELL=fish starship prompt --terminal-width 160 --status 0 2>/dev/null) | strip_ansi
}

# check_branding PROMPT_TEXT — line 1 must be "<url> | <slogan> | HH:MM:SS"
check_branding() {
	local line1
	line1=$(sed -n '1p' <<<"$1")
	line1=${line1%$'\r'}
	[[ $line1 == "$SAKO_BRANDING_LINE"* ]] || return 1
	if [[ ${CFG[SAKO_TIME_FORMAT]} == %T ]]; then
		[[ ${line1#"$SAKO_BRANDING_LINE"} =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || return 1
	fi
	[[ $1 != *"$SAKO_OLD_SLOGAN"* ]]
}

# Values as seen by a brand-new interactive fish process.
fish_fresh() { # COMMAND
	fish -i -c "$1" 2>/dev/null </dev/null
}
fish_autosuggestion_now() { fish_fresh 'printf "%s" "$fish_color_autosuggestion"'; }
fish_prompt_uses_starship() {
	local f
	f=$(fish_fresh 'functions fish_prompt') || return 1
	[[ $f == *'starship prompt'* ]]
}

# Number of places that run `starship init fish`, ignoring comments and our
# own (self-guarding) module.
starship_init_sites() {
	local f n=0 c
	for f in "$SAKO_XDG_CONFIG/fish/config.fish" "$SAKO_XDG_CONFIG"/fish/conf.d/*.fish; do
		[[ -f $f && $f != "$SAKO_FISH_MODULE" ]] || continue
		c=$(grep -cE '^[[:space:]]*(starship[[:space:]]+init[[:space:]]+fish|eval[[:space:]]+\([[:space:]]*starship[[:space:]]+init[[:space:]]+fish)' "$f" || true)
		n=$((n + c))
	done
	echo "$n"
}

# starship_target — the Starship config Starship will actually read.
starship_target() {
	local t=${STARSHIP_CONFIG:-} fdir="$SAKO_XDG_CONFIG/fish"
	# Ask fish only if its config mentions STARSHIP_CONFIG: the first start of
	# fish creates files, which a dry run must not do.
	if [[ -z $t ]] && have fish && grep -qsF STARSHIP_CONFIG "$fdir/config.fish" "$fdir"/conf.d/*.fish; then
		t=$(fish -c 'printf "%s" "$STARSHIP_CONFIG"' 2>/dev/null </dev/null || true)
	fi
	[[ -n $t ]] || t="$SAKO_XDG_CONFIG/starship.toml"
	printf '%s\n' "$t"
}

# contrast HEX1 HEX2 -> WCAG contrast ratio with one decimal
contrast() {
	awk -v a="${1#\#}" -v b="${2#\#}" '
		function ch(h, i,   v) { v = index("0123456789abcdef", tolower(substr(h, i, 1))) - 1; v = v * 16 + index("0123456789abcdef", tolower(substr(h, i + 1, 1))) - 1; v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
		function lum(h) { return 0.2126 * ch(h, 1) + 0.7152 * ch(h, 3) + 0.0722 * ch(h, 5) }
		BEGIN { x = lum(a); y = lum(b); if (x < y) { t = x; x = y; y = t }; printf "%.1f\n", (x + 0.05) / (y + 0.05) }'
}
