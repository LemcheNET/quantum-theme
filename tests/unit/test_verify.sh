#!/usr/bin/env bash
# verify.sh is read-only, so what is testable is its verdicts. Two of them were wrong
# on a live host in ways that read as reassuring, which is the worst failure mode a
# checker has: it reported a true fact about the wrong variant, and it printed the
# widget style without checking it.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/harness.sh"
sandbox_up; trap sandbox_down EXIT

install_variant() { seed_icon_theme "$2"; run install.sh --variant "$1" --apply >/dev/null; }
fails_in() { printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g' | grep -c 'FAIL' || true; }

describe "a clean install verifies with no failures"
install_variant light Slot-Light-Icons
out="$(run verify.sh --variant light)"
assert_eq "no FAIL lines" 0 "$(fails_in "$out")"
assert_contains "the global theme is confirmed active" "$out" "QuantumLight is the active global theme"
assert_contains "the decoration frame colour is cross-checked" "$out" "decoration frame painted #eff0f1"
assert_contains "Header == Window is asserted" "$out" "[Colors:Header] == [Colors:Window]"
assert_contains "the widget style is asserted, not just printed" "$out" "widget style is Breeze"
assert_contains "the button order is asserted" "$out" "button order is M / IAX"
assert_contains "the translucent/ set is checked" "$out" "translucent/ set complete"
assert_contains "the Kickoff heading stacking is reported" "$out" "stacks to"
assert_contains "the installed tree is compared against the repo" "$out" "matches the repo"

describe "missing packages fail loudly"
sandbox_reset
out="$(run verify.sh --variant light)"
assert_contains "the decoration is reported missing" "$out" "aurorae/themes/QuantumLight missing"
assert_contains "the Plasma style is reported missing" "$out" "Plasma style missing"
assert_contains "the global theme is reported missing" "$out" "look-and-feel missing"

describe "a stale install is distinguished from a correct one"
sandbox_reset
install_variant light Slot-Light-Icons
echo '<!-- edited -->' >> "$XDG_DATA_HOME/plasma/desktoptheme/QuantumLight/plasmarc"
out="$(run verify.sh --variant light)"
assert_contains "the installed copy is reported as differing from the repo" "$out" "differs from the repo"
assert_contains "and the fix is named" "$out" "re-run install.sh"

describe "the widget style is a check, not a printed value"
# It was printed and never asserted, so Fusion on a host that declared Breeze passed
# an otherwise green run.
sandbox_reset
install_variant light Slot-Light-Icons
"$SANDBOX/bin/_kconfig" write "$XDG_CONFIG_HOME/kdeglobals" "[KDE]" widgetStyle Fusion
out="$(run verify.sh --variant light)"
assert_contains "a mismatched widget style is a FAIL" "$out" "widget style is 'Fusion'"
assert_contains "and the fix is given" "$out" "kwriteconfig6 --file kdeglobals"

describe "the colour verdict is scoped to the variant whose scheme is live"
# Verifying dark while light's scheme was live reported a cheerful
# 'ok [Colors:Header] == [Colors:Window] (239,240,241)' - a true statement about
# QuantumLight, printed under a dark heading.
sandbox_reset
install_variant light Slot-Light-Icons
install_variant dark Slot-Dark-Icons
"$SANDBOX/bin/_kconfig" write "$XDG_CONFIG_HOME/kdeglobals" "[General]" ColorScheme QuantumLight
out="$(run verify.sh --variant dark)"
assert_not_contains "no bare ok about another variant's scheme" "$out" "ok    [Colors:Header] =="
assert_contains "it names whose scheme is live" "$out" "live colour scheme is QuantumLight, not QuantumDark"
assert_contains "and says why it is skipping" "$out" "rather than this variant's"

describe "a sibling being the active theme is a note, not a failure"
sandbox_reset
install_variant dark Slot-Dark-Icons
install_variant light Slot-Light-Icons
out="$(run verify.sh --variant dark)"
assert_contains "it says which sibling is live" "$out" "QuantumLight is active, not QuantumDark"
assert_contains "and how to switch" "$out" "install.sh --variant dark --apply"

describe "the whichbg test card is shouted about"
# A forgotten test card is indistinguishable from a theme bug; it cost an evening once.
sandbox_reset
install_variant light Slot-Light-Icons
echo "painted by whichbg.sh" > "$XDG_DATA_HOME/plasma/desktoptheme/QuantumLight/.whichbg-active"
out="$(run verify.sh --variant light)"
assert_contains "the banner appears" "$out" "TEST CARD IS INSTALLED"
assert_contains "and names the restore command" "$out" "whichbg.sh --variant light --restore"

describe "a missing icon theme is a failure with the remedy"
sandbox_reset
run install.sh --variant light >/dev/null
out="$(run verify.sh --variant light)"
assert_contains "reported missing" "$out" "Slot-Light-Icons not installed"
assert_contains "with the fetch command" "$out" "icons.sh --variant light"

describe "the GTK and portal preference mismatch is caught"
sandbox_reset
install_variant dark Slot-Dark-Icons
# simulate having applied light afterwards, which leaves GTK one theme behind
"$SANDBOX/bin/_kconfig" write "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" "[Settings]" gtk-application-prefer-dark-theme 0
out="$(run verify.sh --variant dark)"
assert_contains "the stale preference is called out" "$out" "one theme behind"

describe "verify changes nothing"
sandbox_reset
install_variant light Slot-Light-Icons
before="$(find "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" -type f -exec md5sum {} + | sort | md5sum)"
run verify.sh --variant light >/dev/null
assert_eq "no file under HOME was modified" \
  "$before" "$(find "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" -type f -exec md5sum {} + | sort | md5sum)"

describe "a host without the base scheme does not abort the run"
# verify.sh referenced $want in the GTK section while setting it only inside the
# base-scheme branch, so under set -u it died on a host with no Breeze installed.
sandbox_reset
install_variant light Slot-Light-Icons
rm -f "$QUANTUM_SYSTEM_DATA/color-schemes/BreezeLight.colors"
out="$(run verify.sh --variant light)"
assert_contains "it reaches the end of the run" "$out" "kwin decoration errors"
assert_contains "and says it could not cross-check the colour" "$out" "cannot cross-check"

finish
