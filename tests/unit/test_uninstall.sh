#!/usr/bin/env bash
# uninstall.sh is the script with the worst track record in this repo: the first live
# round trip found three defects in it, all in the backup replay. It now reverts to
# KDE's stock global theme by default, and every one of those defects has a case here.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/harness.sh"
sandbox_up; trap sandbox_down EXIT

install_variant() {  # slug, icon theme
  seed_icon_theme "$2"
  run install.sh --variant "$1" --apply >/dev/null
}

describe "the default reverts to stock, matched to the variant"
install_variant dark Slot-Dark-Icons
assert_eq "dark is live before we start" "QuantumDark" "$(kcfg kdeglobals KDE LookAndFeelPackage)"
out="$(run uninstall.sh --variant dark)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "a dark desktop comes back dark, not light" \
  "org.kde.breezedark.desktop" "$(kcfg kdeglobals KDE LookAndFeelPackage)"
assert_contains "and it says which theme it chose" "$out" "org.kde.breezedark.desktop"
assert_eq "the stock colour scheme came with it" "BreezeDark" "$(kcfg kdeglobals General ColorScheme)"
assert_eq "the stock Plasma style came with it" "default" "$(kcfg plasmarc Theme name)"
assert_eq "the stock decoration came with it" "Breeze" "$(kcfg kwinrc org.kde.kdecoration2 theme)"

describe "light reverts to the light stock theme"
sandbox_reset
install_variant light Slot-Light-Icons
run uninstall.sh --variant light >/dev/null
assert_eq "light goes to org.kde.breeze.desktop" \
  "org.kde.breeze.desktop" "$(kcfg kdeglobals KDE LookAndFeelPackage)"

describe "the packages are removed, the icon theme is not"
sandbox_reset
install_variant dark Slot-Dark-Icons
out="$(run uninstall.sh --variant dark)"
assert_no_dir "decoration removed"  "$XDG_DATA_HOME/aurorae/themes/QuantumDark"
assert_no_dir "Plasma style removed" "$XDG_DATA_HOME/plasma/desktoptheme/QuantumDark"
assert_no_dir "global theme removed" "$XDG_DATA_HOME/plasma/look-and-feel/QuantumDark"
assert_no_file "the derived colour scheme file removed" "$XDG_DATA_HOME/color-schemes/QuantumDark.colors"
assert_dir "the icon theme is left alone - it is 215 MiB and a dependency" "$XDG_DATA_HOME/icons/Slot-Dark-Icons"
assert_contains "and it says so" "$out" "left in place"
assert_contains "it points at the saved settings as the real escape hatch" "$out" "timestamped copies"

describe "the sibling variant is untouched"
sandbox_reset
install_variant light Slot-Light-Icons
install_variant dark Slot-Dark-Icons
run uninstall.sh --variant dark >/dev/null
assert_no_dir "dark's packages are gone" "$XDG_DATA_HOME/plasma/look-and-feel/QuantumDark"
assert_dir "light's are still there" "$XDG_DATA_HOME/plasma/look-and-feel/QuantumLight"
assert_dir "and its decoration" "$XDG_DATA_HOME/aurorae/themes/QuantumLight"
assert_file "and its colour scheme" "$XDG_DATA_HOME/color-schemes/QuantumLight.colors"

describe "no dangling global theme - the defect KWin logged"
# Applying a variant twice used to record it as its own rollback target, so uninstall
# restored QuantumDark and then deleted it: 'aurorae: Could not find decoration svg'.
sandbox_reset
install_variant dark Slot-Dark-Icons
install_variant dark Slot-Dark-Icons      # apply again, over itself
run uninstall.sh --variant dark >/dev/null
live="$(kcfg kdeglobals KDE LookAndFeelPackage)"
assert_not_contains "the live global theme is not the deleted one" "$live" "QuantumDark"
assert_eq "it is stock" "org.kde.breezedark.desktop" "$live"
assert_not_contains "and no key still names the deleted decoration" \
  "$(kcfg kwinrc org.kde.kdecoration2 theme)" "QuantumDark"
assert_not_contains "nor the deleted colour scheme" \
  "$(kcfg kdeglobals General ColorScheme)" "QuantumDark"

