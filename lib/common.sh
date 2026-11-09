# shellcheck shell=bash
# shellcheck disable=SC2034 # globals defined here are used by the scripts that source this file
# SAKO Terminal Theme — shared helpers. Sourced by install.sh, update.sh,
# uninstall.sh and scripts/*.sh. Requires bash >= 4.4.

if [[ -n ${SAKO_COMMON_LOADED:-} ]]; then return 0; fi
SAKO_COMMON_LOADED=1

# `&` in ${var//pat/rep} must stay literal (bash >= 5.2 option).
shopt -u patsub_replacement 2>/dev/null || true

SAKO_ROOT=${SAKO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}
SAKO_VERSION=$(tr -d '[:space:]' <"$SAKO_ROOT/VERSION" 2>/dev/null || echo unknown)

SAKO_XDG_CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
SAKO_XDG_DATA=${XDG_DATA_HOME:-$HOME/.local/share}
SAKO_XDG_STATE=${XDG_STATE_HOME:-$HOME/.local/state}
SAKO_STATE_DIR="$SAKO_XDG_STATE/sako-terminal-theme"
SAKO_BACKUP_DIR="$SAKO_STATE_DIR/backups"
SAKO_MANIFEST="$SAKO_STATE_DIR/manifest.tsv"
SAKO_USER_CONF_DIR="$SAKO_XDG_CONFIG/sako-terminal-theme"
SAKO_LOCAL_CONF="$SAKO_USER_CONF_DIR/local.conf"
SAKO_THEME_CONF="$SAKO_ROOT/config/theme.conf"
SAKO_TEMPLATES="$SAKO_ROOT/config/templates"
SAKO_FISH_MODULE="$SAKO_XDG_CONFIG/fish/conf.d/sako-theme.fish"
SAKO_MARK_BEGIN="# >>> sako-terminal-theme >>>"
SAKO_MARK_END="# <<< sako-terminal-theme <<<"
SAKO_OLD_SLOGAN="Empowering Property Growth"
SAKO_ABSENT="<absent>"

# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
	_c_b=$'\e[1m' _c_r=$'\e[0m' _c_red=$'\e[31m' _c_grn=$'\e[32m' _c_yel=$'\e[33m' _c_cyn=$'\e[36m'
else
	_c_b='' _c_r='' _c_red='' _c_grn='' _c_yel='' _c_cyn=''
