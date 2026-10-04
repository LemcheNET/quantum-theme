#!/usr/bin/env bash
# Retune how translucent the Plasma style is, without hand-editing five SVGs.
#
# Usage:  opacity.sh --variant light              # show the current values
#         opacity.sh --variant light 65 75        # panel 65%, popups/plasmoids/tooltips 75%
#         opacity.sh --variant light 65 75 3      # ...and the Kickoff header/footer tint at 3%
#
# The heading tint is NOT a third surface at the popup value: plasmoidheading is painted
# on top of dialogs/background, so the two compound. This script prints the stacked
# result so you can see what Kickoff will actually be.
#
# After changing: bin/install.sh --variant <slug> && rm -rf ~/.cache/plasma_theme_*.kcache
# UNTESTED.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"
T="$STYLE_SRC"

cur() { grep -o 'opacity="[0-9.]*"' "$1" | grep -v 'opacity="0"' | head -1 | cut -d'"' -f2; }

if [[ $# -eq 0 ]]; then
  say "$NAME ($T)"
  printf '%-34s %s\n' "widgets/panel-background.svg"  "$(cur "$T/widgets/panel-background.svg")"
  printf '%-34s %s\n' "dialogs/background.svg"        "$(cur "$T/dialogs/background.svg")"
  printf '%-34s %s\n' "widgets/background.svg"        "$(cur "$T/widgets/background.svg")"
  printf '%-34s %s\n' "widgets/tooltip.svg"           "$(cur "$T/widgets/tooltip.svg")"
  printf '%-34s %s\n' "widgets/plasmoidheading.svg"   "$(cur "$T/widgets/plasmoidheading.svg")"
  echo
  echo "translucent/ (what Plasma actually uses while blur is on):"
  for f in widgets/panel-background.svg dialogs/background.svg widgets/background.svg widgets/tooltip.svg; do
    printf '%-34s %s\n' "  $f" "$(cur "$T/translucent/$f")"
  done
  echo
  echo "usage: opacity.sh --variant $SLUG <panel%> <popup%> [heading%]"
  exit 0
fi

PANEL="${1:?panel percent}"; POPUP="${2:?popup percent}"; HEAD="${3:-3}"
for v in "$PANEL" "$POPUP" "$HEAD"; do
  [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 0 && v <= 100 )) || die "not a percent: $v"
done
(( PANEL < 40 || POPUP < 40 )) && warn "below ~40% text legibility suffers even with the contrast effect" || true

set_op() {  # file, percent  - rewrites only the painting slices, never the zero-opacity hints
  local f="$1" pct="$2"
  local val; val=$(awk -v p="$pct" 'BEGIN{printf "%.2f", p/100}')
  sed -i -E "s/opacity=\"0\.[0-9]+\"/opacity=\"$val\"/g; s/opacity=\"1(\.0+)?\"/opacity=\"$val\"/g" "$f"
}
# Each of these four exists twice: top-level, and under translucent/ where Plasma
# looks first while KWin's blur effect is active. Retune both or they drift.
for base in "$T" "$T/translucent"; do
  set_op "$base/widgets/panel-background.svg" "$PANEL"
  for f in dialogs/background.svg widgets/background.svg widgets/tooltip.svg; do
    set_op "$base/$f" "$POPUP"
  done
done
set_op "$T/widgets/plasmoidheading.svg" "$HEAD"   # not selector-resolved; top-level only

stacked=$(awk -v p="$POPUP" -v h="$HEAD" 'BEGIN{printf "%.1f", 100*(1-(1-p/100)*(1-h/100))}')
echo "$NAME"
echo "panel            ${PANEL}%"
echo "popups/plasmoids ${POPUP}%"
echo "Kickoff heading  ${HEAD}% tint  ->  ${stacked}% where it sits over the popup"
(( $(awk -v s="$stacked" -v p="$POPUP" 'BEGIN{print (s-p > 8) ? 1 : 0}') )) \
  && warn "the heading is adding ${HEAD}% on top - lower it or Kickoff gets banded" || true
