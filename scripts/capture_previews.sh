#!/bin/sh
# Capture the README previews: a real kitty window, using the generated kitty
# scheme, running Grok Build in its terminal theme. Needs X (DISPLAY), kitty,
# xdotool, Python 3 + Pillow, and a signed-in `grok`. Makes a real model call.
#
#   DISPLAY=:0 sh scripts/capture_previews.sh            # all three variants
#   VARIANTS=alucard sh scripts/capture_previews.sh
#
# Isolation: kitty reads a throwaway config dir, and the demo runs in a scratch
# directory. Grok itself uses your normal ~/.grok unless you set GROK_HOME_DIR
# to another HOME (the previews were made with a scratch HOME whose ~/.grok
# links to the real auth and has pager.toml `[scrollback.blocks.edit]
# expanded_by_default = true` so the diff is shown).
# Afterwards run: python3 scripts/frame_previews.py
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KITTY=${KITTY:-kitty}
GROK=${GROK:-grok}
WAIT=${WAIT:-75}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/demo" "$WORK/kitty/kitty/themes" "$ROOT/previews/raw"
cp "$ROOT"/themes/kitty/*.conf "$WORK/kitty/kitty/themes/"
PROMPT='Do these in order, briefly: 1) run python3 greet.py Grok 2) add a one-line docstring to greet() in greet.py 3) reply with one sentence plus the updated greet() in a python code block.'
for V in ${VARIANTS:-dracula dracula-soft alucard}; do
  cat > "$WORK/demo/greet.py" <<'PY'
import sys


def greet(name: str, excited: bool = False) -> str:
    message = f"Hello, {name}"
    return message + ("!" if excited else ".")


if __name__ == "__main__":
    who = sys.argv[1] if len(sys.argv) > 1 else "Dracula"
    print(greet(who, excited=True))
PY
  printf 'include themes/grok-%s.conf\nfont_size 14\nremember_window_size no\ninitial_window_width 104c\ninitial_window_height 44c\nwindow_padding_width 10\nconfirm_os_window_close 0\ncursor_blink_interval 0\n' "$V" > "$WORK/kitty/kitty/kitty.conf"
  env -u NO_COLOR -u FORCE_COLOR -u TERM XDG_CONFIG_HOME="$WORK/kitty" \
    "$KITTY" --class "grokprev-$V" sh -c "cd '$WORK/demo' && exec env HOME='${GROK_HOME_DIR:-$HOME}' GROK_THEME=terminal GROK_TERMINAL_THEME=1 '$GROK' --always-approve \"$PROMPT\"" >/dev/null 2>&1 &
  sleep "$WAIT"
  W=$(xdotool search --class "grokprev-$V" | head -n 1)
  eval "$(xdotool getwindowgeometry --shell "$W")"
  python3 -c "from PIL import ImageGrab; ImageGrab.grab(xdisplay='$DISPLAY', bbox=($X,$Y,$X+$WIDTH,$Y+$HEIGHT)).save('$ROOT/previews/raw/kitty-$V.png')"
  pkill -f "class grokprev-$V" || true
  sleep 2
  echo "captured previews/raw/kitty-$V.png"
done
