#!/usr/bin/env bash
# retint.sh recolours the decoration frame to match the colour scheme's window
# background. It edits the SOURCE tree, so every case here runs against the sandboxed
# copy of the repo.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/harness.sh"
sandbox_up; trap sandbox_down EXIT

deco() { printf '%s\n' "$QUANTUM_ROOT/variants/$1/aurorae/$2/decoration.svg"; }
count_hex() { grep -o "$2" "$1" | wc -l | tr -d ' '; }

describe "matching the installed base scheme"
d="$(deco light QuantumLight)"
# start from upstream Moe's colour so there is something to change
sed -i 's/#eff0f1/#f7f9f9/g' "$d"
assert_eq "fixture starts as upstream Moe" 16 "$(count_hex "$d" '#f7f9f9')"
out="$(run retint.sh --variant light)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "all 16 occurrences become Breeze Light's window colour" 16 "$(count_hex "$d" '#eff0f1')"
assert_eq "none of upstream's colour survives" 0 "$(count_hex "$d" '#f7f9f9')"
assert_contains "it names the target it derived" "$out" "#eff0f1"

describe "idempotent"
out="$(run retint.sh --variant light)"
assert_contains "a second run is a no-op" "$out" "no change"
assert_eq "still 16 occurrences, not 32" 16 "$(count_hex "$d" '#eff0f1')"

describe "dark derives a different target from the same code"
d="$(deco dark QuantumDark)"
sed -i 's/#202326/#f7f9f9/g' "$d"
run retint.sh --variant dark >/dev/null
assert_eq "dark gets Breeze Dark's window colour" 16 "$(count_hex "$d" '#202326')"
assert_eq "and not the light one" 0 "$(count_hex "$d" '#eff0f1')"

describe "an explicit colour overrides the scheme"
sandbox_reset
d="$(deco light QuantumLight)"
run retint.sh --variant light '#31363b' >/dev/null
assert_eq "the given colour is used" 16 "$(count_hex "$d" '#31363b')"

describe "--from reads a different scheme file"
sandbox_reset
d="$(deco light QuantumLight)"
run retint.sh --variant light --from "$QUANTUM_SYSTEM_DATA/color-schemes/BreezeDark.colors" >/dev/null
assert_eq "light's artwork retinted to the dark scheme's window colour" 16 "$(count_hex "$d" '#202326')"

describe "bad input is refused rather than written"
sandbox_reset
d="$(deco light QuantumLight)"
before="$(md5sum "$d" | cut -d' ' -f1)"
for bad in 'eff0f1' '#eff0f' '#gggggg' 'blue'; do
  out="$(run retint.sh --variant light "$bad")"
  assert_eq "'$bad' is rejected" 1 "$(status)"
done
assert_eq "the artwork is untouched after every rejection" "$before" "$(md5sum "$d" | cut -d' ' -f1)"

describe "a missing decoration is an error"
sandbox_reset
rm -f "$(deco light QuantumLight)"
out="$(run retint.sh --variant light)"
assert_eq "exits non-zero" 1 "$(status)"
assert_contains "and says what is missing" "$out" "decoration.svg"

finish
