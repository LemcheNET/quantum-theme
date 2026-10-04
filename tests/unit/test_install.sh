#!/usr/bin/env bash
# install.sh copies three KPackages and, with --apply, rewrites appearance keys. The
# backup it writes first is the input to uninstall.sh, so the cases about what the
# backup may contain are as important as the ones about what gets installed.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/harness.sh"
sandbox_up; trap sandbox_down EXIT

bak() { cat "$XDG_STATE_HOME/quantum-$1/backup-latest.env" 2>/dev/null; }

describe "copy without applying"
seed_icon_theme Slot-Light-Icons
out="$(run install.sh --variant light)"
assert_eq "exits 0" 0 "$(status)"
assert_dir "Aurorae decoration installed"  "$XDG_DATA_HOME/aurorae/themes/QuantumLight"
assert_dir "Plasma style installed"        "$XDG_DATA_HOME/plasma/desktoptheme/QuantumLight"
assert_dir "global theme installed"        "$XDG_DATA_HOME/plasma/look-and-feel/QuantumLight"
assert_file "the rc travels with the decoration" "$XDG_DATA_HOME/aurorae/themes/QuantumLight/QuantumLightrc"
assert_file "contents/defaults travels with the global theme" "$XDG_DATA_HOME/plasma/look-and-feel/QuantumLight/contents/defaults"
assert_contains "it names each package kind, not the id three times" "$out" "installing the Aurorae decoration"
assert_contains "and the Plasma style" "$out" "installing the Plasma style"
assert_contains "and the global theme" "$out" "installing the global theme"
assert_not_called "nothing was applied" "plasma-apply-lookandfeel -a"
assert_eq "no backup written when nothing was changed" "" "$(bak light)"
assert_contains "it says how to apply" "$out" "--apply"

describe "copying is idempotent"
out="$(run install.sh --variant light)"
assert_eq "a second copy exits 0" 0 "$(status)"
assert_dir "packages still in place" "$XDG_DATA_HOME/aurorae/themes/QuantumLight"

describe "--apply refuses to run without the icon theme"
sandbox_reset
out="$(run install.sh --variant light --apply)"
assert_eq "exits non-zero" 1 "$(status)"
assert_contains "and names the missing dependency" "$out" "Slot-Light-Icons"
assert_contains "and the script that fetches it" "$out" "icons.sh"
assert_not_called "nothing was applied" "plasma-apply-lookandfeel -a"
# The refusal happens in the pre-checks, before anything is copied, so --apply is
# all-or-nothing rather than leaving a half-installed theme behind.
assert_no_dir "and nothing was copied either" "$XDG_DATA_HOME/plasma/look-and-feel/QuantumLight"

describe "--force-icons overrides that refusal"
sandbox_reset
out="$(run install.sh --variant light --apply --force-icons)"
assert_eq "exits 0" 0 "$(status)"
assert_called "the look-and-feel was applied" "plasma-apply-lookandfeel -a QuantumLight"

describe "a non-Plasma-6 host is refused outright"
sandbox_reset
seed_icon_theme Slot-Light-Icons
out="$(QUANTUM_TEST_PLASMA_VERSION=5.27.11 run install.sh --variant light --apply)"
assert_eq "exits non-zero" 1 "$(status)"
assert_contains "and says what it targets" "$out" "Plasma 6"
assert_no_dir "nothing was installed" "$XDG_DATA_HOME/plasma/look-and-feel/QuantumLight"

