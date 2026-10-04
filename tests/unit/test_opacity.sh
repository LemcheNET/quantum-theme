#!/usr/bin/env bash
# opacity.sh retunes five SVGs and reports the STACKED Kickoff figure, because the
# heading is painted on top of the dialog background and the two compound. Getting that
# arithmetic wrong is how a launcher ends up visually solid at a nominal 75%.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/harness.sh"
sandbox_up; trap sandbox_down EXIT

style() { printf '%s\n' "$QUANTUM_ROOT/variants/$1/plasma/desktoptheme/$2"; }
op() {  # svg path -> its first painting opacity
  grep -o 'opacity="[0-9.]*"' "$1" | grep -v 'opacity="0"' | head -1 | cut -d'"' -f2
}

describe "reporting without arguments changes nothing"
t="$(style light QuantumLight)"
before="$(find "$t" -name '*.svg' -exec md5sum {} + | sort | md5sum)"
out="$(run opacity.sh --variant light)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "no file touched" "$before" "$(find "$t" -name '*.svg' -exec md5sum {} + | sort | md5sum)"
assert_contains "names the variant" "$out" "Quantum Light"
assert_contains "reports the shipped panel value" "$out" "0.65"
assert_contains "reports the shipped popup value" "$out" "0.75"
assert_contains "reports the shipped heading tint" "$out" "0.03"

describe "setting panel and popup values"
out="$(run opacity.sh --variant light 50 60)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "panel background rewritten" "0.50" "$(op "$t/widgets/panel-background.svg")"
assert_eq "dialog background rewritten" "0.60" "$(op "$t/dialogs/background.svg")"
assert_eq "widget background rewritten" "0.60" "$(op "$t/widgets/background.svg")"
assert_eq "tooltip rewritten" "0.60" "$(op "$t/widgets/tooltip.svg")"

describe "the translucent/ copies are retuned too"
# Plasma resolves these four through a 'translucent' selector whenever KWin's blur is
# active - the normal state. A theme that retunes only the top level loses them to
# Breeze while looking correct on disk.
assert_eq "translucent panel matches" "0.50" "$(op "$t/translucent/widgets/panel-background.svg")"
assert_eq "translucent dialog matches" "0.60" "$(op "$t/translucent/dialogs/background.svg")"
assert_eq "translucent widget matches" "0.60" "$(op "$t/translucent/widgets/background.svg")"
assert_eq "translucent tooltip matches" "0.60" "$(op "$t/translucent/widgets/tooltip.svg")"

describe "the heading is a tint, not a third surface"
sandbox_reset
t="$(style light QuantumLight)"
out="$(run opacity.sh --variant light 65 75 3)"
assert_eq "heading set to the tint value, not the popup value" "0.03" "$(op "$t/widgets/plasmoidheading.svg")"
# 1 - (1 - 0.75)(1 - 0.03) = 0.7575 -> 75.8%
assert_contains "the stacked figure is reported, not the nominal one" "$out" "75.8%"
assert_contains "and labelled as what Kickoff will be" "$out" "over the popup"

describe "the obvious mistake is warned about"
sandbox_reset
out="$(run opacity.sh --variant light 65 75 75)"
# 1 - (1 - 0.75)(1 - 0.75) = 0.9375 -> 93.8%, which reads as solid
assert_contains "a heading at the popup value stacks to 93.8%" "$out" "93.8%"
assert_contains "and is called out" "$out" "Kickoff gets banded"

describe "legibility and range guards"
sandbox_reset
out="$(run opacity.sh --variant light 30 35)"
assert_contains "below ~40% warns about legibility" "$out" "legibility"
for bad in "101 50" "50 101" "-1 50" "abc 50"; do
  # shellcheck disable=SC2086
  out="$(run opacity.sh --variant light $bad)"
  assert_eq "'$bad' is rejected" 1 "$(status)"
done

describe "each variant is retuned independently"
sandbox_reset
run opacity.sh --variant dark 40 45 >/dev/null
assert_eq "dark panel changed" "0.40" "$(op "$(style dark QuantumDark)/widgets/panel-background.svg")"
assert_eq "light panel untouched" "0.65" "$(op "$(style light QuantumLight)/widgets/panel-background.svg")"

finish