fi
SAKO_WARNINGS=0
say() { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$_c_b$_c_cyn" "$*" "$_c_r"; }
info() { printf '    %s\n' "$*"; }
ok() { printf '  %s✔%s %s\n' "$_c_grn" "$_c_r" "$*"; }
warn() {
	SAKO_WARNINGS=$((SAKO_WARNINGS + 1))
	printf '  %s!%s %s\n' "$_c_yel" "$_c_r" "$*" >&2
}
err() { printf '  %s✘ %s%s\n' "$_c_red" "$*" "$_c_r" >&2; }
die() {
	err "$*"
	exit 1
}

have() { command -v -- "$1" >/dev/null 2>&1; }

# confirm "question" — honours SAKO_ASSUME_YES; reads from the terminal even
# when stdin is a pipe. Without a terminal and without --yes it refuses.
confirm() {
	local answer
	if [[ ${SAKO_ASSUME_YES:-0} == 1 ]]; then return 0; fi
	if [[ -t 0 ]]; then
		read -r -p "$1 [y/N] " answer
	elif { : </dev/tty; } 2>/dev/null; then
		read -r -p "$1 [y/N] " answer </dev/tty
	else
		err "No terminal to ask: \"$1\". Re-run with --yes to accept."
		return 1
	fi
	[[ $answer =~ ^([yY]|[yY][eE][sS]|[tT]|[tT][aA][kK])$ ]]
}

# --------------------------------------------------------------------------
# Small file helpers
# --------------------------------------------------------------------------
sha256_of() { # file -> hash (empty if missing)
	[[ -f $1 ]] || return 0
	sha256sum <"$1" | cut -d' ' -f1
}

# Paths end up in TSV files; refuse anything that would corrupt them.
check_path() {
	[[ $1 != *$'\t'* && $1 != *$'\n'* ]] || die "Unsupported path (tab/newline): $1"
}

# Resolve a symlink to the file it points at, so writes go *through* the link
# (dotfile managers keep working) instead of replacing it.
real_target() {
	if [[ -L $1 ]]; then readlink -f -- "$1"; else printf '%s\n' "$1"; fi
}

# atomic_write SRC DEST — copy SRC over DEST atomically, keeping DEST's mode.
atomic_write() {
	local src=$1 dest dir tmp mode=644
	dest=$(real_target "$2")
	dir=$(dirname -- "$dest")
	mkdir -p -- "$dir"
	[[ -e $dest ]] && mode=$(stat -c '%a' -- "$dest")
	tmp=$(mktemp -- "$dir/.sako-tmp.XXXXXX")
	cat -- "$src" >"$tmp" || {
		rm -f -- "$tmp"
		return 1
	}
	chmod "$mode" -- "$tmp"
	mv -f -- "$tmp" "$dest"
}

# --------------------------------------------------------------------------
# Configuration (parsed, never sourced)
# --------------------------------------------------------------------------
declare -gA CFG=()
declare -gA RENDER=()

cfg_parse() { # file allow_new_keys(0/1)
	local f=$1 allow_new=$2 line key val n=0
	while IFS= read -r line || [[ -n $line ]]; do
		n=$((n + 1))
		line=${line%$'\r'}
		[[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
		if [[ $line =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
			key=${BASH_REMATCH[1]}
			val=${BASH_REMATCH[2]}
			val=${val%"${val##*[![:space:]]}"}
			if [[ $val =~ ^\"(.*)\"$ || $val =~ ^\'(.*)\'$ ]]; then val=${BASH_REMATCH[1]}; fi
			if [[ $allow_new != 1 && -z ${CFG[$key]+x} ]]; then
				die "$f:$n: unknown setting '$key' (see config/theme.conf for valid keys)"
			fi
			CFG[$key]=$val
		else
			die "$f:$n: cannot parse line (expected KEY=value)"
		fi
	done <"$f"
}

cfg_validate() {
	local k v
	for k in "${!CFG[@]}"; do
		v=${CFG[$k]}
		[[ $v != *[[:cntrl:]]* ]] || die "Setting $k contains control characters"
		[[ $v != *@@* ]] || die "Setting $k must not contain '@@'"
		case $k in
		SAKO_COLOR* | SAKO_NAVY | SAKO_CYAN | SAKO_GREY | SAKO_GIT_ORANGE | SAKO_WHITE | SAKO_BACKGROUND | \
			SAKO_USER_FG | SAKO_DIR_FG | SAKO_FISH_AUTOSUGGESTION | SAKO_TERM_*)
			[[ $v =~ ^#[0-9A-Fa-f]{6}$ ]] || die "Setting $k must be a colour like #1A2B3C (got '$v')"
			;;
		SAKO_FONT_SIZE)
			[[ $v =~ ^[0-9]{1,2}(\.[0-9])?$ ]] || die "SAKO_FONT_SIZE must be a number like 11 or 11.5"
			;;
		SAKO_FONT_FAMILY)
			[[ -n $v && $v != *[\"\'\\,\;]* ]] || die "SAKO_FONT_FAMILY must not be empty or contain quotes, backslashes, commas or semicolons"
			;;
		SAKO_SLOGAN | SAKO_URL | SAKO_TIME_FORMAT)
			[[ -n $v ]] || die "Setting $k must not be empty"
			;;
		esac
	done
}

# Escape text for a Starship format string, then for a TOML basic string.
starship_text() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\$/\\\$}
	s=${s//\[/\\\[}
	s=${s//\]/\\\]}
	s=${s//\(/\\\(}
	s=${s//\)/\\\)}
	toml_basic "$s"
}
toml_basic() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	printf '%s' "$s"
}

# Load theme.conf (+ local.conf override) and compute render variables.
load_config() {
	CFG=()
	RENDER=()
	[[ -f $SAKO_THEME_CONF ]] || die "Missing $SAKO_THEME_CONF"
	cfg_parse "$SAKO_THEME_CONF" 1
	if [[ -f $SAKO_LOCAL_CONF ]]; then
		cfg_parse "$SAKO_LOCAL_CONF" 0
		SAKO_LOCAL_CONF_USED=1
	else
		SAKO_LOCAL_CONF_USED=0
	fi
	cfg_validate
	local k
	for k in "${!CFG[@]}"; do RENDER[$k]=${CFG[$k]}; done
	RENDER[SAKO_URL_FMT]=$(starship_text "${CFG[SAKO_URL]}")
	RENDER[SAKO_SLOGAN_FMT]=$(starship_text "${CFG[SAKO_SLOGAN]}")
	RENDER[SAKO_TIME_FORMAT_TOML]=$(toml_basic "${CFG[SAKO_TIME_FORMAT]}")
	local hex=${CFG[SAKO_FISH_AUTOSUGGESTION]#\#}
	RENDER[SAKO_FISH_AUTOSUGGESTION_HEX]=${hex,,}
	RENDER[SAKO_KONSOLE_FONT]="${CFG[SAKO_FONT_FAMILY]},${CFG[SAKO_FONT_SIZE]},-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
	SAKO_BRANDING_LINE="${CFG[SAKO_URL]} | ${CFG[SAKO_SLOGAN]} | "
}

# render_template SRC DEST — replace @@KEY@@ placeholders from RENDER.
render_template() {
	local src=$1 dest=$2 line key
	: >"$dest"
	while IFS= read -r line || [[ -n $line ]]; do
		while [[ $line =~ @@([A-Z0-9_]+)@@ ]]; do
			key=${BASH_REMATCH[1]}
			[[ -n ${RENDER[$key]+x} ]] || die "Template $src uses unknown placeholder @@${key}@@"
			line=${line//"@@${key}@@"/"${RENDER[$key]}"}
		done
		printf '%s\n' "$line" >>"$dest"
	done <"$src"
}

# --------------------------------------------------------------------------
# Manifest: what the project manages. TSV, one entry per line:
#   file   <path> <sha256> <orig>        orig = absent | backup:<id>
#   ini    <path> <group> <key> <new> <old>   old = <absent> if key was unset
#   block  <path> <orig>                 orig = absent | present (file)
#   fontdir <path>
#   bin    <path>
# --------------------------------------------------------------------------
manifest_init() {
	mkdir -p -- "$SAKO_STATE_DIR"
	chmod 700 -- "$SAKO_STATE_DIR"
	[[ -f $SAKO_MANIFEST ]] || : >"$SAKO_MANIFEST"
}

# manifest_lookup KIND PATH [GROUP KEY] -> prints the matching line
manifest_lookup() {
	[[ -f $SAKO_MANIFEST ]] || return 1
	awk -F'\t' -v k="$1" -v p="$2" -v g="${3-}" -v key="${4-}" '
		$1==k && $2==p && (k!="ini" || ($3==g && $4==key)) { print; found=1; exit }
		END { exit !found }' "$SAKO_MANIFEST"
}

# manifest_put KIND PATH FIELDS... — replace existing entry or append.
manifest_put() {
	local kind=$1 path=$2 tmp line
	shift 2
	manifest_init
	line=$(printf '%s\t' "$kind" "$path" "$@")
	line=${line%$'\t'}
	tmp=$(mktemp -- "$SAKO_STATE_DIR/.manifest.XXXXXX")
	if [[ $kind == ini ]]; then
		awk -F'\t' -v k="$kind" -v p="$path" -v g="$1" -v key="$2" \
			'!($1==k && $2==p && $3==g && $4==key)' "$SAKO_MANIFEST" >"$tmp"
	else
		awk -F'\t' -v k="$kind" -v p="$path" '!($1==k && $2==p)' "$SAKO_MANIFEST" >"$tmp"
	fi
	printf '%s\n' "$line" >>"$tmp"
	mv -f -- "$tmp" "$SAKO_MANIFEST"
}

manifest_del() { # KIND PATH [GROUP KEY]
	[[ -f $SAKO_MANIFEST ]] || return 0
	local tmp
	tmp=$(mktemp -- "$SAKO_STATE_DIR/.manifest.XXXXXX")
	awk -F'\t' -v k="$1" -v p="$2" -v g="${3-}" -v key="${4-}" \
		'!($1==k && $2==p && (k!="ini" || ($3==g && $4==key)))' "$SAKO_MANIFEST" >"$tmp"
	mv -f -- "$tmp" "$SAKO_MANIFEST"
}

# --------------------------------------------------------------------------
# INI files (KDE Konsole profiles, konsolerc)
# --------------------------------------------------------------------------
ini_get() { # FILE GROUP KEY -> value; status 1 if absent
	[[ -f $1 ]] || return 1
	awk -v g="[$2]" -v k="$3" '
		/^\[/ { ing = ($0 == g); next }
		ing { i = index($0, "="); if (i > 0 && substr($0, 1, i - 1) == k) { print substr($0, i + 1); found = 1; exit } }
		END { exit !found }' "$1"
}

# ini_render FILE GROUP KEY VALUE|<absent> OUT — write FILE with the key set
# (or removed when VALUE is <absent>) to OUT. Other lines stay untouched.
ini_render() {
	local file=$1 group=$2 key=$3 out=$5
	local input=/dev/null
	[[ -f $file ]] && input=$file
	SAKO_V=$4 awk -v g="[$group]" -v k="$key" -v absent="$SAKO_ABSENT" '
		BEGIN { v = ENVIRON["SAKO_V"]; del = (v == absent) }
		/^\[/ {
			if (ing && !done && !del) { print k "=" v; done = 1 }
			ing = ($0 == g); if (ing) seen = 1
			print; next
		}
		ing { i = index($0, "="); if (i > 0 && substr($0, 1, i - 1) == k) { if (!del && !done) { print k "=" v; done = 1 }; next } }
		{ print }
		END {
			if (del || done) exit
			if (ing) { print k "=" v; exit }
			if (NR > 0) print ""
			print g; print k "=" v
		}' "$input" >"$out"
}

# --------------------------------------------------------------------------
# Marker blocks inside user-owned files (kitty.conf, alacritty.toml)
# --------------------------------------------------------------------------
block_present() { [[ -f $1 ]] && grep -qxF -- "$SAKO_MARK_BEGIN" "$1"; }

block_strip() { # FILE OUT — copy FILE without our block
	awk -v b="$SAKO_MARK_BEGIN" -v e="$SAKO_MARK_END" '
		$0 == b { skip = 1; next }
		$0 == e { skip = 0; next }
		!skip' "$1" >"$2"
}

# block_render FILE BODYFILE MODE OUT [HEADER]
#   MODE append — block at the end of the file
#   MODE header — block right after the first line equal to HEADER (e.g.
#                 "[general]"); if there is none, HEADER + block are appended
block_render() {
	local file=$1 body=$2 mode=$3 out=$4 header=${5-} stripped
	stripped=$(mktemp)
	if [[ -f $file ]]; then block_strip "$file" "$stripped"; fi
	{
		printf '%s\n' "$SAKO_MARK_BEGIN"
		cat -- "$body"
		printf '%s\n' "$SAKO_MARK_END"
	} >"$stripped.block"
	if [[ $mode == header ]] && awk -v h="$header" '{ sub(/[ \t\r]+$/, "") } $0 == h { f = 1; exit } END { exit !f }' "$stripped"; then
		awk -v h="$header" -v blk="$stripped.block" '
			{ print; t = $0; sub(/[ \t\r]+$/, "", t) }
			!done && t == h { while ((getline l < blk) > 0) print l; done = 1 }' "$stripped" >"$out"
	else
		cat -- "$stripped" >"$out"
		if [[ -s $stripped && -n $(tail -c1 -- "$stripped") ]]; then printf '\n' >>"$out"; fi
		if [[ $mode == header ]]; then
			[[ -s $stripped ]] && printf '\n' >>"$out"
			printf '%s\n' "$header" >>"$out"
		fi
		cat -- "$stripped.block" >>"$out"
	fi
	rm -f -- "$stripped" "$stripped.block"
}

# --------------------------------------------------------------------------
# Backups: $SAKO_BACKUP_DIR/<id>/{info,backup.tsv,files/<abs path>}
#   backup.tsv: <path> <present|absent> <sha256> <mode>
# --------------------------------------------------------------------------
backup_create() { # REASON PATH... -> sets BACKUP_ID
	local reason=$1 id dir p real
	shift
	id=$(date +%Y%m%d-%H%M%S)
	mkdir -p -- "$SAKO_BACKUP_DIR"
	chmod 700 -- "$SAKO_STATE_DIR" "$SAKO_BACKUP_DIR"
	if [[ -e $SAKO_BACKUP_DIR/$id ]]; then
		local n=1
		while [[ -e $SAKO_BACKUP_DIR/$id-$n ]]; do n=$((n + 1)); done
		id=$id-$n
	fi
	dir=$SAKO_BACKUP_DIR/$id
	mkdir -m 700 -- "$dir"
	mkdir -m 700 -- "$dir/files"
	{
		printf 'id=%s\n' "$id"
		printf 'date=%s\n' "$(date -Iseconds)"
		printf 'reason=%s\n' "$reason"
		printf 'version=%s\n' "$SAKO_VERSION"
	} >"$dir/info"
	: >"$dir/backup.tsv"
	declare -A seen=()
	for p in "$@"; do
		[[ -n ${seen[$p]+x} ]] && continue
		seen[$p]=1
		check_path "$p"
		if [[ -e $p ]]; then
			real=$(real_target "$p")
			mkdir -p -- "$dir/files$(dirname -- "$p")"
			cp -- "$real" "$dir/files$p"
			chmod 600 -- "$dir/files$p"
			printf '%s\tpresent\t%s\t%s\n' "$p" "$(sha256_of "$real")" "$(stat -c '%a' -- "$real")" >>"$dir/backup.tsv"
		else
			printf '%s\tabsent\t-\t-\n' "$p" >>"$dir/backup.tsv"
		fi
	done
	BACKUP_ID=$id
}

backup_list() {
	local d id date reason n
	[[ -d $SAKO_BACKUP_DIR ]] || return 0
	for d in "$SAKO_BACKUP_DIR"/*/; do
		[[ -f $d/info ]] || continue
		id=$(sed -n 's/^id=//p' "$d/info")
		date=$(sed -n 's/^date=//p' "$d/info")
		reason=$(sed -n 's/^reason=//p' "$d/info")
		n=$(wc -l <"$d/backup.tsv")
		printf '%s\t%s\t%s files\t%s\n' "$id" "$date" "$n" "$reason"
	done
}

# backup_restore ID — restore every path to its state at backup time.
# Takes a "pre-restore" backup first so the restore itself can be undone.
backup_restore() {
	local id=$1 dir=$SAKO_BACKUP_DIR/$1 path state sha mode real failed=0
	[[ -f $dir/backup.tsv ]] || die "Backup '$id' not found in $SAKO_BACKUP_DIR"
	local -a paths=()
	while IFS=$'\t' read -r path _ _ _; do paths+=("$path"); done <"$dir/backup.tsv"
	backup_create "pre-restore (before restoring $id)" "${paths[@]}"
	local pre=$BACKUP_ID
	while IFS=$'\t' read -r path state sha mode; do
		if [[ $state == present ]]; then
			atomic_write "$dir/files$path" "$path"
			real=$(real_target "$path")
			chmod "$mode" -- "$real"
			if [[ $(sha256_of "$real") == "$sha" ]]; then
				ok "restored $path"
			else
				err "checksum mismatch after restoring $path"
				failed=1
			fi
		elif [[ -e $path || -L $path ]]; then
			rm -f -- "$path"
			ok "removed $path (did not exist at backup time)"
		fi
	done <"$dir/backup.tsv"
	manifest_reconcile
	info "Undo this restore with: scripts/restore.sh $pre"
	return $failed
}

# Drop manifest entries that no longer describe the files on disk.
manifest_reconcile() {
	[[ -f $SAKO_MANIFEST ]] || return 0
	local line kind path a b c keep tmp
	tmp=$(mktemp -- "$SAKO_STATE_DIR/.manifest.XXXXXX")
	while IFS= read -r line; do
		IFS=$'\t' read -r kind path a b c _ <<<"$line"
		keep=0
		case $kind in
		file) [[ $(sha256_of "$(real_target "$path")") == "$a" ]] && keep=1 ;;
		ini) [[ $(ini_get "$path" "$a" "$b" 2>/dev/null) == "$c" ]] && keep=1 ;;
		block) block_present "$path" && keep=1 ;;
		fontdir | bin) [[ -e $path ]] && keep=1 ;;
		esac
		((keep)) && printf '%s\n' "$line"
	done <"$SAKO_MANIFEST" >"$tmp"
	mv -f -- "$tmp" "$SAKO_MANIFEST"
}
