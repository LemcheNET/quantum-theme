#!/usr/bin/env bash
# Read-only verification. Changes nothing.
#
# Usage:  verify.sh --variant light
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

say "$NAME $QUANTUM_VERSION - verification (read-only)"

if [[ -f "$STYLE_DEST/.whichbg-active" ]]; then
  printf '\033[1;31m'
  echo "=============================================================================="
  echo " THE whichbg.sh TEST CARD IS INSTALLED - every surface is a debug colour."
  echo " $(cat "$STYLE_DEST/.whichbg-active")"
  echo " Notifications will be bright green; the panel and popups are not the theme."
  echo " Fix:  bin/whichbg.sh --variant $SLUG --restore"
  echo "=============================================================================="
  printf '\033[0m'
fi

echo "installed files"
[[ -f "$AURORAE_DEST/metadata.json" ]] && ok "aurorae/themes/$ID" || bad "aurorae/themes/$ID missing"
[[ -f "$AURORAE_DEST/${ID}rc"       ]] && ok "${ID}rc present (name must match dir)" || bad "${ID}rc missing"
[[ -f "$STYLE_DEST/plasmarc"        ]] && ok "plasma/desktoptheme/$ID" || bad "Plasma style missing"
[[ -f "$LNF_DEST/contents/defaults" ]] && ok "look-and-feel/$ID" || bad "look-and-feel missing"
[[ -d "$LNF_DEST/contents/layouts"  ]] && bad "a layouts/ dir exists - applying will reset panels" || ok "no layouts/ - panels are safe"

# The source tree is one repo now, so a stale install is visible rather than inferred.
for p in "$AURORAE_SRC:$AURORAE_DEST" "$STYLE_SRC:$STYLE_DEST" "$LNF_SRC:$LNF_DEST"; do
  s="${p%%:*}"; d="${p##*:}"
  [[ -d "$s" && -d "$d" ]] || continue
  diff -rq "$s" "$d" >/dev/null 2>&1 \
    && ok "$(basename "$(dirname "$s")")/$(basename "$s") matches the repo" \
    || note "$(basename "$(dirname "$s")")/$(basename "$s") differs from the repo - re-run install.sh"
done

echo "does Plasma see the style"
if command -v plasma-apply-desktoptheme >/dev/null; then
  plasma-apply-desktoptheme --list-themes 2>/dev/null | grep -qi "$ID" \
    && ok "listed by plasma-apply-desktoptheme" \
    || bad "NOT listed - metadata.json is wrong, or the cache is stale (rm ~/.cache/plasma_theme_*.kcache)"
else
  note "plasma-apply-desktoptheme not found"
fi

# Which variant is live decides how to read everything below: the colour cross-check
# examines the ACTIVE scheme, so when a sibling variant is applied its verdict is
# evidence about that sibling, not about this variant.
live_lnf="$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage 2>/dev/null)"
if [[ "$live_lnf" == "$ID" ]]; then
  ok "$ID is the active global theme"
else
  sibling=""
  while read -r s; do
    [[ "$s" == "$SLUG" ]] && continue
    [[ "$(quantum_variant_get "$s" ID)" == "$live_lnf" ]] && sibling="$s"
  done < <(quantum_variants)
  if [[ -n "$sibling" ]]; then
    note "$live_lnf is active, not $ID - the figures below are this variant's on disk,"
    note "not what is live. Run: bin/install.sh --variant $SLUG --apply"
  elif [[ -z "$live_lnf" ]]; then
    note "no global theme recorded"
  else
    note "a different global theme is active: $live_lnf"
  fi
fi

