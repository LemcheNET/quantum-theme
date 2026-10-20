#!/usr/bin/env bash
# Keep the GTK theme in step with the desktop's light/dark preference.
#
# Why this exists: Plasma's automatic day/night switch updates the portal preference
# (gsettings color-scheme) but not the GTK theme NAME. GTK4/libadwaita apps follow the
# preference live. GTK3 apps ignore it and only react live to a change of gtk-theme, so
# they stay on the old variant until restarted. This script closes that gap: whenever
# color-scheme changes, it sets gtk-theme to the variant that declares that preference.
#
# It also follows the icon theme (ICON_THEME). Plasma's own GTK sync (the kded module
# gtkconfig) would otherwise do that, but it also pushes the KDE colour scheme into running
# GTK apps through ~/.config/gtk-{3,4}.0/colors.css, and during an automatic day/night
# switch that push can land on the outgoing scheme: running GTK and Electron apps end up
# inverted while new ones start correct. With gtkconfig off, this script is the only
# writer, and it writes the settled value once.
#
# Which theme goes with which preference is read from variants/<slug>/variant.env
# (PORTAL_PREF, ID, GTK_PREFER_DARK, ICON_THEME), so nothing about a variant is written
# down here.
#
# Usage:  gtk-follow.sh              apply once, then watch for changes (what the unit runs)
#         gtk-follow.sh --once       apply once and exit
#         gtk-follow.sh --check      report live vs expected, change nothing; exit 1 if they differ
#         gtk-follow.sh --install-service     install and start the per-user systemd unit
#         gtk-follow.sh --uninstall-service   stop it and remove it
#
# Writes only per-user settings: gsettings, and the gtk-theme-name / prefer-dark keys in
# ~/.config/gtk-{3,4}.0/settings.ini and ~/.gtkrc-2.0 / xsettingsd IF those already exist
# (gtk.sh creates them; this only keeps them current).
#
# The two *-service options are the only code in bin/ or lib/ that runs systemctl, and
# only ever as `systemctl --user`, only when you ask. tests/run-tests.sh enforces both.
# UNTESTED against a live Plasma session; the unit tests cover the logic.
set -euo pipefail
# shellcheck disable=SC2034  # read by quantum_init in lib/common.sh, sourced next
QUANTUM_VARIANT_OPTIONAL=1
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

SCHEMA=org.gnome.desktop.interface
MODE=watch
case "${1:-}" in
  "" | --watch) MODE=watch ;;
  --once)       MODE=once ;;
  --check)      MODE=check ;;
  --install-service)   MODE=install ;;
  --uninstall-service) MODE=uninstall ;;
  -h | --help)  sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
  *)            die "unknown option '$1' (try --help)" ;;
esac

UNIT=quantum-gtk-follow.service
UNIT_SRC="$QUANTUM_ROOT/systemd/$UNIT"
UNIT_DEST="$CONF/systemd/user/$UNIT"

if [[ "$MODE" == install ]]; then
  command -v systemctl >/dev/null || die "systemctl not found; this needs a systemd user session"
  [[ -f "$UNIT_SRC" ]] || die "$UNIT_SRC missing"
  mkdir -p "$(dirname "$UNIT_DEST")"
  unit="$(<"$UNIT_SRC")"
  printf '%s\n' "${unit//@QUANTUM_ROOT@/$QUANTUM_ROOT}" > "$UNIT_DEST"
  say "wrote $UNIT_DEST (runs $QUANTUM_ROOT/bin/gtk-follow.sh)"
  systemctl --user daemon-reload
  systemctl --user enable --now "$UNIT"
  say "enabled and started; follow it with: journalctl --user -u $UNIT"
  exit 0
fi
if [[ "$MODE" == uninstall ]]; then
  command -v systemctl >/dev/null || die "systemctl not found; this needs a systemd user session"
  systemctl --user disable --now "$UNIT" 2>/dev/null || true
  rm -f "$UNIT_DEST"
  systemctl --user daemon-reload
  say "removed $UNIT"
  exit 0
fi

command -v gsettings >/dev/null || die "gsettings not found; it ships in libglib2.0-bin"
mapfile -t ALL < <(quantum_variants)

gget() { gsettings get "$SCHEMA" "$1" 2>/dev/null | tr -d "'"; }

# The slug of the variant that declares this portal preference, if any.
slug_for() {
  local s
  for s in "${ALL[@]}"; do
    if [[ "$(quantum_variant_get "$s" PORTAL_PREF)" == "$1" ]]; then printf '%s\n' "$s"; return 0; fi
  done
  return 1
}

# Replace a key's value in a settings file, only if the key is already there and differs.
# Creating files and keys is gtk.sh's job; this keeps what exists from going stale.
ini_follow() {  # file, key, value
  local f="$1" k="$2" v="$3"
  [[ -f "$f" ]] || return 0
  grep -q "^$k=" "$f" || return 0
  grep -qx "$k=$v" "$f" && return 0
  sed -i "s|^$k=.*|$k=$v|" "$f"
}

# GTK searches all three, so a system-wide install is as good as gtk.sh's per-user one.
theme_installed() { [[ -d "$DATA/themes/$1" || -d "$HOME/.themes/$1" || -d "$SYSDATA/themes/$1" ]]; }
icons_installed() { [[ -d "$DATA/icons/$1" || -d "$HOME/.icons/$1" || -d "$SYSDATA/icons/$1" ]]; }

