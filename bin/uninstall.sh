#!/usr/bin/env bash
# Rollback. Restores the appearance keys captured by install.sh --apply, then removes
# this variant's packages.
#
# Usage:  uninstall.sh --variant light [path/to/backup.env]
# UNTESTED.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

BAK="${1:-$STATE/backup-latest.env}"
say "$NAME - rollback"

# A backup records whatever was live when install.sh --apply ran. Two ways that is not
# safe to replay verbatim:
#
#   1. It can name THIS variant. Applying dark twice makes the second backup record
#      OLD_LNF=QuantumDark, and restoring that then deleting the packages leaves a
#      global theme pointing at nothing - measured on quantum as
#      'aurorae: Could not find decoration svg for "QuantumDark"'.
#   2. It can name something since removed, by hand or by the sibling's uninstall.
#
# So every restore is: refuse this variant's own ids, then require that what the value
# names still exists, then fall back to stock. What it actually did is reported, because
# a rollback that silently did something else is worse than one that says so.

lnf_exists() {
  local id="$1" d
  for d in "$DATA/plasma/look-and-feel/$id" "/usr/share/plasma/look-and-feel/$id"; do
    [[ -d "$d" ]] && return 0
  done
  return 1
}
scheme_exists() {
  local n="$1" d
  for d in "$DATA/color-schemes/$n.colors" "/usr/share/color-schemes/$n.colors"; do
    [[ -f "$d" ]] && return 0
  done
  return 1
}
style_exists() {
  local n="$1" d
  for d in "$DATA/plasma/desktoptheme/$n" "/usr/share/plasma/desktoptheme/$n"; do
    [[ -d "$d" ]] && return 0
  done
  return 1
}
icons_exist() {
  local n="$1" d
  for d in "$DATA/icons/$n" "/usr/share/icons/$n"; do
    [[ -f "$d/index.theme" ]] && return 0
  done
  return 1
}

if [[ -f "$BAK" ]]; then
  # shellcheck disable=SC1090
  source "$BAK"
  say "restoring from $BAK"

  # ---- global theme ----------------------------------------------------------
  target="${OLD_LNF:-}"
  if [[ -z "$target" ]]; then
    say "no previous global theme recorded - falling back to org.kde.breeze.desktop"
    target=org.kde.breeze.desktop
  elif [[ "$target" == "$ID" ]]; then
    warn "the backup names $ID, the theme being removed - falling back to org.kde.breeze.desktop"
    target=org.kde.breeze.desktop
  elif ! lnf_exists "$target"; then
    warn "the recorded global theme $target is no longer installed - falling back to org.kde.breeze.desktop"
    target=org.kde.breeze.desktop
  fi
  say "global theme -> $target"
  plasma-apply-lookandfeel -a "$target" >/dev/null 2>&1 \
    || warn "plasma-apply-lookandfeel failed for $target - set it in System Settings"

  # Everything below is written AFTER the look-and-feel, which sets several of these
  # keys itself from its own contents/defaults.

  # ---- colour scheme ---------------------------------------------------------
  # Backed up since the first version and never restored until now: uninstall deleted
  # <ID>.colors while leaving kdeglobals pointing at it. Measured on quantum, where
  # 'colour scheme QuantumLight' survived the removal of that very file.
  cs="${OLD_COLORSCHEME:-}"
  if [[ -z "$cs" || "$cs" == "$ID" ]] || ! scheme_exists "$cs"; then
    [[ "$cs" == "$ID" ]] && warn "the backup's colour scheme is $ID, which is being deleted"
    cs="$BASE_SCHEME"
  fi
  say "colour scheme -> $cs"
  kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$cs"

  # ---- widget style ----------------------------------------------------------
  # Also backed up and never restored.
  say "widget style -> ${OLD_WIDGETSTYLE:-$WIDGET_STYLE}"
  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle "${OLD_WIDGETSTYLE:-$WIDGET_STYLE}"

  # ---- decoration ------------------------------------------------------------
  deco_theme="${OLD_DECO_THEME:-}"
  deco_lib="${OLD_DECO_LIBRARY:-}"
  if [[ -z "$deco_theme" || "$deco_theme" == "__aurorae__svg__$ID" ]]; then
    [[ "$deco_theme" == "__aurorae__svg__$ID" ]] && warn "the backup's decoration is this theme's - falling back to Breeze"
    deco_theme=Breeze; deco_lib=org.kde.breeze
  fi
  say "decoration -> ${deco_lib:-org.kde.breeze} / $deco_theme"
  kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key library "${deco_lib:-org.kde.breeze}"
  kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key theme   "$deco_theme"
  [[ -n "${OLD_BTN_LEFT:-}"  ]] && kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnLeft  "$OLD_BTN_LEFT"
  [[ -n "${OLD_BTN_RIGHT:-}" ]] && kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnRight "$OLD_BTN_RIGHT"

  # ---- Plasma style ----------------------------------------------------------
  # Breeze's own Plasma style is called "default", not "Breeze".
  ps="${OLD_PLASMATHEME:-}"
  if [[ -z "$ps" || "$ps" == "$ID" ]] || ! style_exists "$ps"; then
    [[ "$ps" == "$ID" ]] && warn "the backup's Plasma style is $ID, which is being deleted"
    ps=default
  fi
  say "plasma style -> $ps"
  kwriteconfig6 --file plasmarc --group Theme --key name "$ps"

  # ---- icons -----------------------------------------------------------------
  # This variant's icon theme is NOT deleted, so naming it is legitimate; only a
  # genuinely missing theme is replaced.
  ic="${OLD_ICONS:-}"
  if [[ -n "$ic" ]] && ! icons_exist "$ic"; then
    warn "the recorded icon theme $ic is not installed - leaving icons alone"
    ic=""
  fi
  [[ -n "$ic" ]] && { say "icons -> $ic"; kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ic"; }

  # ---- cursors, blur ---------------------------------------------------------
  if [[ -n "${OLD_CURSOR:-}" ]]; then
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$OLD_CURSOR"
    command -v plasma-apply-cursortheme >/dev/null && plasma-apply-cursortheme "$OLD_CURSOR" >/dev/null 2>&1 || true
  fi
  [[ -n "${OLD_BLUR:-}" ]] && kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled "$OLD_BLUR"
  if command -v qdbus6 >/dev/null; then qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true; fi
else
  say "no backup at $BAK - only removing the packages"
  say "reset appearance by hand: System Settings -> Colors & Themes -> Global Theme -> Breeze"
fi

say "removing $ID packages"
rm -rf "$AURORAE_DEST" "$STYLE_DEST" "$LNF_DEST" "$GTK_DEST"
rm -f  "$SCHEME_DEST"
rm -rf "$CACHE"/plasma_theme_*.kcache "$CACHE"/icon-cache.kcache 2>/dev/null || true
say "note: GTK settings still name $ID; set another theme in"
say "      System Settings -> Application Style -> GNOME/GTK Application Style"
say "note: the $ICON_THEME theme itself is left in place."
say "      remove it with: rm -rf \"$DATA/icons/$ICON_THEME\""
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
command -v kquitapp6 >/dev/null && { kquitapp6 plasmashell 2>/dev/null || true; sleep 2; (setsid plasmashell >/dev/null 2>&1 &); }
say "done"
