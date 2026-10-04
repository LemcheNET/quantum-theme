#!/usr/bin/env bash
# Installer. UNTESTED: written without a shell on the target host. Read it before running.
#
# Intent       : install one variant's Aurorae decoration, Plasma style and global theme
#                into the current user's ~/.local/share, optionally apply.
# Blast radius : per-user only. No sudo. No system paths touched.
#                With --apply: rewrites appearance keys in kdeglobals, kwinrc, plasmarc,
#                kcminputrc and restarts plasmashell. Panels are NOT touched (the package
#                ships no layout). Current values are backed up first.
# Rollback     : bin/uninstall.sh --variant <slug>
#
# Usage:  install.sh --variant light                       # copy only, apply nothing
#         install.sh --variant light --apply               # back up, apply, reload
#         install.sh --variant light --apply --force-icons # apply without the icon theme
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

APPLY=0
FORCE_ICONS=0
for a in "$@"; do
  case "$a" in
    --apply)       APPLY=1 ;;
    --force-icons) FORCE_ICONS=1 ;;
    *)             die "unknown argument: $a" ;;
  esac
done

say "$NAME $QUANTUM_VERSION (variant: $SLUG)"

# ---- pre-checks --------------------------------------------------------
command -v plasmashell >/dev/null || die "plasmashell not found; is this a Plasma session?"
# plasmashell --version writes QThreadStorage warnings to stderr on exit, which
# read as errors at the top of an install. They are not ours.
PLASMA_VER="$(plasmashell --version 2>/dev/null | awk '{print $NF}')"
say "Plasma $PLASMA_VER"
case "$PLASMA_VER" in
  6.*) ;;
  *) die "This package targets Plasma 6. Found $PLASMA_VER - stopping." ;;
esac

[[ -f "$BASE_SCHEME_FILE" ]] || warn "missing $BASE_SCHEME_FILE - the colour scheme may not apply (install kde-style-breeze / breeze)"

# Cursors: breeze_cursors ships with Breeze on Kubuntu (package breeze-cursor-theme).
# Which variant each theme wants is in variants/<slug>/variant.env.
CURSOR_FOUND=""
for d in "$DATA/icons/$CURSOR_THEME" "$SYSDATA/icons/$CURSOR_THEME"; do
  [[ -d "$d/cursors" ]] && { CURSOR_FOUND="$d"; break; }
done
if [[ -n "$CURSOR_FOUND" ]]; then
  say "cursor theme $CURSOR_THEME found at $CURSOR_FOUND"
else
  warn "cursor theme $CURSOR_THEME not found - install it:  sudo apt install breeze-cursor-theme"
  warn "without it the pointer falls back to the X11 default black arrow"
fi

# The icon theme is a dependency, not part of this package: 13k-19k files and
# 180-215 MiB depending on the variant.
ICON_FOUND=""
for d in "$DATA/icons/$ICON_THEME" "$SYSDATA/icons/$ICON_THEME"; do
  [[ -f "$d/index.theme" ]] && { ICON_FOUND="$d"; break; }
done
if [[ -n "$ICON_FOUND" ]]; then
  say "icon theme $ICON_THEME found at $ICON_FOUND"
else
  warn "icon theme $ICON_THEME is NOT installed."
  warn "The global theme points at it; without it Plasma falls back to whatever it"
  warn "resolves next and your icons will not be what this theme intends."
  warn "Fetch it first:  bin/icons.sh --variant $SLUG"
  if [[ $APPLY -eq 1 && $FORCE_ICONS -eq 0 ]]; then
    die "refusing to --apply with a missing icon theme. Run bin/icons.sh, or pass --force-icons."
  fi
fi

# Which Aurorae plugins does this host actually have? Reported, not guessed.
say "Aurorae decoration plugins present:"
# shellcheck disable=SC2086  # QT_PLUGIN_GLOBS is a deliberately unquoted glob list
find $QT_PLUGIN_GLOBS -iname '*aurorae*' 2>/dev/null | sed 's/^/    /' || true
say "library id before: $(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key library 2>/dev/null || echo '<unset>')"
kwriteconfig6 --help >/dev/null 2>&1 || warn "kwriteconfig6 not found - --apply button fix-up will be skipped"

# ---- install (idempotent) ---------------------------------------------
install_pkg() {
  local what="$1" src="$2" dest="$3"
  [[ -d "$src" ]] || die "missing source package: $src"
  # All three packages are named after the id, so naming the KIND is the only way to
  # tell these three lines apart.
  say "installing the $what -> $dest"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  cp -a "$src" "$dest"
}
install_pkg "Aurorae decoration" "$AURORAE_SRC" "$AURORAE_DEST"
install_pkg "Plasma style"       "$STYLE_SRC"   "$STYLE_DEST"
install_pkg "global theme"       "$LNF_SRC"     "$LNF_DEST"

