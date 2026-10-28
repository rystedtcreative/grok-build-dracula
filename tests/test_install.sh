#!/bin/sh
# Tests install.sh against throwaway HOME directories. Never touches your real ~/.grok.
# Usage: sh tests/test_install.sh [shell]   (default shell: sh; CI also runs dash and bash)
set -u
SH=${1:-sh}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
INSTALL="$ROOT/install.sh"
PASS=0; FAIL=0
WORK=$(mktemp -d)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT; echo "work: $WORK"

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
newhome() { H="$WORK/$1"; mkdir -p "$H/.grok"; }
run() { env -i PATH="$PATH" HOME="$H" TERM=dumb "$SH" "$INSTALL" "$@" > "$H/out.log" 2>&1; }
toml() { python3 -c 'import sys,tomllib,json; d=tomllib.load(open(sys.argv[1],"rb")); print(eval(sys.argv[2]))' "$H/.grok/config.toml" "$1"; }
count() { grep -c "^\[$1\]" "$H/.grok/config.toml"; }
snapshot() { (cd "$H" && find . -path ./out.log -prune -o -type f -print | sort | while read -r f; do printf '%s %s\n' "$f" "$(sha256sum < "$f" | cut -c1-16)"; done); }

echo "== fresh HOME with an existing config ($SH)"
newhome a
cat > "$H/.grok/config.toml" <<'T'
# my grok config
[ui]
fullscreen = true   # keep me
theme = "tokyonight"

[model]
default = "grok-4"

[features]
something_else = true
T
ORIG=$(cat "$H/.grok/config.toml")
before=$(snapshot)
run --variant dracula --terminal kitty --dry-run; rc=$?
check "dry-run exits 0" '[ $rc = 0 ]'
check "dry-run changes nothing" '[ "$(snapshot)" = "$before" ]'
check "dry-run says it would edit" 'grep -q "would set \[ui\] theme" "$H/out.log"'

run --variant dracula --terminal kitty; rc=$?
check "install exits 0" '[ $rc = 0 ]'
check "ui.theme = terminal" '[ "$(toml "d[\"ui\"][\"theme\"]")" = terminal ]'
check "features.terminal_theme = true" '[ "$(toml "d[\"features\"][\"terminal_theme\"]")" = True ]'
check "other keys kept" '[ "$(toml "(d[\"ui\"][\"fullscreen\"], d[\"model\"][\"default\"], d[\"features\"][\"something_else\"])")" = "(True, '"'"'grok-4'"'"', True)" ]'
check "comments kept" 'grep -q "^# my grok config" "$H/.grok/config.toml" && grep -q "# keep me" "$H/.grok/config.toml"'
check "one config backup" '[ "$(ls "$H/.grok" | grep -c "config.toml.bak-grok-dracula-")" = 1 ]'
check "backup equals original" '[ "$(cat "$H"/.grok/config.toml.bak-grok-dracula-*)" = "$ORIG" ]'
check "kitty scheme installed" 'cmp -s "$H/.config/kitty/themes/grok-dracula.conf" "$ROOT/themes/kitty/grok-dracula.conf"'
check "activation steps printed" 'grep -q "include themes/grok-dracula.conf" "$H/out.log"'
check "pager.toml not installed without --with-pager" '[ ! -e "$H/.grok/pager.toml" ]'

after1=$(snapshot); cfg1=$(cat "$H/.grok/config.toml")
run --variant dracula --terminal kitty; rc=$?
check "second run exits 0" '[ $rc = 0 ]'
check "second run is a no-op" '[ "$(snapshot)" = "$after1" ]'
check "no duplicate [ui]" '[ "$(count ui)" = 1 ]'
check "no duplicate [features]" '[ "$(count features)" = 1 ]'
check "still one backup" '[ "$(ls "$H/.grok" | grep -c "config.toml.bak-grok-dracula-")" = 1 ]'

echo "== switching variant and pager"
run --variant alucard --terminal kitty --with-pager; rc=$?
check "variant switch exits 0" '[ $rc = 0 ]'
check "alucard installed" '[ -f "$H/.config/kitty/themes/grok-alucard.conf" ]'
check "pager.toml installed when absent" 'cmp -s "$H/.grok/pager.toml" "$ROOT/extras/pager.toml"'

echo "== no silent overwrite"
mkdir -p "$H/.config/ghostty/themes"; echo "user's own file" > "$H/.config/ghostty/themes/grok-dracula"
run --variant dracula --terminal ghostty
check "foreign file untouched" '[ "$(cat "$H/.config/ghostty/themes/grok-dracula")" = "user'"'"'s own file" ]'
check "warns about it" 'grep -q "Left untouched" "$H/out.log"'
run --variant dracula --terminal ghostty --force
check "--force replaces it" 'cmp -s "$H/.config/ghostty/themes/grok-dracula" "$ROOT/themes/ghostty/grok-dracula"'
check "--force keeps a backup" 'ls "$H/.config/ghostty/themes/" | grep -q "grok-dracula.bak-grok-dracula-"'
echo "edited" >> "$H/.config/kitty/themes/grok-dracula.conf"

