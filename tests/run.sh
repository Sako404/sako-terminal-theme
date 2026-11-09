#!/usr/bin/env bash
# SAKO Terminal Theme — test suite.
#
# Every test runs with its own temporary $HOME; the real home directory is
# never written to. Package managers, sudo, curl and fc-list are replaced by
# stubs where a test needs a specific situation.
#
#   tests/run.sh            run everything
#   tests/run.sh NAME...    run tests whose name contains NAME
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
REAL_HOME=$HOME
WORK=$(mktemp -d "${TMPDIR:-/tmp}/sako-tests.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
export NO_COLOR=1
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME STARSHIP_CONFIG SAKO_OS_RELEASE

PASS=0 FAILN=0 SKIP=0 FAILED=()
_fail() {
	printf '      ✘ %s\n' "$*"
	CUR_FAIL=1
}
assert_rc() { [[ $RC == "$1" ]] || _fail "exit code $RC, expected $1"; }
assert_has() { [[ $OUT == *"$1"* ]] || _fail "output lacks: $1"; }
assert_lacks() { [[ $OUT != *"$1"* ]] || _fail "output unexpectedly contains: $1"; }
assert_file() { [[ -f $1 ]] || _fail "missing file: $1"; }
assert_nofile() { [[ ! -e $1 ]] || _fail "file should not exist: $1"; }
assert_grep() { grep -qF -- "$2" "$1" 2>/dev/null || _fail "$1 lacks: $2"; }
assert_nogrep() { ! grep -qF -- "$2" "$1" 2>/dev/null || _fail "$1 contains: $2"; }
assert_same() { cmp -s -- "$1" "$2" || _fail "files differ: $1 vs $2"; }
skip() {
	SKIP_REASON=$*
	return 0
}

# new_home [NAME] — fresh isolated HOME (path contains a space on purpose)
new_home() {
	H="$WORK/home ${1:-x}.$RANDOM"
	mkdir -p "$H"
	export HOME=$H
	[[ $HOME != "$REAL_HOME" ]] || {
		echo "refusing to run with the real HOME" >&2
		exit 2
	}
	C=$H/.config D=$H/.local/share S=$H/.local/state/sako-terminal-theme
}
inst() { # run install.sh with args, capture output and rc
	OUT=$(cd / && "$ROOT/install.sh" "$@" 2>&1 </dev/null)
	RC=$?
}
run() { # run any command, capture
	OUT=$("$@" 2>&1 </dev/null)
	RC=$?
}
tree_sum() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum) | sha256sum; }
first_line() { sed -n 1p <<<"$1"; }

# Restricted PATH: everything from /usr/bin except the given names.
restricted_path() { # NAME...
	local dir="$WORK/bin.$RANDOM" f n skip
	mkdir -p "$dir"
	for f in /usr/bin/* /usr/local/bin/*; do
		[[ -x $f ]] || continue
		n=${f##*/}
		skip=0
		for x in "$@"; do [[ $n == "$x" ]] && skip=1; done
		((skip)) || ln -sf "$f" "$dir/$n" 2>/dev/null
	done
	echo "$dir"
}
stub() { # DIR NAME BODY
	printf '#!/usr/bin/env bash\n%s\n' "$3" >"$1/$2"
	chmod +x "$1/$2"
}
os_release() { # ID [ID_LIKE]
	local f="$WORK/os-release.$1"
	{
		printf 'ID=%s\nPRETTY_NAME="%s test"\n' "$1" "$1"
		[[ -n ${2-} ]] && printf 'ID_LIKE="%s"\n' "$2"
	} >"$f"
	echo "$f"
}

# ---------------------------------------------------------------------------
t_bash_syntax() {
	local f
	for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/lib/*.sh "$ROOT"/tests/*.sh; do
		bash -n "$f" || _fail "bash -n $f"
	done
}

t_shellcheck() {
	local files=("$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/lib/*.sh "$ROOT"/tests/*.sh)
	if command -v shellcheck >/dev/null; then
		run shellcheck -x -S warning "${files[@]}"
	elif [[ ${SAKO_SHELLCHECK_DOCKER:-0} == 1 ]] && command -v docker >/dev/null; then
		run docker run --rm -v "$ROOT:/mnt:ro" -w /mnt koalaman/shellcheck:stable -x -S warning \
			"${files[@]#"$ROOT/"}"
	else
		skip "shellcheck not installed (set SAKO_SHELLCHECK_DOCKER=1 to use docker)"
		return
	fi
	[[ $RC == 0 ]] || _fail "shellcheck: $OUT"
}

render_all() { # renders into $WORK/r using the default theme
	(
		cd /
		SAKO_ROOT=$ROOT
		# shellcheck source=../lib/common.sh
		. "$ROOT/lib/common.sh"
		load_config
		mkdir -p "$WORK/r"
		for t in starship.toml sako-theme.fish; do render_template "$SAKO_TEMPLATES/$t.tmpl" "$WORK/r/$t"; done
		for t in "$SAKO_TEMPLATES"/terminals/*.tmpl; do
			n=${t##*/}
			render_template "$t" "$WORK/r/${n%.tmpl}"
		done
	)
}

