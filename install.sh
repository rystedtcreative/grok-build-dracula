#!/bin/sh
# grok-build-dracula installer
# Dracula, Dracula Soft and Alucard for the Grok Build CLI.
#
# Grok Build has no custom theme files; its themes are compiled in. This
# installer switches Grok to its built-in `terminal` theme (which draws every
# color from your terminal's 16-color ANSI palette) and installs a matching
# Dracula color scheme for your terminal.
#
# Usage: sh install.sh [options]
#   --variant dracula|dracula-soft|alucard   palette to install (default: dracula)
#   --terminal NAME|auto|all|none            iterm2, ghostty, wezterm, kitty, alacritty,
#                                            windows-terminal (default: auto)
#   --with-pager      also install extras/pager.toml as ~/.grok/pager.toml if none exists
#   --dry-run         show what would happen, change nothing
#   --force           replace scheme files that exist and differ (old copy is backed up)
#   --uninstall       undo: restore the previous Grok theme, remove files this installer added
#   --restore-backup  with --uninstall: put back the config.toml backup taken before first install
#   -h, --help
#
# MIT License. Palette: Dracula Theme (https://draculatheme.com), MIT.
set -u

REPO_URL="${GROK_DRACULA_REPO:-https://github.com/rystedtcreative/grok-build-dracula.git}"
REPO_SLUG="rystedtcreative/grok-build-dracula"
REPO_REF="${GROK_DRACULA_REF:-main}"

VARIANT="dracula"
TERMINAL="auto"
WITH_PAGER=0
DRY_RUN=0
FORCE=0
UNINSTALL=0
RESTORE_BACKUP=0

GROK_DIR="$HOME/.grok"
CONFIG="$GROK_DIR/config.toml"
PAGER="$GROK_DIR/pager.toml"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/grok-build-dracula"
STATE="$DATA_DIR/state"
FILES="$DATA_DIR/files"
CONF_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SRC=""
TMP_SRC=""

