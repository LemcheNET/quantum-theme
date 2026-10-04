#!/usr/bin/env bash
# Titlebar button size, across every variant.
#
# BOTH variants by default. Aurorae keys button size per theme - ~/.config/auroraerc has
# a group per theme name - and --base edits a per-variant rc file. Treating either as
# "the" setting makes the variants silently diverge, so this script writes all of them
# unless you say otherwise.
#
# The mechanism is Aurorae's own, not something this theme added. From
# aurorae/v2/decoration.cpp:
#
#     const KConfigGroup group(m_auroraerc, m_themeName);
#     const int buttonSize = group.readEntry("ButtonSize", 1);
#     setButtonSizeFactor(1.0 + (buttonSize - 1) * 0.2);
#
# and the titlebar follows on its own, from v2/decorationtheme.cpp:159:
#
#     titleHeight = max(TitleHeight, ButtonHeight * factor + ButtonMarginTop)
#
# Usage:  buttons.sh                        show every variant and the pixels it works out to
#         buttons.sh large                  one of the seven named steps, applied to all
#         buttons.sh 3                      the same, by index
#         buttons.sh --base 16              set ButtonWidth/ButtonHeight on all
#         buttons.sh --variant light --sync copy light's base onto the others
#         ... --only dark                   restrict any of the above to one variant
# UNTESTED.
set -euo pipefail
# shellcheck disable=SC2034  # read by quantum_init in lib/common.sh, sourced next
QUANTUM_VARIANT_OPTIONAL=1
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

AURORAERC="$CONF/auroraerc"
NAMES=(tiny normal large very-large huge very-huge oversized)
mapfile -t ALL < <(quantum_variants)

vid()     { quantum_variant_get "$1" ID; }
src_rc()  { local i; i="$(vid "$1")"; printf '%s\n' "$QUANTUM_ROOT/variants/$1/aurorae/$i/${i}rc"; }
live_rc() { local i; i="$(vid "$1")"; printf '%s\n' "$DATA/aurorae/themes/$i/${i}rc"; }
# `|| true`: awk exits 2 when the file is absent (an uninstalled variant), and under
# `set -e` that killed the script right after the report table.
rcval()   { [[ -f "$1" ]] || return 0; awk -F= -v k="$2" '$1==k{gsub(/ /,"",$2); print $2; exit}' "$1" 2>/dev/null || true; }
cur_size() {
  local n
  n=$(awk -v g="[$(vid "$1")]" '$0==g{f=1;next} /^\[/{f=0} f&&/^ButtonSize=/{sub(/^ButtonSize=/,"");print;exit}' "$AURORAERC" 2>/dev/null || true)
  echo "${n:-1}"
}

dpi=$(xdpyinfo 2>/dev/null | awk '/resolution/{split($2,a,"x"); print a[1]; exit}' || true)
[[ -n "${dpi:-}" ]] || dpi=96

report() {
  printf '    %-13s %-7s %-9s %-18s %-9s %-10s %s\n' variant source installed ButtonSize factor button titlebar
  local v rc lrc bw bh bm th te tb idx lbw
  for v in "${ALL[@]}"; do
    rc="$(src_rc "$v")"; lrc="$(live_rc "$v")"
    [[ -f "$rc" ]] || { printf '    %-13s %s\n' "$(vid "$v")" "(no rc found at $rc)"; continue; }
    if [[ -f "$lrc" ]]; then lbw=$(rcval "$lrc" ButtonWidth); else lbw="-"; fi
    bw=$(rcval "$rc" ButtonWidth); bh=$(rcval "$rc" ButtonHeight); bm=$(rcval "$rc" ButtonMarginTop)
    th=$(rcval "$rc" TitleHeight); te=$(rcval "$rc" TitleEdgeTop); tb=$(rcval "$rc" TitleEdgeBottom)
    idx=$(cur_size "$v")
    python3 - "$(vid "$v")" "$bw" "$bh" "$bm" "$th" "$te" "$tb" "$dpi" "$idx" "${NAMES[$idx]}" "${lbw:--}" <<'PY'
import sys
v,bw,bh,bm,th,te,tb,dpi,idx,name,lbw = sys.argv[1:12]
idx=int(idx); bw,bh,bm,th,te,tb=map(float,(bw,bh,bm,th,te,tb)); dpi=float(dpi)
s=dpi/96.0                       # themeconfig.cpp:118
factor=1.0+(idx-1)*0.2           # decoration.cpp
bwS,bhS,bmS,thS,teS,tbS=(round(x*s) for x in (bw,bh,bm,th,te,tb))
btn=bhS*factor
title=max(thS, btn+bmS)+teS+tbS
label = f"{idx} ({name})"
# the INSTALLED rc is what KWin reads; the source is only what the next install will copy
flag = "" if (lbw == "-" or float(lbw) == bw) else "  <- differs from source!"
print(f"    {v:<13} {bw:<7.0f} {lbw:<9} {label:<18} {factor:<9.1f} {btn:<10.0f} {title:.0f}px{flag}")
PY
  done

  # cross-variant drift, which is the whole reason this script writes all of them
  local v a b la lb ref="${ALL[0]}"
  a=$(rcval "$(src_rc "$ref")" ButtonWidth); la=$(rcval "$(live_rc "$ref")" ButtonWidth)
  for v in "${ALL[@]:1}"; do
    b=$(rcval "$(src_rc "$v")" ButtonWidth); lb=$(rcval "$(live_rc "$v")" ButtonWidth)
    if [[ -n "$la" && -n "$lb" && "$la" != "$lb" ]]; then
      warn "the INSTALLED bases differ ($(vid "$ref")=$la, $(vid "$v")=$lb) - that is what KWin reads"
    fi
    if [[ -n "$a" && -n "$b" && "$a" != "$b" ]]; then
      warn "different base sizes in source ($(vid "$ref")=$a, $(vid "$v")=$b)"
      warn "run: buttons.sh --variant $ref --sync   (or --base N to set every variant)"
    fi
    [[ "$(cur_size "$ref")" != "$(cur_size "$v")" ]] &&
      warn "ButtonSize differs ($(vid "$ref")=$(cur_size "$ref"), $(vid "$v")=$(cur_size "$v"))" || true
  done
}