t_fish_syntax() {
	render_all
	fish -n "$WORK/r/sako-theme.fish" || _fail "fish -n on rendered module"
	fish -n "$ROOT/config/templates/sako-theme.fish.tmpl" || _fail "fish -n on template"
}

t_toml_valid() {
	python3 -c 'import tomllib' 2>/dev/null || {
		skip "python3 tomllib not available"
		return
	}
	render_all
	local f
	for f in "$WORK/r/starship.toml" "$WORK/r/alacritty.toml" "$WORK/r/wezterm.toml"; do
		python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1],"rb"))' "$f" || _fail "invalid TOML: $f"
	done
}

t_starship_config_valid() {
	render_all
	OUT=$(STARSHIP_CONFIG="$WORK/r/starship.toml" starship print-config 2>&1 >/dev/null)
	[[ $OUT != *ERROR* && $OUT != *WARN* ]] || _fail "starship: $OUT"
}

t_no_unrendered_placeholders() {
	render_all
	! grep -rn '@@' "$WORK/r" || _fail "placeholders left in rendered files"
}

t_branding_in_sources() {
	assert_grep "$ROOT/config/theme.conf" 'SAKO_SLOGAN=Build • Automate • Solve'
	local f
	for f in "$ROOT/config/theme.conf" "$ROOT"/config/templates/*.tmpl "$ROOT"/config/templates/terminals/*.tmpl; do
		assert_nogrep "$f" "Empowering Property Growth"
	done
}

t_contrast() {
	(
		. "$ROOT/lib/common.sh"
		. "$ROOT/lib/verify.sh"
		load_config
		for p in "SAKO_USER_FG SAKO_NAVY" "SAKO_DIR_FG SAKO_CYAN" "SAKO_GREY SAKO_TERM_BG" "SAKO_GIT_ORANGE SAKO_TERM_BG" "SAKO_FISH_AUTOSUGGESTION SAKO_TERM_BG"; do
			read -r a b <<<"$p"
			r=$(contrast "${CFG[$a]}" "${CFG[$b]}")
			awk -v r="$r" 'BEGIN{exit !(r>=4.5)}' || { echo "$a on $b = $r"; exit 1; }
		done
	) || _fail "a text colour pair is below 4.5:1"
}

t_help_documents_all_options() {
	run "$ROOT/install.sh" --help
	assert_rc 0
	local o
	for o in --help --dry-run --yes --core-only --terminal --font --no-font --no-deps --force --version konsole kitty alacritty wezterm; do
		assert_has "$o"
	done
	for s in update.sh uninstall.sh scripts/restore.sh scripts/backup.sh scripts/doctor.sh scripts/set-default-shell.sh; do
		run "$ROOT/$s" --help
		[[ $RC == 0 ]] || _fail "$s --help exited $RC"
	done
	run "$ROOT/install.sh" --bogus
	assert_rc 1
	assert_has "Unknown option"
}

t_distro_detection() {
	local id fam
	for pair in cachyos:arch arch:arch endeavouros:arch manjaro:arch ubuntu:debian debian:debian linuxmint:debian fedora:fedora \
		pop:debian@"ubuntu debian" garuda:arch@arch nobara:fedora@fedora gentoo:unknown; do
		id=${pair%%:*}
		fam=${pair#*:}
		like=''
		[[ $fam == *@* ]] && like=${fam#*@} fam=${fam%@*}
		got=$(SAKO_OS_RELEASE=$(os_release "$id" "$like") bash -c '. "$1/lib/common.sh"; . "$1/lib/detect.sh"; detect_distro; echo "$DISTRO_FAMILY $DISTRO_SUPPORTED"' _ "$ROOT")
		[[ ${got% *} == "$fam" ]] || _fail "$id: family '${got% *}', expected $fam"
	done
}

t_dry_run_changes_nothing() {
	new_home dry
	mkdir -p "$C"
	printf 'old\n' >"$C/starship.toml"
	local before
	before=$(tree_sum "$H")
	inst --dry-run --terminal konsole --terminal kitty --terminal alacritty --terminal wezterm
	assert_rc 0
	assert_has "Dry run finished"
	[[ $(tree_sum "$H") == "$before" ]] || _fail "dry run modified files"
	assert_nofile "$S"
}

t_fresh_install_core() {
	new_home fresh
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	assert_rc 0
	assert_has "Terminal integration: none"
	assert_file "$C/starship.toml"
	assert_file "$C/fish/conf.d/sako-theme.fish"
	assert_grep "$C/starship.toml" 'Build • Automate • Solve'
	assert_nogrep "$C/starship.toml" 'Empowering Property Growth'
	assert_grep "$C/fish/conf.d/sako-theme.fish" 'set -g fish_color_autosuggestion 7f8c9a'
	[[ $(fish -i -c 'printf %s $fish_color_autosuggestion' 2>/dev/null </dev/null) == 7f8c9a ]] || _fail "autosuggestion in new fish"
	local p
	p=$(cd "$H" && STARSHIP_CONFIG="$C/starship.toml" starship prompt --terminal-width 120 | sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g')
	[[ $(first_line "$p") =~ ^https://marcinsakowski\.com\ \|\ Build\ •\ Automate\ •\ Solve\ \|\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || _fail "line 1: $(first_line "$p")"
	[[ $(grep -c '' <<<"$p") == 3 ]] || _fail "prompt is not 3 lines"
	[[ $p == *'❯'* ]] || _fail "no ❯ prompt character"
	assert_nofile "$D/konsole/SAKO.colorscheme"
}

t_reinstall_idempotent() {
	new_home idem
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal konsole --terminal kitty
	assert_rc 0
	local m b
	m=$(sha256sum <"$S/manifest.tsv")
	b=$(ls "$S/backups" | wc -l)
	local kc
	kc=$(sha256sum <"$C/kitty/kitty.conf")
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal konsole --terminal kitty
	assert_rc 0
	assert_has "Nothing to change"
	[[ $(sha256sum <"$S/manifest.tsv") == "$m" ]] || _fail "manifest changed on re-run"
	[[ $(ls "$S/backups" | wc -l) == "$b" ]] || _fail "re-run created another backup"
	[[ $(sha256sum <"$C/kitty/kitty.conf") == "$kc" ]] || _fail "kitty.conf changed on re-run"
	[[ $(grep -c 'sako-terminal-theme >>>' "$C/kitty/kitty.conf") == 1 ]] || _fail "duplicate kitty block"
}

t_no_duplicate_starship_init() {
	new_home dup
	local bin
	bin="$WORK/wrap.$RANDOM"
	mkdir -p "$bin" "$C/fish"
	# A starship wrapper that logs every `starship init` call.
	# (`starship init fish` itself calls `starship init fish --print-full-init`;
	#  only the outer call counts as one initialisation.)
	stub "$bin" starship "[[ \"\$*\" == 'init fish' ]] && echo init >>\"$H/init.log\"; exec $(command -v starship) \"\$@\""
	printf 'starship init fish | source\n' >"$C/fish/config.fish"
	PATH="$bin:$PATH" SAKO_DETECTED_TERMINAL=unknown inst --yes
	assert_rc 0
	rm -f "$H/init.log"
	PATH="$bin:$PATH" fish -i -c true </dev/null >/dev/null 2>&1
	[[ $(grep -c init "$H/init.log" 2>/dev/null) == 1 ]] || _fail "with config.fish init: starship init ran $(grep -c init "$H/init.log" 2>/dev/null) times"
	# Without the config.fish line the module must initialise it once.
	: >"$C/fish/config.fish"
	rm -f "$H/init.log"
	PATH="$bin:$PATH" fish -i -c true </dev/null >/dev/null 2>&1
	[[ $(grep -c init "$H/init.log" 2>/dev/null) == 1 ]] || _fail "module only: starship init ran $(grep -c init "$H/init.log" 2>/dev/null) times"
	[[ $(PATH="$bin:$PATH" fish -i -c 'functions fish_prompt' 2>/dev/null </dev/null) == *'starship prompt'* ]] || _fail "fish_prompt not starship"
}

t_universal_autosuggestion_shadowed() {
	new_home uvar
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	fish -c 'set -U fish_color_autosuggestion red' </dev/null
	local got
	got=$(fish -i -c 'printf %s $fish_color_autosuggestion' 2>/dev/null </dev/null)
	[[ $got == 7f8c9a ]] || _fail "universal value won: $got"
	[[ $(fish -c 'set -qU fish_color_autosuggestion; and echo kept' 2>/dev/null </dev/null) == kept ]] || _fail "universal variable was removed"
}

t_existing_starship_backed_up_and_restored_on_uninstall() {
	new_home exist
	mkdir -p "$C"
	printf 'format = "[https://marcinsakowski.com | Empowering Property Growth | ]$time"\n' >"$C/starship.toml"
	cp "$C/starship.toml" "$WORK/orig.toml"
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	assert_rc 0
	assert_has "replace"
	assert_nogrep "$C/starship.toml" "Empowering Property Growth"
	local bk
	bk=$(ls "$S/backups" | head -n1)
	assert_same "$S/backups/$bk/files$C/starship.toml" "$WORK/orig.toml"
	run "$ROOT/uninstall.sh" --yes
	assert_rc 0
	assert_same "$C/starship.toml" "$WORK/orig.toml"
	assert_nofile "$C/fish/conf.d/sako-theme.fish"
}

t_user_edits_are_protected() {
	new_home edits
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	printf '\n# my tweak\n' >>"$C/starship.toml"
	cp "$C/starship.toml" "$WORK/edited.toml"
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	assert_rc 0
	assert_has "was changed by you"
	assert_same "$C/starship.toml" "$WORK/edited.toml"
	SAKO_DETECTED_TERMINAL=unknown inst --yes --force
	assert_rc 0
	assert_nogrep "$C/starship.toml" "# my tweak"
	grep -rqF '# my tweak' "$S/backups" || _fail "edited file was not backed up before --force"
	# uninstall keeps an edited file
	printf '\n# again\n' >>"$C/starship.toml"
	run "$ROOT/uninstall.sh" --yes
	assert_rc 0
	assert_grep "$C/starship.toml" "# again"
}

t_kitty_block_preserves_user_config() {
	new_home kitty
	mkdir -p "$C/kitty"
	printf 'font_size 14\nmap ctrl+t new_tab\n' >"$C/kitty/kitty.conf"
	cp "$C/kitty/kitty.conf" "$WORK/kitty.orig"
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal kitty
	assert_rc 0
	assert_grep "$C/kitty/kitty.conf" "map ctrl+t new_tab"
	assert_grep "$C/kitty/kitty.conf" "include sako-theme.conf"
	assert_grep "$C/kitty/sako-theme.conf" "background            #141B24"
	run "$ROOT/uninstall.sh" --yes
	assert_same "$C/kitty/kitty.conf" "$WORK/kitty.orig"
	assert_nofile "$C/kitty/sako-theme.conf"
}

t_alacritty_import() {
	new_home ala
	mkdir -p "$C/alacritty"
	printf '[window]\nopacity = 0.8\n\n[general]\nlive_config_reload = true\n' >"$C/alacritty/alacritty.toml"
	cp "$C/alacritty/alacritty.toml" "$WORK/ala.orig"
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal alacritty
	assert_rc 0
	python3 - "$C/alacritty/alacritty.toml" "$C/alacritty/sako-theme.toml" <<'PY' || _fail "alacritty import not valid"
import sys, tomllib
c = tomllib.load(open(sys.argv[1], "rb"))
assert c["general"]["import"] == [sys.argv[2]], c
assert c["general"]["live_config_reload"] is True
assert c["window"]["opacity"] == 0.8
tomllib.load(open(sys.argv[2], "rb"))
PY
	run "$ROOT/uninstall.sh" --yes
	assert_same "$C/alacritty/alacritty.toml" "$WORK/ala.orig"
	# existing import list: never edited
	new_home ala2
	mkdir -p "$C/alacritty"
	printf '[general]\nimport = ["~/x.toml"]\n' >"$C/alacritty/alacritty.toml"
	cp "$C/alacritty/alacritty.toml" "$WORK/ala2.orig"
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal alacritty
	assert_rc 0
	assert_has "already has an 'import' list"
	assert_same "$C/alacritty/alacritty.toml" "$WORK/ala2.orig"
}

t_wezterm_respects_existing_lua() {
	new_home wez
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal wezterm
	assert_rc 0
	assert_file "$C/wezterm/colors/SAKO.toml"
	assert_grep "$C/wezterm/wezterm.lua" "config.color_scheme = 'SAKO'"
	new_home wez2
	mkdir -p "$C/wezterm"
	printf 'return {}\n' >"$C/wezterm/wezterm.lua"
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal wezterm
	assert_rc 0
	[[ $(cat "$C/wezterm/wezterm.lua") == 'return {}' ]] || _fail "existing wezterm.lua was edited"
	assert_has "config.color_scheme = 'SAKO'"
}

t_konsole_existing_profile() {
	new_home konsole
	mkdir -p "$D/konsole" "$C"
	printf '[Desktop Entry]\nDefaultProfile=Mine.profile\n\n[General]\nConfigVersion=1\n' >"$C/konsolerc"
	printf '[Appearance]\nColorScheme=Breeze\nFont=Hack,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n\n[General]\nName=Mine\nParent=FALLBACK/\n\n[Interaction Options]\nAutoCopySelectedText=true\n' >"$D/konsole/Mine.profile"
	cp "$D/konsole/Mine.profile" "$WORK/mine.orig"
	cp "$C/konsolerc" "$WORK/rc.orig"
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal konsole
	assert_rc 0
	assert_grep "$D/konsole/Mine.profile" "ColorScheme=SAKO"
	assert_grep "$D/konsole/Mine.profile" "Font=JetBrainsMonoNL Nerd Font,11"
	assert_grep "$D/konsole/Mine.profile" "AutoCopySelectedText=true"
	assert_same "$C/konsolerc" "$WORK/rc.orig"
	assert_grep "$D/konsole/SAKO.colorscheme" "Color=#141B24"
	run "$ROOT/uninstall.sh" --yes
	assert_rc 0
	assert_same "$D/konsole/Mine.profile" "$WORK/mine.orig"
	assert_nofile "$D/konsole/SAKO.colorscheme"
	# A profile that already uses a Nerd Font keeps its font.
	new_home konsole2
	mkdir -p "$D/konsole" "$C"
	printf '[Desktop Entry]\nDefaultProfile=Mine.profile\n' >"$C/konsolerc"
	printf '[Appearance]\nColorScheme=X\nFont=FiraCode Nerd Font,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n' >"$D/konsole/Mine.profile"
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal konsole
	assert_grep "$D/konsole/Mine.profile" "Font=FiraCode Nerd Font,12"
}

t_backup_and_restore() {
	new_home backup
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	run "$ROOT/scripts/backup.sh" test
	assert_rc 0
	local id
	id=$(sed -n 's/.*Backup \([0-9-]*\) created.*/\1/p' <<<"$OUT")
	[[ -n $id ]] || _fail "no backup id in output"
	cp "$C/starship.toml" "$WORK/s.before"
	printf 'broken' >"$C/starship.toml"
	mkdir -p "$C/kitty"
	printf 'x\n' >"$C/kitty/sako-theme.conf" # did not exist at backup time
	run "$ROOT/scripts/restore.sh" --list
	assert_has "$id"
	run "$ROOT/scripts/restore.sh" "$id" --yes
	assert_rc 0
	assert_same "$C/starship.toml" "$WORK/s.before"
	assert_nofile "$C/kitty/sako-theme.conf"
	assert_has "Undo this restore with"
	stat -c %a "$S/backups/$id" | grep -qx 700 || _fail "backup dir is not mode 700"
}