if [ -t 1 ]; then B=$(printf '\033[1m'); P=$(printf '\033[35m'); G=$(printf '\033[32m'); Y=$(printf '\033[33m'); R=$(printf '\033[31m'); N=$(printf '\033[0m'); else B=""; P=""; G=""; Y=""; R=""; N=""; fi
say()  { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s\n' "$P" "$N" "$*"; }
ok()   { printf '%s ok%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%swarn%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
dry()  { printf '%s[dry-run]%s would %s\n' "$Y" "$N" "$*"; }

usage() {
  cat <<'USAGE'
Usage: install.sh [options]
  --variant dracula|dracula-soft|alucard   palette to install (default: dracula)
  --terminal NAME|auto|all|none            iterm2, ghostty, wezterm, kitty, alacritty,
                                           windows-terminal (default: auto)
  --with-pager      also install extras/pager.toml as ~/.grok/pager.toml if none exists
  --dry-run         show what would happen, change nothing
  --force           replace scheme files that exist and differ (old copy is backed up)
  --uninstall       undo: restore the previous Grok theme, remove files this installer added
  --restore-backup  with --uninstall: put back the config.toml backup taken before first install
  -h, --help
USAGE
}

have() { command -v "$1" >/dev/null 2>&1; }

sha() {
  if have sha256sum; then sha256sum "$1" | cut -d' ' -f1
  elif have shasum; then shasum -a 256 "$1" | cut -d' ' -f1
  else cksum "$1" | cut -d' ' -f1-2 | tr ' ' '-'; fi
}

stamp() { date +%Y%m%d-%H%M%S; }

state_get() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | tail -n 1; }
state_set() {
  mkdir -p "$DATA_DIR"
  if [ -f "$STATE" ]; then grep -v "^$1=" "$STATE" > "$STATE.tmp" || true; mv "$STATE.tmp" "$STATE"; fi
  printf '%s=%s\n' "$1" "$2" >> "$STATE"
}
file_record() { # path sha
  mkdir -p "$DATA_DIR"
  if [ -f "$FILES" ]; then awk -F'\t' -v p="$1" '$1 != p' "$FILES" > "$FILES.tmp"; mv "$FILES.tmp" "$FILES"; fi
  printf '%s\t%s\n' "$1" "$2" >> "$FILES"
}
file_recorded_sha() { [ -f "$FILES" ] && awk -F'\t' -v p="$1" '$1 == p { s = $2 } END { if (s) print s }' "$FILES"; }
file_forget() { [ -f "$FILES" ] && { awk -F'\t' -v p="$1" '$1 != p' "$FILES" > "$FILES.tmp"; mv "$FILES.tmp" "$FILES"; }; return 0; }

cleanup() { [ -n "$TMP_SRC" ] && rm -rf "$TMP_SRC"; return 0; }

# ------------------------------------------------------------------ sources

find_sources() {
  d=""
  [ -f "$0" ] && d=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
  if [ -n "$d" ] && [ -f "$d/palettes/dracula.toml" ] && [ -d "$d/themes" ]; then SRC="$d"; return 0; fi
  if [ -n "${GROK_DRACULA_SRC:-}" ] && [ -d "$GROK_DRACULA_SRC/themes" ]; then SRC="$GROK_DRACULA_SRC"; return 0; fi
  # Running from a pipe (curl | sh): fetch the repo.
  if [ "$DRY_RUN" = 1 ]; then TMP_SRC=$(mktemp -d); dest="$TMP_SRC/src"; else dest="$DATA_DIR/src"; fi
  if [ -d "$dest/.git" ] && have git; then
    info "Updating $dest"
    git -C "$dest" fetch -q --depth 1 origin "$REPO_REF" </dev/null && git -C "$dest" checkout -q FETCH_HEAD </dev/null || warn "could not update $dest; using it as is"
    SRC="$dest"; return 0
  fi
  mkdir -p "$(dirname "$dest")"
  info "Fetching $REPO_SLUG ($REPO_REF)"
  if have git && GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 --branch "$REPO_REF" "$REPO_URL" "$dest" </dev/null 2>/dev/null; then SRC="$dest"; return 0; fi
  if have gh && gh repo clone "$REPO_SLUG" "$dest" -- -q --depth 1 --branch "$REPO_REF" </dev/null >/dev/null 2>&1; then SRC="$dest"; return 0; fi
  die "could not download $REPO_SLUG. The repo may be private: run 'gh auth login' first, or clone it and run ./install.sh from the checkout."
}

# ------------------------------------------------------------- terminals

detect_terminal() {
  case "${TERM_PROGRAM:-}" in
    iTerm.app) echo iterm2; return ;;
    ghostty) echo ghostty; return ;;
    WezTerm) echo wezterm; return ;;
  esac
  if [ -n "${GHOSTTY_RESOURCES_DIR:-}" ] || [ "${TERM:-}" = "xterm-ghostty" ]; then echo ghostty; return; fi
  if [ -n "${KITTY_WINDOW_ID:-}" ] || [ "${TERM:-}" = "xterm-kitty" ]; then echo kitty; return; fi
  if [ -n "${WEZTERM_PANE:-}" ] || [ -n "${WEZTERM_EXECUTABLE:-}" ]; then echo wezterm; return; fi
  if [ -n "${ALACRITTY_WINDOW_ID:-}" ] || [ -n "${ALACRITTY_SOCKET:-}" ] || [ "${TERM:-}" = "alacritty" ]; then echo alacritty; return; fi
  if [ -n "${ITERM_SESSION_ID:-}" ]; then echo iterm2; return; fi
  if [ -n "${WT_SESSION:-}" ]; then echo windows-terminal; return; fi
  echo unknown
}

scheme_name() {
  case "$VARIANT" in
    dracula) echo "Grok Dracula" ;;
    dracula-soft) echo "Grok Dracula Soft" ;;
    alucard) echo "Grok Alucard" ;;
  esac
}