echo "one colour across decoration, colours and application style"
want=""           # consumed again by the GTK section below; must survive set -u
if [[ -f "$BASE_SCHEME_FILE" ]]; then
  rgb=$(awk '/^\[Colors:Window\]/{f=1;next} /^\[/{f=0} f&&/^BackgroundNormal=/{sub(/^BackgroundNormal=/,"");print;exit}' "$BASE_SCHEME_FILE")
  want=$(printf '#%02x%02x%02x' ${rgb//,/ })
  printf '  %-30s %s (%s)\n' "this variant targets" "$want" "$rgb"
  deco="$AURORAE_DEST/decoration.svg"
  if [[ -f "$deco" ]]; then
    n=$(grep -o "$want" "$deco" | wc -l)
    if [[ "$n" -gt 0 ]]; then
      ok "decoration frame painted $want ($n occurrences) - titlebar matches window body"
    else
      bad "decoration frame is NOT $want - run bin/retint.sh --variant $SLUG, then install.sh"
      grep -oE '#[0-9a-f]{6}' "$deco" | sort | uniq -c | sort -rn | head -4 | sed 's/^/        /'
    fi
  fi
  # the scheme that is actually in use, which should be the derived one
  live_scheme="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null)"
  active=""
  for c in "$DATA/color-schemes/$live_scheme.colors" "/usr/share/color-schemes/$live_scheme.colors"; do
    [[ -f "$c" ]] && { active="$c"; break; }
  done
  if [[ -n "$active" ]]; then
    hdr=$(awk '/^\[Colors:Header\]/{f=1;next} /^\[/{f=0} f&&/^BackgroundNormal=/{sub(/^BackgroundNormal=/,"");print;exit}' "$active")
    awin=$(awk '/^\[Colors:Window\]/{f=1;next} /^\[/{f=0} f&&/^BackgroundNormal=/{sub(/^BackgroundNormal=/,"");print;exit}' "$active")
    wm=$(awk '/^\[WM\]/{f=1;next} /^\[/{f=0} f&&/^activeBackground=/{sub(/^activeBackground=/,"");print;exit}' "$active")
    printf '  %-30s %s\n' "active scheme (live)" "$live_scheme"
    if [[ "$live_lnf" == "$ID" ]]; then
      [[ "$hdr" == "$awin" ]] && ok "[Colors:Header] == [Colors:Window] ($hdr) - app toolbars match the titlebar" \
                              || bad "[Colors:Header]=$hdr != [Colors:Window]=$awin - run bin/colorscheme.sh, then re-apply"
      [[ "$wm" == "$awin" ]]  && ok "[WM] activeBackground == [Colors:Window]" \
                              || note "[WM] activeBackground=$wm != $awin"
    else
      # Checking $live_scheme would report a verdict on whichever variant IS applied,
      # which reads as validating this one. Say whose scheme it is instead.
      note "the live scheme is $live_scheme, not $ID - skipping the Header check, it would"
      note "be a verdict on that variant rather than this one"
      [[ "$hdr" == "$awin" ]] && note "  (for the record, $live_scheme does have Header == Window)" \
                              || note "  (for the record, $live_scheme has Header=$hdr != Window=$awin)"
    fi
  fi
else
  note "$BASE_SCHEME_FILE not found - cannot cross-check the colour"
fi

echo "live settings"
printf '  %-22s %s\n' "global theme"   "$live_lnf"
printf '  %-22s %s\n' "colour scheme"  "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)"
live_style="$(kreadconfig6 --file kdeglobals --group KDE --key widgetStyle)"
printf '  %-22s %s\n' "widget style"   "${live_style:-<unset>}"
# contents/defaults sets widgetStyle, so a different live value means either
# plasma-apply-lookandfeel did not write it or it was changed afterwards. The colour
# scheme still reaches a non-Breeze Qt style through the platform theme, so this is
# not necessarily a returning colour seam - what changes is how widgets are DRAWN
# (frames, buttons, scrollbars, toolbar shape), which is not what this theme was
# designed or previewed against. Worth knowing, so it is a check rather than a line
# of output; look at a toolbar before deciding whether you mind.
case "$live_style" in
  "$WIDGET_STYLE") ok "widget style is $WIDGET_STYLE, as the look-and-feel declares" ;;
  "")   note "widgetStyle unset - Qt falls back to the platform default" ;;
  *)    bad "widget style is '$live_style' but this theme declares $WIDGET_STYLE, so the"
        bad "  look-and-feel is not getting the application style it was built against."
        bad "  Either plasma-apply-lookandfeel did not write it or it changed since. Fix:"
        bad "  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle $WIDGET_STYLE" ;;