t_uninstall_removes_only_managed() {
	new_home uninst
	mkdir -p "$C/fish/conf.d"
	printf 'set -g my_var 1\n' >"$C/fish/conf.d/mine.fish"
	SAKO_DETECTED_TERMINAL=unknown inst --yes --terminal kitty
	printf 'SAKO_SLOGAN=Mine\n' >>"$C/sako-terminal-theme/local.conf"
	run "$ROOT/uninstall.sh" --dry-run
	assert_rc 0
	assert_file "$C/starship.toml"
	run "$ROOT/uninstall.sh" --yes
	assert_rc 0
	assert_nofile "$C/starship.toml"
	assert_nofile "$C/fish/conf.d/sako-theme.fish"
	assert_nofile "$C/kitty/kitty.conf"
	assert_file "$C/fish/conf.d/mine.fish"
	assert_grep "$C/sako-terminal-theme/local.conf" "SAKO_SLOGAN=Mine"
	command -v fish >/dev/null || _fail "fish disappeared"
	run "$ROOT/uninstall.sh" --yes
	assert_has "Nothing to uninstall"
}

t_custom_slogan_escaping() {
	new_home slogan
	mkdir -p "$C/sako-terminal-theme"
	printf '%s\n' 'SAKO_SLOGAN="Ship [fast] & $cheap (now) \o/ "quoted""' >"$C/sako-terminal-theme/local.conf"
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	assert_rc 0
	assert_has 'Ship [fast] & $cheap (now) \o/ "quoted" | '
	printf 'SAKO_BOGUS=1\n' >>"$C/sako-terminal-theme/local.conf"
	local before
	before=$(sha256sum <"$C/starship.toml")
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	assert_rc 1
	assert_has "unknown setting 'SAKO_BOGUS'"
	[[ $(sha256sum <"$C/starship.toml") == "$before" ]] || _fail "invalid local.conf still changed files"
}