# copy_file SRC DEST LABEL: never silently overwrite a file we don't own
copy_file() {
  src=$1; dst=$2
  new_sha=$(sha "$src")
  if [ -f "$dst" ]; then
    cur_sha=$(sha "$dst")
    if [ "$cur_sha" = "$new_sha" ]; then ok "$dst already up to date"; return 0; fi
    rec=$(file_recorded_sha "$dst")
    if [ "$rec" != "$cur_sha" ] && [ "$FORCE" != 1 ]; then
      warn "$dst exists and was not written by this installer (or was edited). Left untouched."
      warn "  re-run with --force to replace it (a backup is kept), or copy manually from: $src"
      return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then dry "update $dst"; return 0; fi
    if [ "$rec" != "$cur_sha" ]; then cp "$dst" "$dst.bak-grok-dracula-$(stamp)"; ok "backed up $dst"; fi
  elif [ "$DRY_RUN" = 1 ]; then dry "install $dst"; return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  file_record "$dst" "$new_sha"
  ok "installed $dst"
}

install_terminal() {
  t=$1; name=$(scheme_name); slug="grok-$VARIANT"
  case "$t" in
    ghostty)
      copy_file "$SRC/themes/ghostty/$slug" "$CONF_HOME/ghostty/themes/$slug"
      say ""
      say "${B}Activate in Ghostty${N}: add this line to your Ghostty config"
      say "  (~/.config/ghostty/config, or on macOS ~/Library/Application Support/com.mitchellh.ghostty/config):"
      say "    theme = $slug"
      say "  Light/dark pair:  theme = light:grok-alucard,dark:grok-dracula"
      say "  Then reload the config (macOS: Cmd+Shift+,  Linux: Ctrl+Shift+,) or open a new window."
      ;;
    kitty)
      copy_file "$SRC/themes/kitty/$slug.conf" "$CONF_HOME/kitty/themes/$slug.conf"
      say ""
      say "${B}Activate in kitty${N}, either:"
      say "    kitten themes --reload-in=all \"$name\""
      say "  or add to ~/.config/kitty/kitty.conf:"
      say "    include themes/$slug.conf"
      say "  and reload with Ctrl+Shift+F5 (macOS: Cmd+Ctrl+,)."
      ;;
    alacritty)
      copy_file "$SRC/themes/alacritty/$slug.toml" "$CONF_HOME/alacritty/themes/$slug.toml"
      say ""
      say "${B}Activate in Alacritty${N} (0.14+): add to ~/.config/alacritty/alacritty.toml:"
      say "    [general]"
      say "    import = [\"~/.config/alacritty/themes/$slug.toml\"]"
      say "  (Alacritty 0.13 and older: put the import line at the top level, without [general].)"
      say "  Alacritty reloads its config automatically."
      ;;
    wezterm)
      copy_file "$SRC/themes/wezterm/$slug.toml" "$CONF_HOME/wezterm/colors/$slug.toml"
      say ""
      say "${B}Activate in WezTerm${N}: in ~/.wezterm.lua (or ~/.config/wezterm/wezterm.lua) set:"
      say "    config.color_scheme = \"$name\""
      say "  WezTerm reloads its config automatically."
      ;;
    iterm2)
      f="$SRC/themes/iterm2/$slug.itermcolors"
      copy_file "$f" "$CONF_HOME/grok-build-dracula/iterm2/$slug.itermcolors"
      say ""
      say "${B}Activate in iTerm2${N}: iTerm2 imports presets through its UI:"
      say "    open \"$CONF_HOME/grok-build-dracula/iterm2/$slug.itermcolors\"    # imports the preset"
      say "  or Settings > Profiles > Colors > Color Presets... > Import..., pick that file,"
      say "  then choose \"$slug\" from Color Presets."
      ;;
    windows-terminal)
      say ""
      say "${B}Activate in Windows Terminal${N}: Settings > Open JSON file, add this object to the"
      say "\"schemes\" array, then set \"colorScheme\": \"$name\" in your profile (or profiles.defaults):"
      say ""
      cat "$SRC/themes/windows-terminal/$slug.json"
      ;;
    *) die "unknown terminal: $t" ;;
  esac
}