esac
printf '  %-22s %s\n' "icons"          "$(kreadconfig6 --file kdeglobals --group Icons   --key Theme)"
printf '  %-22s %s\n' "plasma style"   "$(kreadconfig6 --file plasmarc   --group Theme   --key name)"
dlib="$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key library)"
printf '  %-22s %s\n' "deco library"   "$dlib"
case "$dlib" in
  *aurorae*)
    avail=$(find /usr/lib*/*/qt6/plugins/org.kde.kdecoration* /usr/lib/qt6/plugins/org.kde.kdecoration* \
                 -iname "*aurorae*.so" 2>/dev/null | sed 's|.*/||; s|\.so$||' | grep -v '^kcm' | sort -u)
    if [[ -n "$avail" ]]; then
      echo "$avail" | grep -qx "$dlib" \
        && ok "$dlib is present on this host" \
        || bad "$dlib is NOT among the installed plugins: $(echo "$avail" | tr '\n' ' ')"
      printf '        available: %s\n' "$(echo "$avail" | tr '\n' ' ')"
    fi ;;
  "")        ;;
  *)         note "not an Aurorae plugin - the $ID decoration will not load" ;;
esac
printf '  %-22s %s\n' "deco theme"     "$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key theme)"
bl="$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnLeft)"
br="$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnRight)"
printf '  %-22s %s\n' "buttons left"   "${bl:-<unset>}"
printf '  %-22s %s\n' "buttons right"  "${br:-<unset>}"
# Plasma 6.6 drops these two when applying a look-and-feel (WhiteSur-kde#130), which
# is why install.sh writes them explicitly. If they are wrong, that write did not run.
[[ "$bl" == "$BUTTONS_LEFT" && "$br" == "$BUTTONS_RIGHT" ]] \
  && ok "button order is $BUTTONS_LEFT / $BUTTONS_RIGHT, as theme.env sets" \
  || note "button order is '${bl:-<unset>}' / '${br:-<unset>}', theme.env wants $BUTTONS_LEFT / $BUTTONS_RIGHT - re-run install.sh --apply"

echo "Plasma style internals"
if [[ -f "$STYLE_DEST/widgets/plasmoidheading.svg" ]]; then
  ok "widgets/plasmoidheading.svg present - Kickoff header/footer will not be opaque Breeze bands"
  python3 - "$STYLE_DEST" <<'PYEOF' 2>/dev/null || note "python3 unavailable - skipped the margin parity check"
import re, sys, os
T = sys.argv[1]
def margins(p):
    s = open(p).read(); out = {}
    for m in re.finditer(r'<rect id="hint-(top|bottom|left|right)-margin"[^>]*width="(\d+)"[^>]*height="(\d+)"', s):
        edge, w, h = m.group(1), int(m.group(2)), int(m.group(3))
        out[edge] = h if edge in ("top", "bottom") else w
    return out
d = margins(os.path.join(T, "dialogs/background.svg"))
p = margins(os.path.join(T, "widgets/plasmoidheading.svg"))
if d == p:
    print(f"  \033[1;32mok\033[0m    heading margins match dialogs/background {d}")
else:
    print(f"  \033[1;31mFAIL\033[0m  heading margins {p} != dialog margins {d} - Kickoff's header will misalign")
PYEOF
  op=$(grep -o 'opacity="[0-9.]*"' "$STYLE_DEST/widgets/plasmoidheading.svg" | grep -v 'opacity="0"' | head -1 | cut -d'"' -f2)
  dlg=$(grep -o 'opacity="[0-9.]*"' "$STYLE_DEST/dialogs/background.svg" | grep -v 'opacity="0"' | head -1 | cut -d'"' -f2)
  awk -v o="${op:-0}" 'BEGIN{ if (o+0 > 0.15) exit 1 }' \
    && ok "heading tint ${op:-0} over a ${dlg:-?} dialog - stacks to $(awk -v o="${op:-0}" -v d="${dlg:-0.88}" 'BEGIN{printf "%.1f%%", 100*(1-(1-d)*(1-o))}')" \
    || bad "heading tint ${op:-0} is high - it compounds with the dialog and will look solid"