t_verification_failure_rolls_back() {
	new_home rollback
	mkdir -p "$C/fish"
	printf 'old = 1\n' >"$C/starship.toml"
	# config.fish replaces the prompt after conf.d → verification must fail.
	printf 'function fish_prompt\n  echo "> "\nend\n' >"$C/fish/config.fish"
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	assert_rc 1
	assert_has "restoring the previous configuration"
	[[ $(cat "$C/starship.toml") == 'old = 1' ]] || _fail "starship.toml not rolled back"
	assert_nofile "$C/fish/conf.d/sako-theme.fish"
}

t_no_tty_without_yes_refuses() {
	new_home notty
	OUT=$(cd / && setsid -w "$ROOT/install.sh" --core-only 2>&1 </dev/null)
	RC=$?
	[[ $RC != 0 ]] || _fail "installer proceeded without confirmation"
	assert_has "Re-run with --yes"
	assert_nofile "$C/starship.toml"
}

t_missing_deps_plan() {
	new_home deps
	local bin
	bin=$(restricted_path fish starship sudo apt-get apt-cache dnf pacman fc-list)
	stub "$bin" sudo 'exec "$@"'
	stub "$bin" apt-get 'echo "apt-get $*" >>"$HOME/pm.log"'
	stub "$bin" apt-cache 'exit 0'
	OUT=$(cd / && PATH=$bin SAKO_OS_RELEASE=$(os_release ubuntu debian) SAKO_DETECTED_TERMINAL=unknown \
		DISPLAY=:0 "$bin/bash" "$ROOT/install.sh" --dry-run 2>&1 </dev/null)
	RC=$?
	assert_rc 0
	assert_has "Package manager:  apt"
	assert_has "Install with apt (via sudo): fish"
	assert_has "starship: apt package if the official repositories have it, otherwise the verified v"
	assert_has "Nerd Font: JetBrains Mono Nerd Font"
	assert_nofile "$H/pm.log"
	# pacman family, as root-less user with sudo
	stub "$bin" pacman 'exit 0'
	OUT=$(cd / && PATH=$bin SAKO_OS_RELEASE=$(os_release endeavouros arch) SAKO_DETECTED_TERMINAL=unknown \
		DISPLAY=:0 "$bin/bash" "$ROOT/install.sh" --dry-run 2>&1 </dev/null)
	assert_has "Install with pacman (via sudo): fish starship ttf-jetbrains-mono-nerd"
	# no sudo, not root: fish cannot be installed → clear error
	rm -f "$bin/sudo"
	stub "$bin" dnf 'exit 0'
	OUT=$(cd / && PATH=$bin SAKO_OS_RELEASE=$(os_release fedora) SAKO_DETECTED_TERMINAL=unknown \
		"$bin/bash" "$ROOT/install.sh" --dry-run 2>&1 </dev/null)
	RC=$?
	assert_rc 1
	assert_has "fish is not installed and cannot be installed automatically (not root and sudo is not available)"
	assert_has "starship: verified v"
}