echo "== uninstall"
before=$(snapshot)
run --uninstall --dry-run
check "uninstall dry-run changes nothing" '[ "$(snapshot)" = "$before" ]'
run --uninstall; rc=$?
check "uninstall exits 0" '[ $rc = 0 ]'
check "previous theme restored" '[ "$(toml "d[\"ui\"][\"theme\"]")" = tokyonight ]'
check "terminal_theme removed" '[ "$(toml "\"terminal_theme\" in d[\"features\"]")" = False ]'
check "other keys still there" '[ "$(toml "d[\"features\"][\"something_else\"]")" = True ]'
check "installed alucard scheme removed" '[ ! -e "$H/.config/kitty/themes/grok-alucard.conf" ]'
check "pager.toml we added removed" '[ ! -e "$H/.grok/pager.toml" ]'
check "user-edited scheme kept" '[ -f "$H/.config/kitty/themes/grok-dracula.conf" ]'
check "config semantically back to original" 'python3 -c "import tomllib,sys; a=tomllib.load(open(sys.argv[1],\"rb\")); b=tomllib.loads(sys.argv[2]); sys.exit(a!=b)" "$H/.grok/config.toml" "$ORIG"'
run --uninstall; rc=$?
check "second uninstall is harmless" '[ $rc = 0 ] && [ "$(toml "d[\"ui\"][\"theme\"]")" = tokyonight ]'

echo "== no config at all, then --restore-backup"
newhome b
run --variant dracula-soft --terminal none; rc=$?
check "creates config from nothing" '[ $rc = 0 ] && [ "$(toml "d[\"ui\"][\"theme\"]")" = terminal ]'
run --uninstall; rc=$?
check "uninstall removes the theme key (default groknight)" '[ $rc = 0 ] && [ "$(toml "\"theme\" in d.get(\"ui\",{})")" = False ]'

newhome c
printf '[ui]\ntheme = "catppuccin"\n' > "$H/.grok/config.toml"
run --terminal none
printf '\n[mcp]\nfoo = 1\n' >> "$H/.grok/config.toml"
run --uninstall --restore-backup; rc=$?
check "--restore-backup restores the pre-install file" '[ $rc = 0 ] && [ "$(cat "$H/.grok/config.toml")" = "$(printf "[ui]\ntheme = \"catppuccin\"")" ]'
check "--restore-backup saves the current file first" 'ls "$H/.grok" | grep -q "bak-grok-dracula-uninstall-"'

echo "== layouts we refuse to edit"
newhome d
printf 'ui.theme = "x"\n' > "$H/.grok/config.toml"
run --terminal none; rc=$?
check "dotted ui key left alone with manual steps" '[ "$(cat "$H/.grok/config.toml")" = "ui.theme = \"x\"" ] && grep -q "Edit .* by hand" "$H/out.log"'
newhome e
printf '[ui\nbroken\n' > "$H/.grok/config.toml"
run --terminal none
check "invalid TOML left alone" '[ "$(head -1 "$H/.grok/config.toml")" = "[ui" ]'

echo "== no python3"
newhome f
mkdir -p "$WORK/nopy"; for c in sh dash bash cat cp mv rm mkdir grep sed awk cut tr date dirname sha256sum cmp ls head tail mktemp rmdir find sort; do p=$(command -v $c) && ln -sf "$p" "$WORK/nopy/$c"; done
printf '[ui]\ntheme = "x"\n' > "$H/.grok/config.toml"
env -i PATH="$WORK/nopy" HOME="$H" "$SH" "$INSTALL" --terminal kitty > "$H/out.log" 2>&1; rc=$?
check "without python3: exits 0, config untouched, manual steps" '[ $rc = 0 ] && [ "$(cat "$H/.grok/config.toml")" = "$(printf "[ui]\ntheme = \"x\"")" ] && grep -q "theme = \"terminal\"" "$H/out.log"'
check "without python3: scheme still installed" '[ -f "$H/.config/kitty/themes/grok-dracula.conf" ]'

echo "== bad flags"
newhome g
run --variant nope; rc=$?
check "rejects unknown variant" '[ $rc != 0 ]'
run --bogus; rc=$?
check "rejects unknown flag" '[ $rc != 0 ]'

echo
echo "$PASS passed, $FAIL failed ($SH)"
[ "$FAIL" = 0 ]
