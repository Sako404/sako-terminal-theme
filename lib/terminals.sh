# shellcheck shell=bash
# shellcheck disable=SC2034 # globals defined here are used by the scripts that source this file
# SAKO Terminal Theme — optional terminal emulator integrations (layer B).
# Each function renders its files into $BUILD and registers operations.
# They never require the emulator to be installed or running.

is_nerd_font_name() { [[ $1 =~ (Nerd\ Font|[[:alnum:]]\ ?NF[MP]?(,|$)) ]]; }

term_konsole() {
	local data="$SAKO_XDG_DATA/konsole" rc="$SAKO_XDG_CONFIG/konsolerc" prof cur_font
	mkdir -p -- "$BUILD/konsole"
	render_template "$SAKO_TEMPLATES/terminals/konsole.colorscheme.tmpl" "$BUILD/konsole/SAKO.colorscheme"
	op_file "$BUILD/konsole/SAKO.colorscheme" "$data/SAKO.colorscheme" "Konsole colour scheme"

	prof=$(ini_get "$rc" "Desktop Entry" DefaultProfile 2>/dev/null) || prof=''
	if [[ -n $prof && $prof != SAKO.profile && $prof != */* && -f $data/$prof ]]; then
		# Keep the user's own profile (and all its other settings);
		# only switch the colour scheme, and the font if it has no Nerd glyphs.
		op_ini "$data/$prof" Appearance ColorScheme SAKO "Konsole profile '$prof'"
		cur_font=$(ini_get "$data/$prof" Appearance Font 2>/dev/null) || cur_font=''
		if ! is_nerd_font_name "${cur_font%%,*}"; then
			op_ini "$data/$prof" Appearance Font "${RENDER[SAKO_KONSOLE_FONT]}" "Konsole profile '$prof' font"
		fi
	else
		render_template "$SAKO_TEMPLATES/terminals/konsole.profile.tmpl" "$BUILD/konsole/SAKO.profile"
		op_file "$BUILD/konsole/SAKO.profile" "$data/SAKO.profile" "Konsole profile"
		op_ini "$rc" "Desktop Entry" DefaultProfile SAKO.profile "Konsole default profile"
	fi
	TERM_NOTES+=("Konsole: open a new tab or window to see the change (Settings → Edit Current Profile → Appearance shows 'SAKO').")
}

term_kitty() {
	local dir="$SAKO_XDG_CONFIG/kitty"
	mkdir -p -- "$BUILD/kitty"
	render_template "$SAKO_TEMPLATES/terminals/kitty.conf.tmpl" "$BUILD/kitty/sako-theme.conf"
	printf 'include sako-theme.conf\n' >"$BUILD/kitty/block"
	op_file "$BUILD/kitty/sako-theme.conf" "$dir/sako-theme.conf" "Kitty theme"
	op_block "$dir/kitty.conf" "$BUILD/kitty/block" append '' "Kitty include"
	TERM_NOTES+=("Kitty: reload with ctrl+shift+F5 or open a new window.")
}

alacritty_minor_version() { # prints e.g. 15 for 0.15.1, empty if unknown
	have alacritty || return 0
	alacritty --version 2>/dev/null | sed -nE 's/^alacritty 0\.([0-9]+).*/\1/p'
}

term_alacritty() {
	local dir="$SAKO_XDG_CONFIG/alacritty" main minor stripped
	main="$dir/alacritty.toml"
	minor=$(alacritty_minor_version)
	if [[ -n $minor && $minor -lt 14 ]]; then
		warn "Alacritty 0.$minor found; the integration needs >= 0.14 (general.import). Skipped — import config/terminals output manually."
		return 0
	fi
	if [[ ! -f $main && -f $dir/alacritty.yml ]]; then
		warn "Only the legacy alacritty.yml exists. Run 'alacritty migrate' first. Alacritty integration skipped."
		return 0
	fi
	mkdir -p -- "$BUILD/alacritty"
	render_template "$SAKO_TEMPLATES/terminals/alacritty.toml.tmpl" "$BUILD/alacritty/sako-theme.toml"
	op_file "$BUILD/alacritty/sako-theme.toml" "$dir/sako-theme.toml" "Alacritty theme"

	stripped=$(mktemp)
	[[ -f $main ]] && block_strip "$main" "$stripped"
	if grep -qE '^[[:space:]]*import[[:space:]]*=' "$stripped"; then
		warn "alacritty.toml already has an 'import' list. Add \"$dir/sako-theme.toml\" to it yourself; the file was not edited."
		rm -f -- "$stripped"
		return 0
	fi
	printf 'import = ["%s"]\n' "$(toml_basic "$dir/sako-theme.toml")" >"$BUILD/alacritty/block"
	op_block "$main" "$BUILD/alacritty/block" header '[general]' "Alacritty import"
	# Values in the main file win over imports — tell the user, do not delete.
	local overrides
	overrides=$(grep -oE '^\[(colors|font)[^]]*\]' "$stripped" | sort -u | tr '\n' ' ' || true)
	if [[ -n $overrides ]]; then
		warn "alacritty.toml defines ${overrides% } — those keys override the imported SAKO theme. Remove or comment them out to see the SAKO palette."
	fi
	rm -f -- "$stripped"
	TERM_NOTES+=("Alacritty: reloads automatically when live_config_reload is on, otherwise open a new window.")
}

term_wezterm() {
	local dir="$SAKO_XDG_CONFIG/wezterm"
	mkdir -p -- "$BUILD/wezterm"
	render_template "$SAKO_TEMPLATES/terminals/wezterm.toml.tmpl" "$BUILD/wezterm/SAKO.toml"
	op_file "$BUILD/wezterm/SAKO.toml" "$dir/colors/SAKO.toml" "WezTerm colour scheme"
	if [[ -f $dir/wezterm.lua || -f $HOME/.wezterm.lua ]]; then
		TERM_NOTES+=("WezTerm: your wezterm.lua was not edited (Lua cannot be merged safely). Add:  config.color_scheme = 'SAKO'  and  config.font = wezterm.font '${CFG[SAKO_FONT_FAMILY]}'")
	else
		render_template "$SAKO_TEMPLATES/terminals/wezterm.lua.tmpl" "$BUILD/wezterm/wezterm.lua"
		op_file "$BUILD/wezterm/wezterm.lua" "$dir/wezterm.lua" "WezTerm config"
		TERM_NOTES+=("WezTerm: picks up the new config automatically.")
	fi
}