t_missing_deps_install_with_stubs() {
	# Full apply path with a fake package manager that "installs" fish/starship
	# by linking the real binaries — proves the plan → install → verify flow.
	new_home depsinst
	local bin real_fish real_starship
	real_fish=$(command -v fish)
	real_starship=$(command -v starship)
	bin=$(restricted_path fish starship sudo apt-get apt-cache dnf pacman)
	stub "$bin" sudo 'exec "$@"'
	stub "$bin" pacman "echo \"pacman \$*\" >>\"\$HOME/pm.log\"; for p in \"\$@\"; do case \$p in fish) ln -sf $real_fish $bin/fish;; starship) ln -sf $real_starship $bin/starship;; esac; done"
	OUT=$(cd / && PATH=$bin SAKO_OS_RELEASE=$(os_release cachyos arch) SAKO_DETECTED_TERMINAL=unknown \
		"$bin/bash" "$ROOT/install.sh" --yes 2>&1 </dev/null)
	RC=$?
	assert_rc 0
	assert_grep "$H/pm.log" "pacman -S --needed --noconfirm -- fish starship"
	assert_has "SAKO Terminal Theme 1.0.0 is active"
	# second run: nothing is installed again
	: >"$H/pm.log"
	OUT=$(cd / && PATH=$bin SAKO_OS_RELEASE=$(os_release cachyos arch) SAKO_DETECTED_TERMINAL=unknown \
		"$bin/bash" "$ROOT/install.sh" --yes 2>&1 </dev/null)
	assert_rc 0
	[[ ! -s $H/pm.log ]] || _fail "package manager called again: $(cat "$H/pm.log")"
}

