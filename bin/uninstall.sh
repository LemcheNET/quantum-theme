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

if [[ -f "$BAK" ]]; then
  # shellcheck disable=SC1090
  source "$BAK"
  say "restoring from $BAK"
  if [[ -n "${OLD_LNF:-}" ]]; then
    plasma-apply-lookandfeel -a "$OLD_LNF"
  else
    say "no previous global theme recorded - falling back to org.kde.breeze.desktop"
    plasma-apply-lookandfeel -a org.kde.breeze.desktop
  fi
  kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key library  "${OLD_DECO_LIBRARY:-org.kde.breeze}"
  kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key theme    "${OLD_DECO_THEME:-Breeze}"
  [[ -n "${OLD_BTN_LEFT:-}"  ]] && kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnLeft  "$OLD_BTN_LEFT"
  [[ -n "${OLD_BTN_RIGHT:-}" ]] && kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnRight "$OLD_BTN_RIGHT"
  [[ -n "${OLD_PLASMATHEME:-}" ]] && kwriteconfig6 --file plasmarc --group Theme --key name "$OLD_PLASMATHEME"
  [[ -n "${OLD_ICONS:-}" ]] && kwriteconfig6 --file kdeglobals --group Icons --key Theme "$OLD_ICONS"
  if [[ -n "${OLD_CURSOR:-}" ]]; then
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$OLD_CURSOR"
    command -v plasma-apply-cursortheme >/dev/null && plasma-apply-cursortheme "$OLD_CURSOR" 2>/dev/null || true
  fi
  [[ -n "${OLD_BLUR:-}" ]] && kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled "$OLD_BLUR"
  if command -v qdbus6 >/dev/null; then qdbus6 org.kde.KWin /KWin reconfigure; fi
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