describe "falling back when the matched stock theme is absent"
# A host can be missing the dark Breeze package. Resolution is against what is there,
# not against an id Plasma has renamed before.
sandbox_reset
install_variant dark Slot-Dark-Icons
rm -rf "$QUANTUM_SYSTEM_DATA/plasma/look-and-feel/org.kde.breezedark.desktop"
out="$(run uninstall.sh --variant dark)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "falls back to the universal stock theme" \
  "org.kde.breeze.desktop" "$(kcfg kdeglobals KDE LookAndFeelPackage)"

describe "no stock theme at all is an error, not a silent half-uninstall"
sandbox_reset
install_variant dark Slot-Dark-Icons
rm -rf "$QUANTUM_SYSTEM_DATA/plasma/look-and-feel"
out="$(run uninstall.sh --variant dark)"
assert_eq "exits non-zero" 1 "$(status)"
assert_contains "and says what is missing" "$out" "stock Breeze"
assert_dir "the packages are still there, so nothing is half-done" \
  "$XDG_DATA_HOME/plasma/look-and-feel/QuantumDark"

describe "--restore-backup replays the recorded keys"
sandbox_reset
# start from a non-stock state so there is something distinctive to come back to
"$SANDBOX/bin/_kconfig" write "$XDG_CONFIG_HOME/kdeglobals" "[KDE]" widgetStyle Oxygen
"$SANDBOX/bin/_kconfig" write "$XDG_CONFIG_HOME/kdeglobals" "[Icons]" Theme breeze
install_variant light Slot-Light-Icons
out="$(run uninstall.sh --variant light --restore-backup)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "the recorded widget style is restored" "Oxygen" "$(kcfg kdeglobals KDE widgetStyle)"
assert_eq "the recorded icon theme is restored" "breeze" "$(kcfg kdeglobals Icons Theme)"
assert_contains "and it warns that the replay is best-effort" "$out" "best-effort"

describe "--restore-backup still refuses a backup naming this variant"
sandbox_reset
install_variant light Slot-Light-Icons
# forge the failure mode the guard exists for
sed -i 's/^OLD_LNF=.*/OLD_LNF=QuantumLight/' "$XDG_STATE_HOME/quantum-light/backup-latest.env"
out="$(run uninstall.sh --variant light --restore-backup)"
assert_eq "exits 0" 0 "$(status)"
assert_not_contains "it did not restore the theme it was deleting" \
  "$(kcfg kdeglobals KDE LookAndFeelPackage)" "QuantumLight"
assert_contains "and said why" "$out" "is this variant or is gone"

describe "--restore-backup with a recorded theme since removed"
sandbox_reset
install_variant light Slot-Light-Icons
sed -i 's/^OLD_LNF=.*/OLD_LNF=org.kde.somethingelse.desktop/' "$XDG_STATE_HOME/quantum-light/backup-latest.env"
out="$(run uninstall.sh --variant light --restore-backup)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "falls back to stock" "org.kde.breeze.desktop" "$(kcfg kdeglobals KDE LookAndFeelPackage)"

describe "--restore-backup with no backup is an error, and names the alternative"
sandbox_reset
run install.sh --variant light >/dev/null          # copy only: no --apply, no backup
out="$(run uninstall.sh --variant light --restore-backup)"
assert_eq "exits non-zero" 1 "$(status)"
assert_contains "and points at the stock path instead" "$out" "revert to stock"

describe "uninstalling something never installed is survivable"
sandbox_reset
out="$(run uninstall.sh --variant light)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "and leaves the host on stock" "org.kde.breeze.desktop" "$(kcfg kdeglobals KDE LookAndFeelPackage)"

describe "the round trip, twice, leaves no residue"
sandbox_reset
for _ in 1 2; do
  install_variant light Slot-Light-Icons
  run uninstall.sh --variant light >/dev/null
done
assert_no_dir "no decoration left" "$XDG_DATA_HOME/aurorae/themes/QuantumLight"
assert_no_dir "no Plasma style left" "$XDG_DATA_HOME/plasma/desktoptheme/QuantumLight"
assert_no_dir "no global theme left" "$XDG_DATA_HOME/plasma/look-and-feel/QuantumLight"
assert_no_file "no colour scheme left" "$XDG_DATA_HOME/color-schemes/QuantumLight.colors"
assert_eq "and the host is on stock" "org.kde.breeze.desktop" "$(kcfg kdeglobals KDE LookAndFeelPackage)"

finish