t_existing_deps_not_reinstalled() {
	new_home have
	SAKO_DETECTED_TERMINAL=unknown inst --dry-run --no-font
	assert_has "starship: already installed"
	assert_has "fish: already installed"
	assert_lacks "Install with"
}

t_headless_skips_font() {
	new_home headless
	local bin
	bin=$(restricted_path fc-list)
	stub "$bin" fc-list 'exit 0'
	OUT=$(cd / && env -u DISPLAY -u WAYLAND_DISPLAY PATH=$bin SAKO_DETECTED_TERMINAL=tty "$bin/bash" "$ROOT/install.sh" --dry-run 2>&1 </dev/null)
	assert_has "Session:          local, no GUI"
	assert_has "Nerd Font: skipped — no graphical session"
	OUT=$(cd / && env -u DISPLAY -u WAYLAND_DISPLAY SSH_CONNECTION='1 2 3 4' PATH=$bin SAKO_DETECTED_TERMINAL=ssh "$bin/bash" "$ROOT/install.sh" --dry-run 2>&1 </dev/null)
	assert_has "Session:          SSH, no GUI"
	assert_has "Terminal integration: none"
}

t_unknown_terminal() {
	new_home unk
	SAKO_DETECTED_TERMINAL=gnome-terminal inst --dry-run
	assert_has "Terminal integration: none — 'gnome-terminal' has no integration"
	inst --dry-run --terminal gnome-terminal
	assert_rc 1
	assert_has "Unsupported terminal 'gnome-terminal'"
	# a process with no emulator among its ancestors
	local out="$WORK/detect.$RANDOM"
	setsid -f bash -c '. "$1/lib/common.sh"; . "$1/lib/detect.sh"; detect_terminal >"$2"' _ "$ROOT" "$out"
	for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s $out ]] && break; sleep 0.2; done
	[[ $(cat "$out" 2>/dev/null) == unknown ]] || _fail "detached process detected '$(cat "$out" 2>/dev/null)'"
}