if command -v kbuildsycoca6 >/dev/null; then kbuildsycoca6 --noincremental >/dev/null 2>&1 || true; fi

if [[ $APPLY -eq 0 ]]; then
  cat <<MSG

Not applied. Either:
  System Settings -> Colors & Themes -> Global Theme -> "$NAME" -> Apply
      (untick "Desktop layout" if offered - this package ships none, but the KCM may
       still offer to reset your panels)
or re-run:  bin/install.sh --variant $SLUG --apply
MSG
  exit 0
fi

# ---- backup before applying -------------------------------------------
mkdir -p "$STATE"
STAMP="$(date +%Y%m%d-%H%M%S)"
BAK="$STATE/backup-$STAMP.env"
say "backing up current appearance settings to $BAK"
# Applying a variant that is ALREADY live would otherwise record itself as the thing to
# roll back to, and uninstall would then restore a theme it is about to delete. The
# uninstaller guards against this too; recording a sane value is the cheaper half.
was() {  # key reading command's output, with this variant's own id replaced by a stock one
  local current="$1" stock="$2"
  [[ "$current" == "$ID" || "$current" == "__aurorae__svg__$ID" ]] && { printf '%s\n' "$stock"; return; }
  printf '%s\n' "$current"
}
{
  echo "# restore with uninstall.sh, or by hand with kwriteconfig6"
  echo "# values naming $ID were replaced with stock at capture time: applying a variant"
  echo "# that is already live must not record itself as the rollback target."
  echo "OLD_LNF=$(was "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage 2>/dev/null || true)" org.kde.breeze.desktop)"
  echo "OLD_COLORSCHEME=$(was "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || true)" "$BASE_SCHEME")"
  echo "OLD_WIDGETSTYLE=$(kreadconfig6 --file kdeglobals --group KDE --key widgetStyle 2>/dev/null || true)"
  echo "OLD_ICONS=$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || true)"
  echo "OLD_PLASMATHEME=$(was "$(kreadconfig6 --file plasmarc --group Theme --key name 2>/dev/null || true)" default)"
  echo "OLD_BLUR=$(kreadconfig6 --file kwinrc --group Plugins --key blurEnabled 2>/dev/null || true)"
  echo "OLD_CURSOR=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme 2>/dev/null || true)"
  echo "OLD_DECO_LIBRARY=$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key library 2>/dev/null || true)"
  echo "OLD_DECO_THEME=$(was "$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key theme 2>/dev/null || true)" Breeze)"
  echo "OLD_BTN_LEFT=$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnLeft 2>/dev/null || true)"
  echo "OLD_BTN_RIGHT=$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnRight 2>/dev/null || true)"
} > "$BAK"
ln -sfn "$BAK" "$STATE/backup-latest.env"
for c in kdeglobals kwinrc plasmarc kcminputrc; do
  [[ -f "$CONF/$c" ]] && cp -a "$CONF/$c" "$STATE/$c.$STAMP"
done

# ---- apply -------------------------------------------------------------
# Breeze's [Colors:Header] sits away from [Colors:Window] in both variants, so
# Kirigami-era app toolbars step away from the titlebar. Derive a scheme that closes it.
if [[ -x "$QUANTUM_ROOT/bin/colorscheme.sh" ]]; then
  say "deriving the $ID colour scheme from the installed $BASE_SCHEME"
  "$QUANTUM_ROOT/bin/colorscheme.sh" --variant "$SLUG" | sed 's/^/    /'
else
  warn "colorscheme.sh missing - falling back to stock $BASE_SCHEME (app headers will not match the titlebar)"
  kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$BASE_SCHEME"
fi

say "applying global theme $ID"
plasma-apply-lookandfeel -a "$ID"

# Plasma 6.6 applies library+theme from the look-and-feel but ignores the button
# positions (see WhiteSur-kde#130). Write them explicitly.
if command -v kwriteconfig6 >/dev/null; then
  say "writing titlebar button order explicitly"
  # NOT library/theme: plasma-apply-lookandfeel has just written those from
  # contents/defaults. Writing them again here overwrote the correct value with a
  # stale pre-check reading in v2.0 - the decoration silently fell back to Breeze.
  kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnLeft  "$BUTTONS_LEFT"
  kwriteconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key ButtonsOnRight "$BUTTONS_RIGHT"