set_base() {  # slug, pixels
  local v="$1" n="$2" f
  for f in "$(src_rc "$v")" "$(live_rc "$v")"; do
    [[ -f "$f" ]] || continue
    sed -i "s/^ButtonWidth=.*/ButtonWidth=$n/; s/^ButtonHeight=.*/ButtonHeight=$n/" "$f"
    echo "      $f"
  done
}

set_size() {  # slug, index
  local i; i="$(vid "$1")"
  kwriteconfig6 --file auroraerc --group "$i" --key ButtonSize "$2"
  echo "      auroraerc [$i] ButtonSize=$2"
}

# qdbus reconfigure is enough for auroraerc (ButtonSize) but NOT for the theme's own rc.
# aurorae/v2/decorationtheme.cpp:57 reads <Theme>rc in the DecorationTheme constructor,
# and DecorationTheme::open() returns a cached instance for a theme name it has already
# seen. onDecorationSettingsChanged() reparses only auroraerc. So ButtonWidth/ButtonHeight
# are read ONCE per theme per KWin process: changing them needs a KWin restart.
restart_notice() {
  cat <<'MSG'

!!  ButtonWidth/ButtonHeight are read once per theme per KWin process.
!!  qdbus reconfigure does NOT re-read them - aurorae/v2/decorationtheme.cpp:57 reads
!!  the rc in the DecorationTheme constructor, and DecorationTheme::open() hands back a
!!  cached instance for a theme it has already loaded.
!!
!!  Until KWin restarts you will keep seeing the base that was on disk when each theme
!!  was FIRST used this session - which is how two themes with identical rc files end up
!!  drawing different button sizes.
!!
!!      X11      kwin_x11 --replace &
!!      Wayland  log out and back in
!!
!!  ButtonSize (buttons.sh large) is live and needs none of this.
MSG
}

reconfigure() {
  say "reconfiguring kwin"
  if command -v qdbus6 >/dev/null; then qdbus6 org.kde.KWin /KWin reconfigure
  elif command -v qdbus >/dev/null; then qdbus org.kde.KWin /KWin reconfigure
  else warn "qdbus not found - log out and back in"; fi
}

# ---- argument parsing --------------------------------------------------------
TARGETS=("${ALL[@]}")
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      only="${2:?--only needs a variant: ${ALL[*]}}"
      # accept either the slug or the package id
      if quantum_is_variant "$only"; then TARGETS=("$only")
      else
        TARGETS=()
        for v in "${ALL[@]}"; do [[ "$(vid "$v")" == "$only" ]] && TARGETS=("$v"); done
        [[ ${#TARGETS[@]} -gt 0 ]] || die "no such variant '$only'. One of: ${ALL[*]}"
      fi
      shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

if [[ -z "${1:-}" ]]; then
  say "current"
  report
  echo
  echo "    steps: ${NAMES[*]}   (0-6)"
  echo "    GUI:   System Settings -> Colors & Themes -> Window Decorations"
  echo "           -> configure (gear) on the theme -> Button size"
  echo "           That control is per-theme, so it sets one variant only."
  exit 0
fi

case "$1" in
  --sync)
    [[ -n "${SLUG:-}" ]] || die "--sync needs a source: buttons.sh --variant <slug> --sync"
    N=$(rcval "$(src_rc "$SLUG")" ButtonWidth)
    [[ -n "$N" ]] || die "could not read ButtonWidth from $(src_rc "$SLUG")"
    IDX=$(cur_size "$SLUG")
    for v in "${ALL[@]}"; do
      [[ "$v" == "$SLUG" ]] && continue
      say "copying $(vid "$SLUG")'s base ($N) onto $(vid "$v")"
      set_base "$v" "$N"
      command -v kwriteconfig6 >/dev/null && set_size "$v" "$IDX" || true
    done
    report; reconfigure; restart_notice ;;
  --base)
    N="${2:?--base needs a pixel size}"
    [[ "$N" =~ ^[0-9]+$ ]] && (( N >= 4 && N <= 64 )) || die "--base wants 4-64"
    say "setting ButtonWidth/ButtonHeight=$N on: ${TARGETS[*]}"
    for v in "${TARGETS[@]}"; do set_base "$v" "$N"; done
    warn "Moe's button SVGs are 21x21 natural - much past that and they soften"
    report; reconfigure; restart_notice ;;
  *)
    SEL="$1"; IDX=""
    if [[ "$SEL" =~ ^[0-6]$ ]]; then IDX="$SEL"
    else for i in "${!NAMES[@]}"; do [[ "${NAMES[$i]}" == "$SEL" ]] && IDX="$i"; done; fi
    [[ -n "$IDX" ]] || die "unknown size '$SEL'. One of: ${NAMES[*]} (or 0-6)"
    command -v kwriteconfig6 >/dev/null || die "kwriteconfig6 not found"
    say "setting ButtonSize=$IDX (${NAMES[$IDX]}) on: ${TARGETS[*]}"
    for v in "${TARGETS[@]}"; do set_size "$v" "$IDX"; done
    report; reconfigure ;;
esac