describe "--apply: the full sequence"
sandbox_reset
seed_icon_theme Slot-Light-Icons
out="$(run install.sh --variant light --apply)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "the global theme is live" "QuantumLight" "$(kcfg kdeglobals KDE LookAndFeelPackage)"
assert_eq "the derived colour scheme is live" "QuantumLight" "$(kcfg kdeglobals General ColorScheme)"
assert_file "and the scheme file exists" "$XDG_DATA_HOME/color-schemes/QuantumLight.colors"
assert_eq "the Plasma style is live" "QuantumLight" "$(kcfg plasmarc Theme name)"
assert_eq "the decoration theme is live" "__aurorae__svg__QuantumLight" "$(kcfg kwinrc org.kde.kdecoration2 theme)"
assert_eq "the Aurorae plugin is named" "org.kde.kwin.aurorae.v2" "$(kcfg kwinrc org.kde.kdecoration2 library)"
assert_eq "the icon theme is live" "Slot-Light-Icons" "$(kcfg kdeglobals Icons Theme)"
# Plasma 6.6 drops these two when applying a look-and-feel, so install.sh writes them.
assert_eq "button order written explicitly: left" "M" "$(kcfg kwinrc org.kde.kdecoration2 ButtonsOnLeft)"
assert_eq "button order written explicitly: right" "IAX" "$(kcfg kwinrc org.kde.kdecoration2 ButtonsOnRight)"
assert_called "the SVG cache was cleared via a plasmashell restart" "kquitapp6 plasmashell"
assert_called "kwin was reconfigured" "qdbus6 org.kde.KWin /KWin reconfigure"
assert_called "the cursor theme was applied explicitly" "plasma-apply-cursortheme breeze_cursors"

describe "--apply: the GTK and XDG-portal preference follows the variant"
# Electron and GTK apps read the portal, not the Plasma scheme. Getting this wrong is
# what makes the light/dark preference look inverted when you alternate variants.
assert_contains "light syncs to prefer-light" "$out" "prefer-light"
assert_eq "gtk-3.0 prefer-dark-theme=0" "0" "$(kcfg gtk-3.0/settings.ini Settings gtk-application-prefer-dark-theme)"
sandbox_reset
seed_icon_theme Slot-Dark-Icons
out="$(run install.sh --variant dark --apply)"
assert_contains "dark syncs to prefer-dark" "$out" "prefer-dark"
assert_eq "gtk-3.0 prefer-dark-theme=1" "1" "$(kcfg gtk-3.0/settings.ini Settings gtk-application-prefer-dark-theme)"
assert_eq "and the dark scheme is live" "QuantumDark" "$(kcfg kdeglobals General ColorScheme)"

describe "--apply writes a backup before changing anything"
sandbox_reset
seed_icon_theme Slot-Light-Icons
run install.sh --variant light --apply >/dev/null
b="$(bak light)"
assert_contains "records the previous global theme" "$b" "OLD_LNF=org.kde.breeze.desktop"
assert_contains "records the previous colour scheme" "$b" "OLD_COLORSCHEME=BreezeLight"
assert_contains "records the previous widget style" "$b" "OLD_WIDGETSTYLE=Breeze"
assert_contains "records the previous Plasma style" "$b" "OLD_PLASMATHEME=default"
assert_contains "records the previous icon theme" "$b" "OLD_ICONS=breeze"
assert_contains "records the previous cursor theme" "$b" "OLD_CURSOR=breeze_cursors"
assert_file "and a timestamped copy of kdeglobals beside it" \
  "$(find "$XDG_STATE_HOME/quantum-light" -name 'kdeglobals.*' | head -1)"

describe "the backup never names the variant being installed"
# Applying a variant that is already live used to record itself as the rollback target,
# so uninstall restored a theme it then deleted - KWin logged
# 'Could not find decoration svg for "QuantumLight"'. This is that regression test.
out="$(run install.sh --variant light --apply)"
b="$(bak light)"
assert_not_contains "OLD_LNF is not this variant" "$b" "OLD_LNF=QuantumLight"
assert_contains "it is the stock theme instead" "$b" "OLD_LNF=org.kde.breeze.desktop"
assert_not_contains "OLD_COLORSCHEME is not this variant" "$b" "OLD_COLORSCHEME=QuantumLight"
assert_not_contains "OLD_PLASMATHEME is not this variant" "$b" "OLD_PLASMATHEME=QuantumLight"
assert_not_contains "OLD_DECO_THEME is not this variant's" "$b" "OLD_DECO_THEME=__aurorae__svg__QuantumLight"
assert_contains "and the substitution is explained in the file" "$b" "must not record itself"

describe "unknown arguments are refused, not ignored"
sandbox_reset
seed_icon_theme Slot-Light-Icons
out="$(run install.sh --variant light --aply)"
assert_eq "a typo'd flag exits non-zero" 1 "$(status)"
assert_contains "and is named" "$out" "--aply"

finish