fi

# A newly installed Plasma style is not picked up until the SVG cache is dropped.
say "clearing the Plasma SVG and icon caches"
rm -rf "$CACHE"/plasma_theme_*.kcache "$CACHE"/plasma-svgelements* "$CACHE"/icon-cache.kcache 2>/dev/null || true

# Translucency without blur just looks washed out.
if command -v kwriteconfig6 >/dev/null; then
  blur="$(kreadconfig6 --file kwinrc --group Plugins --key blurEnabled 2>/dev/null || true)"
  if [[ "$blur" == "false" ]]; then
    say "enabling the KWin Blur effect (was off)"
    kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
  fi
fi

# The look-and-feel carries cursorTheme, but plasma-apply-cursortheme also pokes the
# running session (and XWayland) instead of only writing kcminputrc.
if [[ -n "$CURSOR_FOUND" ]] && command -v plasma-apply-cursortheme >/dev/null; then
  say "applying cursor theme $CURSOR_THEME"
  plasma-apply-cursortheme "$CURSOR_THEME" 2>/dev/null \
    || warn "plasma-apply-cursortheme failed; kcminputrc is still set, a re-login will pick it up"
fi

lib_after="$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key library 2>/dev/null || true)"
thm_after="$(kreadconfig6 --file kwinrc --group "$KDECORATION_GROUP" --key theme 2>/dev/null || true)"
say "library id after:  $lib_after   theme: $thm_after"
case "$lib_after" in
  *aurorae*) ;;
  *) warn "kwinrc no longer names an Aurorae plugin - the decoration will not load" ;;
esac

say "reconfiguring kwin"
if command -v qdbus6 >/dev/null; then qdbus6 org.kde.KWin /KWin reconfigure
elif command -v qdbus >/dev/null; then qdbus org.kde.KWin /KWin reconfigure
else warn "qdbus not found - log out and back in to pick up the decoration"; fi

# Qt apps follow the Plasma colour scheme directly. GTK apps, and anything reading the
# XDG portal's org.freedesktop.appearance color-scheme - which includes Electron apps -
# do not. They keep whatever the last gtk.sh run set. Applying a Plasma theme without
# updating that leaves them one theme behind, which looks exactly like the light/dark
# preference being inverted when you alternate between the variants.
say "syncing the GTK / portal light-dark preference to $PORTAL_PREF"
if [[ -x "$QUANTUM_ROOT/bin/gtk.sh" && -d "$GTK_DEST" ]]; then
  "$QUANTUM_ROOT/bin/gtk.sh" --variant "$SLUG" 2>&1 | sed 's/^/    /' || warn "gtk.sh failed - preference may be stale"
else
  # No GTK theme installed; still set the preference so portal consumers follow.
  if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.interface color-scheme "$PORTAL_PREF" 2>/dev/null || true
  fi
  for g in gtk-3.0 gtk-4.0; do
    f="$CONF/$g/settings.ini"
    mkdir -p "$(dirname "$f")"
    [[ -f "$f" ]] || printf '[Settings]\n' > "$f"
    if grep -q '^gtk-application-prefer-dark-theme=' "$f"; then
      sed -i "s|^gtk-application-prefer-dark-theme=.*|gtk-application-prefer-dark-theme=$GTK_PREFER_DARK|" "$f"
    else
      sed -i "/^\[Settings\]/a gtk-application-prefer-dark-theme=$GTK_PREFER_DARK" "$f"
    fi
  done
  say "run bin/gtk.sh --variant $SLUG for the full GTK theme"
fi

say "restarting plasmashell to load the Plasma style"
if command -v kquitapp6 >/dev/null; then
  kquitapp6 plasmashell 2>/dev/null || true
  sleep "${QUANTUM_RESTART_DELAY:-2}"
  (setsid plasmashell >/dev/null 2>&1 &)
else
  warn "kquitapp6 not found - run 'plasmashell --replace &' yourself"
fi

cat <<'MSG'

Two things the theme cannot set for you:

  1. Panel opacity is a PER-PANEL setting in Plasma 6 and it overrides the style.
     Right-click the panel -> Enter Edit Mode -> More Options -> Opacity -> Translucent.
     Leave it on Adaptive and the panel goes opaque whenever a window is maximised.

  2. Translucency for APPLICATION windows (Dolphin, Kate) is not part of a Plasma
     style. That needs Kvantum as the widget style plus kwin-effects-forceblur.
     This theme deliberately does not go there - it would replace Breeze.

MSG
say "done. Verify with bin/verify.sh --variant $SLUG"