else
  bad "widgets/plasmoidheading.svg missing - Kickoff falls back to Breeze's OPAQUE header/footer"
fi

# Plasma sets the KSvg selector "translucent" whenever KWin's blur effect is active
# (libplasma theme_p.cpp, updateKSvgSelectors). These four paths then resolve from
# translucent/ first. A theme without them loses to Breeze's copies.
missing=0
for f in dialogs/background.svg widgets/background.svg widgets/panel-background.svg widgets/tooltip.svg; do
  [[ -f "$STYLE_DEST/translucent/$f" ]] || { bad "translucent/$f MISSING - Breeze's copy wins while blur is on"; missing=1; }
done
if [[ $missing -eq 0 ]]; then
  ok "translucent/ set complete (4 files) - these are what Plasma uses while blur is on"
  drift=0
  for f in dialogs/background.svg widgets/background.svg widgets/panel-background.svg widgets/tooltip.svg; do
    a=$(md5sum "$STYLE_DEST/$f" | cut -d' ' -f1); b=$(md5sum "$STYLE_DEST/translucent/$f" | cut -d' ' -f1)
    [[ "$a" == "$b" ]] || { note "translucent/$f differs from the top-level copy"; drift=1; }
  done
  [[ $drift -eq 0 ]] && ok "translucent/ matches top-level - no drift"
  tl=$(grep -o 'opacity="[0-9.]*"' "$STYLE_DEST/translucent/dialogs/background.svg" | grep -v 'opacity="0"' | head -1 | cut -d'"' -f2)
  printf '        effective popup opacity: %s\n' "${tl:-?}"
fi

echo "icon theme (a dependency, not shipped here)"
found=""
for d in "$DATA/icons/$ICON_THEME" "/usr/share/icons/$ICON_THEME"; do
  [[ -f "$d/index.theme" ]] && { found="$d"; break; }
done
if [[ -n "$found" ]]; then
  ok "$ICON_THEME at $found"
  printf '        %s files, %s\n' "$(find "$found" -type f | wc -l)" "$(du -sh "$found" | cut -f1)"
  inh=$(grep -m1 '^Inherits=' "$found/index.theme" | cut -d= -f2)
  case "$inh" in
    *breeze*) ok "inherits breeze ($inh) - missing icons fall back to Breeze" ;;
    *)        bad "does NOT inherit breeze ($inh) - expect blank icons for anything it lacks" ;;
  esac
  grep -qi '^FollowsColorScheme=true' "$found/index.theme" \
    && ok "FollowsColorScheme=true - recolours with the active scheme" \
    || note "no FollowsColorScheme - icons keep their own colours"
else
  bad "$ICON_THEME not installed - run bin/icons.sh --variant $SLUG"
fi

echo "GTK applications"
if [[ -f "$GTK_DEST/gtk-3.0/gtk.css" ]]; then
  ok "$ID GTK theme installed ($(find "$GTK_DEST" -type f | wc -l) files)"
  gbg=$(grep -m1 '@define-color theme_bg_color_breeze' "$GTK_DEST/gtk-3.0/gtk.css" | sed 's/.*breeze //; s/;//')
  if [[ -n "$want" ]]; then
    [[ "$gbg" == "$want" ]] && ok "GTK background $gbg matches the colour scheme" \
                            || note "GTK background $gbg vs scheme $want - run bin/gtk.sh --variant $SLUG --rebuild"
  else
    note "GTK background $gbg (no base scheme on this host to compare against)"
  fi
  live_gtk=$(grep -m1 '^gtk-theme-name=' "$CONF/gtk-3.0/settings.ini" 2>/dev/null | cut -d= -f2)
  [[ "$live_gtk" == "$ID" ]] && ok "gtk-3.0/settings.ini points at $ID" \
                             || note "gtk-3.0 gtk-theme-name is '${live_gtk:-<unset>}' - run bin/gtk.sh --variant $SLUG"
  live_pref=$(grep -m1 '^gtk-application-prefer-dark-theme=' "$CONF/gtk-3.0/settings.ini" 2>/dev/null | cut -d= -f2)
  [[ "$live_pref" == "$GTK_PREFER_DARK" ]] && ok "prefer-dark-theme=$live_pref matches this variant" \
                                           || note "prefer-dark-theme='${live_pref:-<unset>}', this variant wants $GTK_PREFER_DARK - GTK and Electron apps will look one theme behind"