print_all_terminals() {
  say ""
  say "Could not detect your terminal. Scheme files for $(scheme_name) live in:"
  for d in iterm2 ghostty wezterm kitty alacritty windows-terminal; do say "    $SRC/themes/$d/"; done
  say "Re-run with --terminal iterm2|ghostty|wezterm|kitty|alacritty|windows-terminal to install one"
  say "and see its activation steps, or --terminal all."
}

# ----------------------------------------------------------------- config

manual_config_help() {
  say ""
  say "Edit $CONFIG by hand and make sure it contains (merge into existing tables, don't duplicate them):"
  say ""
  say "    [ui]"
  say "    theme = \"terminal\""
  say ""
  say "    [features]"
  say "    terminal_theme = true"
  say ""
  say "Or skip the config entirely and launch Grok with: GROK_THEME=terminal GROK_TERMINAL_THEME=1 grok"
}

py() { if have python3; then python3 "$@"; else return 127; fi; }

json_field() { # json key -> value or "null"
  printf '%s' "$1" | py -c 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print("null" if v is None else (str(v).lower() if isinstance(v,bool) else v))' "$2"
}

configure_grok() {
  info "Grok Build config: $CONFIG"
  if ! have python3; then warn "python3 not found, so the config was not edited."; manual_config_help; return 0; fi
  cur=$(py "$SRC/scripts/grok_config.py" get "$CONFIG") || { rc=$?; [ $rc = 4 ] && warn "python3 is older than 3.11 and has no tomli."; warn "could not read $CONFIG"; manual_config_help; return 0; }
  theme=$(json_field "$cur" theme); feat=$(json_field "$cur" terminal_theme); legacy=$(json_field "$cur" ui_theme_legacy)
  if [ ! -f "$STATE" ] || [ -z "$(state_get prev_theme)" ]; then
    if [ "$DRY_RUN" = 1 ]; then dry "record previous settings (theme=$theme, terminal_theme=$feat)"
    else state_set prev_theme "$theme"; state_set prev_feature "$feat"; fi
  fi
  [ "$legacy" != "null" ] && warn "$CONFIG also sets the legacy [ui] ui_theme = \"$legacy\"; remove it if Grok ignores the new theme."
  if [ "$theme" = "terminal" ] && [ "$feat" = "true" ]; then ok "theme = \"terminal\" and terminal_theme = true already set"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then
    res=$(py "$SRC/scripts/grok_config.py" set "$CONFIG" --theme terminal --feature true --dry-run) || { warn "automatic edit not possible"; manual_config_help; return 0; }
    dry "set [ui] theme = \"terminal\" and [features] terminal_theme = true ($res)"
    [ -f "$CONFIG" ] && dry "back up $CONFIG first"
    return 0
  fi
  if [ -f "$CONFIG" ]; then
    bak="$CONFIG.bak-grok-dracula-$(stamp)"
    cp -p "$CONFIG" "$bak" || die "could not back up $CONFIG"
    ok "backed up config to $bak"
    [ -z "$(state_get first_backup)" ] && state_set first_backup "$bak"
  else
    [ -z "$(state_get first_backup)" ] && state_set first_backup "none"
  fi
  if res=$(py "$SRC/scripts/grok_config.py" set "$CONFIG" --theme terminal --feature true); then
    ok "set [ui] theme = \"terminal\" and [features] terminal_theme = true ($res)"
  else
    warn "automatic edit not possible; $CONFIG was left unchanged."
    manual_config_help
  fi
}

