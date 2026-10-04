#!/usr/bin/env bash
# Is the Plasma style being used AT ALL, and if so which files?
#
# Paints every surface this theme ships a different flat colour, then reloads. Whatever
# stays unchanged is not coming from this theme.
#
#   panel            MAGENTA  widgets/panel-background.svg
#                    ORANGE   translucent/widgets/panel-background.svg
#   popups/launcher  RED      dialogs/background.svg
#                    GREEN    translucent/dialogs/background.svg
#                    BLUE     solid/dialogs/background.svg
#   tooltips         CYAN     widgets/tooltip.svg
#
# Usage:  whichbg.sh --variant light
#         whichbg.sh --variant light --restore
# UNTESTED. Diagnostic only - your desktop looks like a test card for a minute.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

DEST="$STYLE_DEST"
SRC="$STYLE_SRC"

reload() {
  rm -rf "$CACHE"/plasma_theme_*.kcache "$CACHE"/plasma-svgelements* 2>/dev/null || true
  if command -v kquitapp6 >/dev/null; then
    kquitapp6 plasmashell 2>/dev/null || true; sleep "${QUANTUM_RESTART_DELAY:-2}"; (setsid plasmashell >/dev/null 2>&1 &)
  fi
}

if [[ "${1:-}" == "--restore" ]]; then
  say "restoring the real $NAME style"
  rm -rf "$DEST"; cp -a "$SRC" "$DEST"; reload
  say "done - real theme back in place"; exit 0
fi

paint() {
  local dest="$1" hex="$2" label="$3"
  mkdir -p "$(dirname "$dest")"
  python3 - "$dest" "$hex" <<'PY'
import sys
dest, hex_ = sys.argv[1], sys.argv[2]
c, e, m = 10, 8, 4
w = h = 2*c + e
def corner(ox, oy, which):
    return {"tl": f"M {ox},{oy+c} A {c},{c} 0 0 1 {ox+c},{oy} L {ox+c},{oy+c} Z",
            "tr": f"M {ox},{oy} A {c},{c} 0 0 1 {ox+c},{oy+c} L {ox},{oy+c} Z",
            "bl": f"M {ox+c},{oy+c} A {c},{c} 0 0 1 {ox},{oy} L {ox+c},{oy} Z",
            "br": f"M {ox+c},{oy} A {c},{c} 0 0 1 {ox},{oy+c} L {ox},{oy} Z"}[which]
f = f'style="fill:{hex_};fill-opacity:1;stroke:none" opacity="0.95"'
p = [f'<path {f} id="topleft"     d="{corner(0,0,"tl")}" />',
     f'<rect {f} id="top"         x="{c}" y="0" width="{e}" height="{c}" />',
     f'<path {f} id="topright"    d="{corner(c+e,0,"tr")}" />',
     f'<rect {f} id="left"        x="0" y="{c}" width="{c}" height="{e}" />',
     f'<rect {f} id="center"      x="{c}" y="{c}" width="{e}" height="{e}" />',
     f'<rect {f} id="right"       x="{c+e}" y="{c}" width="{c}" height="{e}" />',
     f'<path {f} id="bottomleft"  d="{corner(0,c+e,"bl")}" />',
     f'<rect {f} id="bottom"      x="{c}" y="{c+e}" width="{e}" height="{c}" />',
     f'<path {f} id="bottomright" d="{corner(c+e,c+e,"br")}" />',
     f'<rect id="hint-top-margin"    x="{c}" y="0" width="{e}" height="{m}" opacity="0" />',
     f'<rect id="hint-bottom-margin" x="{c}" y="{h-m}" width="{e}" height="{m}" opacity="0" />',
     f'<rect id="hint-left-margin"   x="0" y="{c}" width="{m}" height="{e}" opacity="0" />',
     f'<rect id="hint-right-margin"  x="{w-m}" y="{c}" width="{m}" height="{e}" opacity="0" />',
     f'<rect id="hint-stretch-borders" x="0" y="0" width="1" height="1" opacity="0" />']
open(dest,"w").write('<?xml version="1.0" encoding="UTF-8"?>\n'
  f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
  + "\n".join("  "+x for x in p) + "\n</svg>\n")
PY
  printf '    %-9s %-8s %s\n' "$hex" "$label" "${dest#"$DEST"/}"
}

say "reinstalling $NAME, then painting every surface"
rm -rf "$DEST"; cp -a "$SRC" "$DEST"
paint "$DEST/widgets/panel-background.svg"             "#ff00ff" MAGENTA
paint "$DEST/translucent/widgets/panel-background.svg" "#ff8800" ORANGE
paint "$DEST/dialogs/background.svg"                   "#ff0000" RED
paint "$DEST/translucent/dialogs/background.svg"       "#00cc00" GREEN
paint "$DEST/solid/dialogs/background.svg"             "#0000ff" BLUE
paint "$DEST/widgets/tooltip.svg"                      "#00cccc" CYAN
# Breadcrumb: verify.sh fails loudly while this exists, because a forgotten test card
# is indistinguishable from a theme bug. It cost an evening once.
date -u +"painted %Y-%m-%dT%H:%M:%SZ by whichbg.sh - run whichbg.sh --variant $SLUG --restore" > "$DEST/.whichbg-active"
reload
cat <<'MSG'

!!  THIS IS A TEST CARD, NOT THE THEME. Restore it when done.
!!  Until you do, every Plasma surface is a debug colour - including notifications,
!!  which read translucent/dialogs/background.svg and will be bright green.

==> Look at three things and report each:

    1. THE PANEL itself          magenta or orange -> the style IS live
                                 unchanged         -> the style is NOT being used at all
    2. THE APPLICATION LAUNCHER  red / green / blue / unchanged
    3. A TOOLTIP                 hover a taskbar entry. cyan -> live
MSG
echo "    Then:  bin/whichbg.sh --variant $SLUG --restore"
