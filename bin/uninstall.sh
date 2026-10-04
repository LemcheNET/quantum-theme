#!/usr/bin/env bash
# Rollback. Reverts to KDE's own stock global theme, then removes this variant's
# packages.
#
# Usage:  uninstall.sh --variant light
#         uninstall.sh --variant light --restore-backup [path/to/backup.env]
#
# WHY STOCK RATHER THAN "WHAT YOU HAD BEFORE"
#
# install.sh --apply records eleven appearance keys before it changes anything, and the
# first version of this script replayed them. Every rollback defect found on quantum
# came from that replay:
#
#   * The backup can name THIS variant. Applying dark while dark is already live records
#     OLD_LNF=QuantumDark, so the rollback restored QuantumDark and then deleted its
#     packages - 'aurorae: Could not find decoration svg for "QuantumDark"'.
#   * It can name something since removed by hand or by the sibling's uninstall.
#   * With both variants installed, "what was there before" is ambiguous: light's
#     backup records dark, so uninstalling light re-applied dark.
#   * Two keys were captured and never written back at all, leaving kdeglobals pointing
#     at a .colors file this script had just deleted.
#
# Reverting to stock has none of those failure modes. Breeze is present on every Plasma
# install, KDE's own look-and-feel package sets its own keys correctly, and the outcome
# is one sentence a stranger can be told in advance.
#
# The cost, stated plainly: if you had a third-party global theme or a hand-built colour
# scheme before installing this, stock Breeze is not where you were. The backup is still
# written, --restore-backup still replays it, and the timestamped copies of kdeglobals,
# kwinrc, plasmarc and kcminputrc beside it are the honest escape hatch - a file copy
# beats replaying eleven keys.
#
# UNTESTED in this form.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

MODE=stock
BAK="$STATE/backup-latest.env"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --restore-backup) MODE=backup; shift ;;
    -*)               die "unknown argument: $1" ;;
    *)                BAK="$1"; MODE=backup; shift ;;
  esac
done

say "$NAME - rollback ($MODE)"

lnf_exists() {
  local id="$1" d
  for d in "$DATA/plasma/look-and-feel/$id" "/usr/share/plasma/look-and-feel/$id"; do
    [[ -d "$d" ]] && return 0
  done
  return 1
}

# Resolve the stock theme against what the host has rather than trusting an id. Plasma
# has renamed these before, and a host can be missing the dark counterpart.
resolve_stock() {
  local c
  for c in "$STOCK_LNF" org.kde.breeze.desktop; do
    [[ "$c" == "$ID" ]] && continue
    lnf_exists "$c" && { printf '%s\n' "$c"; return 0; }
  done
  # last resort: ask Plasma what it has and take the first Breeze that is not ours
  if command -v plasma-apply-lookandfeel >/dev/null; then
    c=$(plasma-apply-lookandfeel --list 2>/dev/null | tr -d ' *' | grep -i '^org\.kde\.breeze' | grep -v "^$ID$" | head -1)
    [[ -n "$c" ]] && { printf '%s\n' "$c"; return 0; }
  fi
  return 1
}

restore_from_backup() {
  [[ -f "$BAK" ]] || die "no backup at $BAK (use --variant $SLUG with no flag to revert to stock instead)"
  # shellcheck disable=SC1090
  source "$BAK"
  warn "replaying a recorded backup is best-effort - see the header of this script"
  say "restoring from $BAK"

  local target="${OLD_LNF:-}"
  if [[ -z "$target" || "$target" == "$ID" ]] || ! lnf_exists "$target"; then
    warn "the recorded global theme (${OLD_LNF:-<unset>}) is this variant or is gone - using stock"
    target="$(resolve_stock)" || die "no stock global theme found on this host"
  fi
  say "global theme -> $target"
  plasma-apply-lookandfeel -a "$target" >/dev/null 2>&1 \
    || warn "plasma-apply-lookandfeel failed for $target - set it in System Settings"

  # Written after the look-and-feel, which sets several of these itself.
  local cs="${OLD_COLORSCHEME:-}"
  if [[ -n "$cs" && "$cs" != "$ID" ]]; then
    say "colour scheme -> $cs"
    kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$cs"
  fi
  [[ -n "${OLD_WIDGETSTYLE:-}" ]] && {
    say "widget style -> $OLD_WIDGETSTYLE"
    kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle "$OLD_WIDGETSTYLE"; }
  [[ -n "${OLD_ICONS:-}" ]] && kwriteconfig6 --file kdeglobals --group Icons --key Theme "$OLD_ICONS"
  [[ -n "${OLD_BTN_LEFT:-}"  ]] && kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnLeft  "$OLD_BTN_LEFT"
  [[ -n "${OLD_BTN_RIGHT:-}" ]] && kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnRight "$OLD_BTN_RIGHT"
  [[ -n "${OLD_BLUR:-}" ]] && kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled "$OLD_BLUR"
  if [[ -n "${OLD_CURSOR:-}" ]]; then
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$OLD_CURSOR"
    command -v plasma-apply-cursortheme >/dev/null && plasma-apply-cursortheme "$OLD_CURSOR" >/dev/null 2>&1 || true
  fi
}

revert_to_stock() {
  local target
  target="$(resolve_stock)" || die "no stock Breeze global theme on this host - install the 'breeze' package, or use --restore-backup"
  say "reverting to KDE's stock global theme: $target"
  # One command, and the look-and-feel package sets its own colour scheme, widget
  # style, Plasma style, decoration and cursors from its own contents/defaults. That
  # is the whole reason this path has no key-by-key replay.
  plasma-apply-lookandfeel -a "$target" >/dev/null 2>&1 \
    || die "plasma-apply-lookandfeel failed for $target - set the Global Theme in System Settings, then re-run"
  # Blur is the one thing install.sh --apply may have turned on that stock Breeze does
  # not set either way, so leave it as the user has it rather than guessing.
  say "left alone: KWin blur, panel opacity, cursor size - stock Breeze does not set them"
}

case "$MODE" in
  stock)  revert_to_stock ;;
  backup) restore_from_backup ;;
esac

if command -v qdbus6 >/dev/null; then qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true; fi

say "removing $ID packages"
rm -rf "$AURORAE_DEST" "$STYLE_DEST" "$LNF_DEST" "$GTK_DEST"
rm -f  "$SCHEME_DEST"
rm -rf "$CACHE"/plasma_theme_*.kcache "$CACHE"/icon-cache.kcache 2>/dev/null || true

say "note: the $ICON_THEME icon theme is left in place."
say "      remove it with: rm -rf \"$DATA/icons/$ICON_THEME\""
if [[ -d "$STATE" ]]; then
  say "note: your pre-install settings are still recorded in $STATE -"
  say "      backup-*.env plus timestamped copies of kdeglobals, kwinrc, plasmarc and"
  say "      kcminputrc. Copying one of those back is the most reliable rollback there is."
fi
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
command -v kquitapp6 >/dev/null && { kquitapp6 plasmashell 2>/dev/null || true; sleep 2; (setsid plasmashell >/dev/null 2>&1 &); }
say "done. Verify with bin/verify.sh --variant $SLUG (it should now report the packages missing)"