install_pager() {
  if [ -f "$PAGER" ]; then
    if [ "$(sha "$PAGER")" = "$(sha "$SRC/extras/pager.toml")" ]; then ok "$PAGER already matches the snippet"; return 0; fi
    info "$PAGER already exists, so it was left alone. Optional snippet you can merge by hand:"
    say ""; cat "$SRC/extras/pager.toml"; say ""
    return 0
  fi
  if [ "$WITH_PAGER" = 1 ]; then
    copy_file "$SRC/extras/pager.toml" "$PAGER"
  else
    say ""
    say "Optional: layout tweaks for Grok live in $PAGER (none exists yet)."
    say "Re-run with --with-pager to install $SRC/extras/pager.toml there."
  fi
}

check_env_overrides() {
  if [ -n "${GROK_THEME:-}" ] && [ "${GROK_THEME:-}" != "terminal" ]; then
    warn "GROK_THEME=$GROK_THEME is set in your environment and overrides config.toml. Unset it or set GROK_THEME=terminal."
  fi
  if [ -n "${NO_COLOR:-}" ]; then warn "NO_COLOR is set, so Grok will render without color."; fi
}

# -------------------------------------------------------------- uninstall

do_uninstall() {
  info "Uninstalling grok-build-dracula"
  if [ "$RESTORE_BACKUP" = 1 ]; then
    first=$(state_get first_backup)
    case "$first" in
      ""|none) warn "no pre-install backup recorded; falling back to a normal uninstall" ;;
      *)
        if [ ! -f "$first" ]; then warn "recorded backup $first is missing; falling back to a normal uninstall"
        elif [ "$DRY_RUN" = 1 ]; then dry "copy $first back to $CONFIG (current file saved as $CONFIG.bak-grok-dracula-uninstall-*)"
        else
          [ -f "$CONFIG" ] && cp -p "$CONFIG" "$CONFIG.bak-grok-dracula-uninstall-$(stamp)"
          cp -p "$first" "$CONFIG"; ok "restored $CONFIG from $first"
          RESTORED=1
        fi ;;
    esac
  fi
  if [ "${RESTORED:-0}" != 1 ]; then
    if ! have python3; then
      warn "python3 not found. Set [ui] theme back (e.g. theme = \"groknight\") in $CONFIG by hand."
    elif [ -f "$CONFIG" ]; then
      if [ -f "$STATE" ]; then prev=$(state_get prev_theme); pfeat=$(state_get prev_feature)
      else
        # No record of an install: only act if the theme is still "terminal".
        cur=$(json_field "$(py "$SRC/scripts/grok_config.py" get "$CONFIG")" theme 2>/dev/null)
        if [ "$cur" = "terminal" ]; then prev="groknight"; pfeat="null"
        else ok "no install recorded and theme is not \"terminal\"; config left as is"; prev="skip"; pfeat="null"; fi
      fi
      [ -z "$prev" ] && prev="groknight"
      if [ "$prev" = "null" ]; then targs="--unset-theme"; tdesc="removed [ui] theme (Grok's default, groknight)"
      elif [ "$prev" = "terminal" ]; then targs=""; tdesc="kept theme = \"terminal\" (it was set before install)"
      else targs="--theme $prev"; tdesc="set [ui] theme = \"$prev\""; fi
      case "$pfeat" in true|false) fargs="--feature $pfeat" ;; *) fargs="--unset-feature" ;; esac
      if [ "$prev" != "skip" ]; then
        # shellcheck disable=SC2086
        if res=$(py "$SRC/scripts/grok_config.py" set "$CONFIG" $targs $fargs --dry-run); then
          if [ "$res" = "unchanged" ]; then ok "config already restored"
          elif [ "$DRY_RUN" = 1 ]; then dry "back up $CONFIG, then: $tdesc; restore terminal_theme"
          else
            cp -p "$CONFIG" "$CONFIG.bak-grok-dracula-uninstall-$(stamp)"
            # shellcheck disable=SC2086
            py "$SRC/scripts/grok_config.py" set "$CONFIG" $targs $fargs >/dev/null && ok "$tdesc; restored terminal_theme"
          fi
        else
          warn "could not edit $CONFIG automatically; set [ui] theme = \"groknight\" by hand."
        fi
      fi
    fi
  fi
  # remove files this installer added, only if unmodified
  if [ -f "$FILES" ]; then
    while IFS="$(printf '\t')" read -r path rec; do
      [ -n "$path" ] || continue
      if [ ! -f "$path" ]; then file_forget "$path"; continue; fi
      if [ "$(sha "$path")" != "$rec" ]; then warn "$path was modified after install; left in place"; continue; fi
      if [ "$DRY_RUN" = 1 ]; then dry "remove $path"; else rm -f "$path"; file_forget "$path"; ok "removed $path"; fi
    done < "$FILES"
  fi
  if [ "$DRY_RUN" != 1 ]; then
    rm -f "$STATE" "$FILES"
    rm -rf "$DATA_DIR/src"
    rmdir "$DATA_DIR" 2>/dev/null || true
  fi
  say ""
  say "Done. Backups of config.toml (config.toml.bak-grok-dracula-*) were kept in $GROK_DIR."
  say "Switch your terminal back to its previous color scheme in its own settings."
}

