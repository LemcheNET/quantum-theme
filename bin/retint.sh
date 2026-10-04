#!/usr/bin/env bash
# Retint the window decoration frame to match a colour scheme's window background.
#
# The Moe frame is a single flat colour across every slice, active and inactive, so
# matching it to the application style is one substitution. Upstream Moe ships #f7f9f9;
# the gap between that and the variant's [Colors:Window] BackgroundNormal is the seam
# you see between titlebar and toolbar.
#
# Usage:  retint.sh --variant light            # match the installed base scheme
#         retint.sh --variant dark '#31363b'   # match something else
#         retint.sh --variant dark --from /path/to/some.colors
#
# Edits the SOURCE tree. Run install.sh afterwards to push it to the live copy.
# Idempotent: re-running with the same target is a no-op. UNTESTED.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

DECO="$AURORAE_SRC/decoration.svg"
SCHEME="$BASE_SCHEME_FILE"
TARGET=""

case "${1:-}" in
  --from) SCHEME="${2:?--from needs a .colors path}" ;;
  "")     ;;
  *)      TARGET="$1" ;;
esac

[[ -f "$DECO" ]] || die "no decoration.svg at $DECO"

if [[ -z "$TARGET" ]]; then
  [[ -f "$SCHEME" ]] || die "no $SCHEME; pass a hex colour instead"
  # [Colors:Window] BackgroundNormal=R,G,B  -> #rrggbb
  rgb=$(awk '/^\[Colors:Window\]/{f=1;next} /^\[/{f=0} f&&/^BackgroundNormal=/{sub(/^BackgroundNormal=/,"");print;exit}' "$SCHEME")
  [[ -n "$rgb" ]] || die "could not read [Colors:Window] BackgroundNormal from $SCHEME"
  TARGET=$(printf '#%02x%02x%02x' ${rgb//,/ })
  echo "target from $SCHEME: $rgb -> $TARGET"
fi

[[ "$TARGET" =~ ^#[0-9a-fA-F]{6}$ ]] || die "not a hex colour: $TARGET"

# Every colour that currently paints a visible part of the frame. Verified by rendering
# each slice and taking a histogram: the frame is 100% one colour. Shadows are black
# with alpha and are deliberately not in this list.
FRAME_COLOURS=(f7f9f9 eff0f1 31363b 2a2e32 202326)

before=$(md5sum "$DECO" | cut -d' ' -f1)
for c in "${FRAME_COLOURS[@]}"; do
  [[ "#$c" == "${TARGET,,}" ]] && continue
  sed -i "s/#$c/${TARGET,,}/g; s/#${c^^}/${TARGET,,}/g" "$DECO"
done
after=$(md5sum "$DECO" | cut -d' ' -f1)

n=$(grep -o "${TARGET,,}" "$DECO" | wc -l)
if [[ "$before" == "$after" ]]; then
  echo "no change - $ID frame already ${TARGET,,} ($n occurrences)"
else
  echo "retinted $ID frame to ${TARGET,,} ($n occurrences)"
  echo "reinstall and reload:  bin/install.sh --variant $SLUG && qdbus6 org.kde.KWin /KWin reconfigure"
fi