# Keep the icon theme in step with the variant. Same rules as the theme: gsettings always,
# files only where the key already exists, and never select something not installed.
follow_icons() {  # slug
  local icons live_icons g xs
  icons="$(quantum_variant_get "$1" ICON_THEME)"
  [[ -n "$icons" ]] || return 0
  if ! icons_installed "$icons"; then
    warn "$icons is not installed (looked in $DATA/icons, ~/.icons, $SYSDATA/icons); run bin/icons.sh --variant $1 first"
    return 0
  fi
  live_icons="$(gget icon-theme)"
  if [[ "$live_icons" != "$icons" ]]; then
    gsettings set "$SCHEMA" icon-theme "$icons"
    say "icon-theme $live_icons -> $icons"
  fi
  for g in gtk-3.0 gtk-4.0; do
    ini_follow "$CONF/$g/settings.ini" gtk-icon-theme-name "$icons"
  done
  if [[ -f "$HOME/.gtkrc-2.0" ]] && grep -q '^gtk-icon-theme-name' "$HOME/.gtkrc-2.0" \
     && ! grep -qx "gtk-icon-theme-name=\"$icons\"" "$HOME/.gtkrc-2.0"; then
    sed -i "s|^gtk-icon-theme-name.*|gtk-icon-theme-name=\"$icons\"|" "$HOME/.gtkrc-2.0"
  fi
  xs="$CONF/xsettingsd/xsettingsd.conf"
  if [[ -f "$xs" ]] && grep -q '^Net/IconThemeName' "$xs" && ! grep -qx "Net/IconThemeName \"$icons\"" "$xs"; then
    sed -i "s|^Net/IconThemeName.*|Net/IconThemeName \"$icons\"|" "$xs"
    pkill -HUP xsettingsd 2>/dev/null || true
  fi
}

apply() {
  local pref slug id dark live g xs
  pref="$(gget color-scheme)"
  if ! slug="$(slug_for "$pref")"; then
    say "color-scheme is '$pref'; no variant declares it, leaving the GTK theme alone"
    return 0
  fi
  id="$(quantum_variant_get "$slug" ID)"
  dark="$(quantum_variant_get "$slug" GTK_PREFER_DARK)"
  if ! theme_installed "$id"; then
    warn "$id is not installed (looked in $DATA/themes, ~/.themes, $SYSDATA/themes); run bin/gtk.sh --variant $slug first"
    return 0
  fi

  live="$(gget gtk-theme)"
  if [[ "$live" != "$id" ]]; then
    gsettings set "$SCHEMA" gtk-theme "$id"
    say "color-scheme '$pref': gtk-theme $live -> $id"
  fi

  for g in gtk-3.0 gtk-4.0; do
    ini_follow "$CONF/$g/settings.ini" gtk-theme-name "$id"
    ini_follow "$CONF/$g/settings.ini" gtk-application-prefer-dark-theme "$dark"
  done
  if [[ -f "$HOME/.gtkrc-2.0" ]] && ! grep -qx "gtk-theme-name=\"$id\"" "$HOME/.gtkrc-2.0" \
     && grep -q '^gtk-theme-name' "$HOME/.gtkrc-2.0"; then
    sed -i "s|^gtk-theme-name.*|gtk-theme-name=\"$id\"|" "$HOME/.gtkrc-2.0"
  fi
  xs="$CONF/xsettingsd/xsettingsd.conf"
  if [[ -f "$xs" ]] && grep -q '^Net/ThemeName' "$xs" && ! grep -qx "Net/ThemeName \"$id\"" "$xs"; then
    sed -i "s|^Net/ThemeName.*|Net/ThemeName \"$id\"|" "$xs"
    pkill -HUP xsettingsd 2>/dev/null || true
  fi
  follow_icons "$slug"
}

if [[ "$MODE" == check ]]; then
  pref="$(gget color-scheme)"; live="$(gget gtk-theme)"
  printf '    %-24s %s\n' "color-scheme" "$pref" "gtk-theme (live)" "$live"
  if ! slug="$(slug_for "$pref")"; then
    note "no variant declares '$pref'; nothing to follow"
    exit 0
  fi
  want="$(quantum_variant_get "$slug" ID)"
  printf '    %-24s %s\n' "gtk-theme (expected)" "$want"
  rc=0
  if [[ "$live" == "$want" ]]; then ok "gtk-theme follows color-scheme"
  else bad "gtk-theme is $live but color-scheme calls for $want"; rc=1; fi
  wanti="$(quantum_variant_get "$slug" ICON_THEME)"
  if [[ -n "$wanti" ]]; then
    livei="$(gget icon-theme)"
    printf '    %-24s %s\n' "icon-theme (live)" "$livei" "icon-theme (expected)" "$wanti"
    if [[ "$livei" == "$wanti" ]]; then ok "icon-theme follows color-scheme"
    else bad "icon-theme is $livei but color-scheme calls for $wanti"; rc=1; fi
  fi
  exit "$rc"
fi

apply
[[ "$MODE" == once ]] && exit 0

say "watching $SCHEMA color-scheme"
gsettings monitor "$SCHEMA" color-scheme | while read -r _; do apply || true; done
die "gsettings monitor ended; is the session bus still up?"