# ------------------------------------------------------------------- main

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --variant) [ $# -ge 2 ] || die "--variant needs a value"; VARIANT=$2; shift 2 ;;
      --variant=*) VARIANT=${1#*=}; shift ;;
      --terminal) [ $# -ge 2 ] || die "--terminal needs a value"; TERMINAL=$2; shift 2 ;;
      --terminal=*) TERMINAL=${1#*=}; shift ;;
      --with-pager) WITH_PAGER=1; shift ;;
      --dry-run|-n) DRY_RUN=1; shift ;;
      --force) FORCE=1; shift ;;
      --uninstall) UNINSTALL=1; shift ;;
      --restore-backup) RESTORE_BACKUP=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
  done
  case "$VARIANT" in dracula|dracula-soft|alucard) ;; *) die "--variant must be dracula, dracula-soft or alucard" ;; esac
  case "$TERMINAL" in auto|all|none|iterm2|ghostty|wezterm|kitty|alacritty|windows-terminal) ;;
    iterm|iTerm|iTerm2) TERMINAL=iterm2 ;; wt|windowsterminal) TERMINAL=windows-terminal ;;
    *) die "--terminal must be auto, all, none, iterm2, ghostty, wezterm, kitty, alacritty or windows-terminal" ;; esac
  [ "$RESTORE_BACKUP" = 1 ] && [ "$UNINSTALL" != 1 ] && die "--restore-backup only works with --uninstall"
  [ -n "${HOME:-}" ] || die "HOME is not set"
  trap cleanup EXIT INT TERM

  if [ "$UNINSTALL" = 1 ]; then
    find_sources
    do_uninstall
    return 0
  fi

  find_sources
  say "${B}grok-build-dracula${N}: installing ${P}$(scheme_name)${N}"
  [ "$DRY_RUN" = 1 ] && say "(dry run: nothing will be changed)"
  configure_grok
  [ "$DRY_RUN" = 1 ] || state_set variant "$VARIANT"
  check_env_overrides

  t=$TERMINAL
  [ "$t" = auto ] && t=$(detect_terminal) && info "Detected terminal: $t"
  case "$t" in
    none) ;;
    unknown) print_all_terminals ;;
    all) for x in ghostty kitty alacritty wezterm iterm2 windows-terminal; do install_terminal "$x"; done ;;
    *) install_terminal "$t" ;;
  esac
  install_pager
  say ""
  say "Restart Grok Build. It now uses its built-in Terminal theme, so colors follow your terminal's palette."
  say "(Without editing config: GROK_THEME=terminal GROK_TERMINAL_THEME=1 grok)"
  say "Undo any time: run the installer again with --uninstall"
}

main "$@"
