# shellcheck shell=bash
# shellcheck disable=SC2034 # globals defined here are used by the scripts that source this file
# SAKO Terminal Theme — planned file operations.
#
# Every change is first registered as an operation, then planned (compared
# with what is on disk and in the manifest), shown to the user, backed up and
# only then applied. Nothing is written during planning or --dry-run.

OP_KIND=() OP_TARGET=() OP_A=() OP_B=() OP_C=() OP_LABEL=() OP_STATUS=()
SAKO_FORCE=${SAKO_FORCE:-0}

op_reset() { OP_KIND=() OP_TARGET=() OP_A=() OP_B=() OP_C=() OP_LABEL=() OP_STATUS=(); }

# op_file SRC TARGET LABEL — TARGET becomes a copy of SRC (whole file owned).
op_file() {
	check_path "$2"
	OP_KIND+=(file) OP_TARGET+=("$2") OP_A+=("$1") OP_B+=('') OP_C+=('') OP_LABEL+=("$3")
}
# op_ini FILE GROUP KEY VALUE LABEL — set one key in an INI file.
op_ini() {
	check_path "$1"
	OP_KIND+=(ini) OP_TARGET+=("$1") OP_A+=("$2") OP_B+=("$3") OP_C+=("$4") OP_LABEL+=("$5")
}
# op_block FILE BODYFILE MODE HEADER LABEL — marker block in a user file.
op_block() {
	check_path "$1"
	OP_KIND+=(block) OP_TARGET+=("$1") OP_A+=("$2") OP_B+=("$3") OP_C+=("$4") OP_LABEL+=("$5")
}

# Status values: create | update | replace | set | unchanged | skip-modified
ops_plan() {
	local i t cur new entry msha
	for i in "${!OP_KIND[@]}"; do
		t=${OP_TARGET[$i]}
		case ${OP_KIND[$i]} in
		file)
			cur=$(sha256_of "$(real_target "$t")")
			new=$(sha256_of "${OP_A[$i]}")
			if [[ $cur == "$new" ]]; then
				OP_STATUS[i]=unchanged
			elif [[ -z $cur && ! -e $t ]]; then
				OP_STATUS[i]=create
			elif entry=$(manifest_lookup file "$t"); then
				msha=$(cut -f3 <<<"$entry")
				if [[ $cur == "$msha" || $SAKO_FORCE == 1 ]]; then
					OP_STATUS[i]=update
				else
					OP_STATUS[i]=skip-modified
				fi
			else
				OP_STATUS[i]=replace # not ours yet: backed up, then replaced
			fi
			;;
		ini)
			cur=$(ini_get "$t" "${OP_A[$i]}" "${OP_B[$i]}" 2>/dev/null) || cur=$SAKO_ABSENT
			if [[ $cur == "${OP_C[$i]}" ]]; then
				OP_STATUS[i]=unchanged
			elif entry=$(manifest_lookup ini "$t" "${OP_A[$i]}" "${OP_B[$i]}") &&
				[[ $cur != "$(cut -f5 <<<"$entry")" && $SAKO_FORCE != 1 ]]; then
				OP_STATUS[i]=skip-modified # user changed the value we set earlier
			else
				OP_STATUS[i]='set'
			fi
			;;
		block)
			local tmp
			tmp=$(mktemp)
			block_render "$t" "${OP_A[$i]}" "${OP_B[$i]}" "$tmp" "${OP_C[$i]}"
			if [[ -f $t && $(sha256_of "$tmp") == "$(sha256_of "$(real_target "$t")")" ]]; then
				OP_STATUS[i]=unchanged
			elif [[ -f $t ]]; then
				OP_STATUS[i]=update
			else
				OP_STATUS[i]=create
			fi
			rm -f -- "$tmp"
			;;
		esac
	done
}

ops_print() {
	local i s t
	for i in "${!OP_KIND[@]}"; do
		s=${OP_STATUS[$i]}
		t=${OP_TARGET[$i]/#$HOME/\~}
		case $s in
		unchanged) info "= ${OP_LABEL[$i]}: $t (unchanged)" ;;
		create) info "+ ${OP_LABEL[$i]}: create $t" ;;
		update) info "~ ${OP_LABEL[$i]}: update $t" ;;
		replace) info "~ ${OP_LABEL[$i]}: replace $t (current file is backed up first)" ;;
		set) info "~ ${OP_LABEL[$i]}: $t [${OP_A[$i]}] ${OP_B[$i]}=${OP_C[$i]}" ;;
		skip-modified) warn "${OP_LABEL[$i]}: $t was changed by you since the last install — left alone (use --force to overwrite; it would be backed up)" ;;
		esac
	done
}

ops_pending() { # -> number of operations that will write something
	local i n=0
	for i in "${!OP_STATUS[@]}"; do
		case ${OP_STATUS[$i]} in create | update | replace | set) n=$((n + 1)) ;; esac
	done
	echo "$n"
}

# ops_apply — back up every target that will change, then apply.
# Sets BACKUP_ID ('' if nothing changed).
ops_apply() {
	local i t entry tmp orig old
	local -a targets=()
	BACKUP_ID=''
	for i in "${!OP_STATUS[@]}"; do
		case ${OP_STATUS[$i]} in create | update | replace | set) targets+=("${OP_TARGET[$i]}") ;; esac
	done
	((${#targets[@]})) || return 0
	manifest_init
	backup_create "install $SAKO_VERSION" "${targets[@]}"
	ok "Backup created: ${SAKO_BACKUP_DIR/#$HOME/\~}/$BACKUP_ID"
	SAKO_CURRENT_BACKUP=$BACKUP_ID

	for i in "${!OP_KIND[@]}"; do
		t=${OP_TARGET[$i]}
		case ${OP_STATUS[$i]} in create | update | replace | set) ;; *) continue ;; esac
		case ${OP_KIND[$i]} in
		file)
			if entry=$(manifest_lookup file "$t"); then
				orig=$(cut -f4 <<<"$entry")
			elif [[ -e $t ]]; then
				orig="backup:$BACKUP_ID"
			else
				orig=absent
			fi
			atomic_write "${OP_A[$i]}" "$t"
			manifest_put file "$t" "$(sha256_of "$(real_target "$t")")" "$orig"
			;;
		ini)
			if entry=$(manifest_lookup ini "$t" "${OP_A[$i]}" "${OP_B[$i]}"); then
				old=$(cut -f6 <<<"$entry")
			else
				old=$(ini_get "$t" "${OP_A[$i]}" "${OP_B[$i]}" 2>/dev/null) || old=$SAKO_ABSENT
			fi
			tmp=$(mktemp)
			ini_render "$t" "${OP_A[$i]}" "${OP_B[$i]}" "${OP_C[$i]}" "$tmp"
			atomic_write "$tmp" "$t"
			rm -f -- "$tmp"
			manifest_put ini "$t" "${OP_A[$i]}" "${OP_B[$i]}" "${OP_C[$i]}" "$old"
			;;
		block)
			if entry=$(manifest_lookup block "$t"); then
				orig=$(cut -f3 <<<"$entry")
			elif [[ -e $t ]]; then
				orig=present
			else
				orig=absent
			fi
			tmp=$(mktemp)
			block_render "$t" "${OP_A[$i]}" "${OP_B[$i]}" "$tmp" "${OP_C[$i]}"
			atomic_write "$tmp" "$t"
			rm -f -- "$tmp"
			manifest_put block "$t" "$orig"
			;;
		esac
		ok "${OP_LABEL[$i]}: ${t/#$HOME/\~}"
	done
}