t_invoking_shells_and_cwd() {
	new_home shells
	local sh
	for sh in bash zsh fish; do
		command -v "$sh" >/dev/null || {
			printf '      (no %s, skipped)\n' "$sh"
			continue
		}
		OUT=$(cd "$WORK" && SAKO_DETECTED_TERMINAL=unknown "$sh" -c "'$ROOT/install.sh' --dry-run" 2>&1 </dev/null)
		RC=$?
		[[ $RC == 0 && $OUT == *"Dry run finished"* ]] || _fail "dry run from $sh failed (rc $RC)"
	done
	mkdir -p "$WORK/dir with spaces"
	OUT=$(cd "$WORK/dir with spaces" && SAKO_DETECTED_TERMINAL=unknown "$ROOT/install.sh" --dry-run 2>&1 </dev/null)
	[[ $? == 0 ]] || _fail "dry run from a directory with spaces"
}

t_symlinked_config() {
	new_home link
	mkdir -p "$H/dotfiles" "$C"
	printf 'old = 1\n' >"$H/dotfiles/starship.toml"
	ln -s "$H/dotfiles/starship.toml" "$C/starship.toml"
	SAKO_DETECTED_TERMINAL=unknown inst --yes
	assert_rc 0
	[[ -L $C/starship.toml ]] || _fail "symlink was replaced by a file"
	assert_grep "$H/dotfiles/starship.toml" "Build • Automate • Solve"
	run "$ROOT/uninstall.sh" --yes
	[[ -L $C/starship.toml ]] || _fail "symlink lost on uninstall"
	[[ $(cat "$H/dotfiles/starship.toml") == 'old = 1' ]] || _fail "original content not restored through symlink"
}