else
  note "$ID GTK theme not installed - run bin/gtk.sh --variant $SLUG (optional; Qt apps are unaffected)"
fi
if grep -qs 'applyColorsToNonQtApps=true' "$CONF/kdeglobals"; then
  note "'apply colors to non-Qt applications' is ON - it will overwrite the GTK theme"
fi

echo "cursors"
cfound=""
for d in "$DATA/icons/$CURSOR_THEME" "/usr/share/icons/$CURSOR_THEME"; do
  [[ -d "$d/cursors" ]] && { cfound="$d"; break; }
done
if [[ -n "$cfound" ]]; then
  ok "$CURSOR_THEME installed at $cfound ($(find "$cfound/cursors" -maxdepth 1 | wc -l) entries)"
else
  bad "$CURSOR_THEME not installed - sudo apt install breeze-cursor-theme"
fi
live_cursor="$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme 2>/dev/null)"
printf '  %-22s %s\n' "live cursorTheme" "${live_cursor:-<unset, X11 default>}"
printf '  %-22s %s\n' "live cursorSize" "$(kreadconfig6 --file kcminputrc --group Mouse --key cursorSize 2>/dev/null || echo '<unset, Plasma default>')"
case "$live_cursor" in
  "$CURSOR_THEME") ok "matches what this variant sets" ;;
  "")              note "unset - apply the global theme, or: plasma-apply-cursortheme $CURSOR_THEME" ;;
  *)               note "is '$live_cursor', this variant sets '$CURSOR_THEME' - apply the global theme to change it" ;;
esac
# shellcheck disable=SC2088  # the tilde is prose; the test above uses $HOME
[[ -f "$HOME/.icons/default/index.theme" ]] && note "~/.icons/default/index.theme exists: $(grep -m1 -i '^Inherits' "$HOME/.icons/default/index.theme" 2>/dev/null) - legacy XCursor override, it can win over kcminputrc for some X11/GTK apps"

echo "translucency prerequisites"
if [[ -f "$STYLE_DEST/plasmarc" ]]; then
  ce=$(awk '/^\[ContrastEffect\]/{f=1;next} /^\[/{f=0} f&&/^enabled=/{sub(/^enabled=/,"");print;exit}' "$STYLE_DEST/plasmarc")
  case "$ce" in
    false) ok "ContrastEffect off - blur alone, so the wallpaper reads through" ;;
    true)  note "ContrastEffect ON - it homogenises the backdrop and can make a translucent"
           note "surface look like flat paint. Set enabled=false if it looks opaque." ;;
    *)     note "ContrastEffect unset in $STYLE_DEST/plasmarc" ;;
  esac
fi
blur="$(kreadconfig6 --file kwinrc --group Plugins --key blurEnabled 2>/dev/null)"
case "$blur" in
  false) bad "KWin Blur effect is OFF - translucent surfaces will look washed out, not frosted" ;;
  "")    ok  "KWin Blur effect at default (on)" ;;
  *)     ok  "KWin Blur effect = $blur" ;;
esac
APPLETS="$CONF/plasma-org.kde.plasma.desktop-appletsrc"
if [[ -f "$APPLETS" ]]; then
  if grep -q 'panelOpacity' "$APPLETS"; then
    echo "  per-panel opacity keys found (this OVERRIDES the Plasma style):"
    grep -n 'panelOpacity' "$APPLETS" | sed 's/^/        /'
    note "if a panel looks opaque: Edit Mode -> More Options -> Opacity -> Translucent"
  else
    note "no panelOpacity key set - panels are on the default (Adaptive), which goes"
    note "opaque when a window is maximised. Set Opacity -> Translucent to see the style."
  fi
fi

echo "kwin decoration errors in this session"
journalctl --user -b -u plasma-kwin_wayland -u plasma-kwin_x11 --no-pager 2>/dev/null \
  | grep -iE "aurorae|decoration" | tail -5 || note "nothing logged (or journald unavailable)"