t_offline_and_bad_checksum() {
	new_home offline
	local bin
	bin=$(restricted_path starship curl fc-list)
	stub "$bin" fc-list 'exit 0'
	stub "$bin" curl 'exit 6'
	OUT=$(cd / && PATH=$bin SAKO_OS_RELEASE=$(os_release gentoo) SAKO_DETECTED_TERMINAL=unknown "$bin/bash" "$ROOT/install.sh" --yes --no-font 2>&1 </dev/null)
	RC=$?
	assert_rc 1
	assert_has "Download failed (no internet access?)"
	assert_nofile "$C/starship.toml"
	stub "$bin" curl 'while [[ $# -gt 0 ]]; do [[ $1 == -o ]] && { echo tampered >"$2"; }; shift; done; exit 0'
	OUT=$(cd / && PATH=$bin SAKO_OS_RELEASE=$(os_release gentoo) SAKO_DETECTED_TERMINAL=unknown "$bin/bash" "$ROOT/install.sh" --yes --no-font 2>&1 </dev/null)
	RC=$?
	assert_rc 1
	assert_has "SHA-256 mismatch"
	assert_nofile "$H/.local/bin/starship"
	assert_nofile "$C/starship.toml"
}

t_update_flow() {
	command -v git >/dev/null || {
		skip "git missing"
		return
	}
	new_home update
	local remote="$WORK/remote.$RANDOM" src="$WORK/src.$RANDOM" clone="$WORK/clone.$RANDOM"
	mkdir -p "$src"
	(cd "$ROOT" && tar --exclude=.git -cf - .) | tar -xf - -C "$src"
	g() { git -c user.name=t -c user.email=t@localhost -c init.defaultBranch=main "$@"; }
	(cd "$src" && g init -q && g add -A && g commit -qm v1) || _fail "git setup"
	g clone -q --bare "$src" "$remote"
	g clone -q "$remote" "$clone"
	OUT=$(cd / && SAKO_DETECTED_TERMINAL=unknown "$clone/install.sh" --yes 2>&1 </dev/null) || _fail "initial install"
	run "$clone/update.sh" --check
	assert_rc 0
	assert_has "Already up to date"
	[[ ${SAKO_TEST_DEBUG:-0} == 1 ]] && printf '%s\n' "$OUT"
	# new upstream version changes the default slogan
	(cd "$src" && sed -i 's/^SAKO_SLOGAN=.*/SAKO_SLOGAN=Updated Slogan/' config/theme.conf && g commit -qam v2 && g push -q "$remote" HEAD:main) || _fail "push v2"
	# a dirty checkout must stop the update
	printf '\n' >>"$clone/VERSION"
	run "$clone/update.sh" --yes
	assert_rc 1
	assert_has "local changes"
	(cd "$clone" && git checkout -q -- VERSION)
	OUT=$(cd / && SAKO_DETECTED_TERMINAL=unknown "$clone/update.sh" --yes 2>&1 </dev/null)
	RC=$?
	[[ ${SAKO_TEST_DEBUG:-0} == 1 ]] && printf '%s\n' "$OUT"
	assert_rc 0
	assert_has "1 new commit"
	assert_grep "$C/starship.toml" "Updated Slogan"
	# local.conf personalisation survives updates
	printf 'SAKO_SLOGAN=Mine\n' >>"$C/sako-terminal-theme/local.conf"
	OUT=$(cd / && SAKO_DETECTED_TERMINAL=unknown "$clone/update.sh" --yes --reapply 2>&1 </dev/null)
	assert_grep "$C/starship.toml" "Mine"
}

# ---------------------------------------------------------------------------
TESTS=$(declare -F | awk '$3 ~ /^t_/ { print $3 }')
for t in $TESTS; do
	if (($#)); then
		m=0
		for f in "$@"; do [[ $t == *"$f"* ]] && m=1; done
		((m)) || continue
	fi
	CUR_FAIL=0 SKIP_REASON=''
	printf '  %-60s' "${t#t_}"
	# Each test in a subshell: HOME and other changes never leak.
	res=$(
		CUR_FAIL=0
		SKIP_REASON=''
		"$t" >"$WORK/log" 2>&1
		cat "$WORK/log"
		if [[ -n $SKIP_REASON ]]; then echo "@@SKIP $SKIP_REASON"; elif ((CUR_FAIL)); then echo "@@FAIL"; else echo "@@PASS"; fi
	)
	case $(tail -n1 <<<"$res") in
	@@PASS)
		echo "ok"
		PASS=$((PASS + 1))
		;;
	@@SKIP*)
		echo "SKIP ($(tail -n1 <<<"$res" | cut -c8-))"
		SKIP=$((SKIP + 1))
		;;
	*)
		echo "FAIL"
		if [[ ${SAKO_TEST_DEBUG:-0} == 1 ]]; then sed '$d' <<<"$res"; else sed '$d' <<<"$res" | grep -E '✘' | sed 's/^/  /'; fi
		FAILN=$((FAILN + 1))
		FAILED+=("$t")
		;;
	esac
done
printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAILN" "$SKIP"
((FAILN == 0))
