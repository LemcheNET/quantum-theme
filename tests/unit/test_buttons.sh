#!/usr/bin/env bash
# buttons.sh is the script the merge changed most: the forked version reached into
# ../quantum-dark/ by relative path, and the consolidated one enumerates variants. Its
# pixel arithmetic comes from Aurorae's own source and is documented as a table in the
# README, so the table is the fixture.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/harness.sh"
sandbox_up; trap sandbox_down EXIT

rc() { printf '%s\n' "$QUANTUM_ROOT/variants/$1/aurorae/$2/${2}rc"; }
rcval() { awk -F= -v k="$2" '$1==k{gsub(/ /,"",$2);print $2;exit}' "$1"; }

describe "reporting needs no --variant, because it covers all of them"
out="$(run buttons.sh)"
assert_eq "exits 0" 0 "$(status)"
assert_contains "reports the light variant" "$out" "QuantumLight"
assert_contains "reports the dark variant" "$out" "QuantumDark"
assert_contains "prints the per-theme ButtonSize knob" "$out" "ButtonSize"
assert_contains "and the resulting titlebar height" "$out" "titlebar"

describe "the documented pixel table"
# From the README, at a base of 12 and 96 dpi: index 1 (normal) is 1.0x -> 12px button,
# index 6 (oversized) is 2.0x -> 24px. The harness's xdpyinfo stub reports 96 dpi.
for v in light dark; do
  id=QuantumLight; [[ $v == dark ]] && id=QuantumDark
  sed -i 's/^ButtonWidth=.*/ButtonWidth=12/; s/^ButtonHeight=.*/ButtonHeight=12/' "$(rc "$v" "$id")"
done
out="$(run buttons.sh normal)"
assert_contains "normal is factor 1.0" "$out" "1.0"
out="$(run buttons.sh oversized)"
assert_contains "oversized is factor 2.0" "$out" "2.0"
assert_eq "ButtonSize written for light" "6" "$(kcfg auroraerc QuantumLight ButtonSize)"
assert_eq "ButtonSize written for dark" "6" "$(kcfg auroraerc QuantumDark ButtonSize)"

describe "a size is applied to EVERY variant by default"
# Aurorae keys button size per theme, so touching one variant silently diverges them.
# This is the behaviour the forked packages could not express without a relative path
# into each other.
sandbox_reset
run buttons.sh large >/dev/null
assert_eq "light got index 2" "2" "$(kcfg auroraerc QuantumLight ButtonSize)"
assert_eq "dark got index 2" "2" "$(kcfg auroraerc QuantumDark ButtonSize)"

describe "by index as well as by name"
sandbox_reset
run buttons.sh 4 >/dev/null
assert_eq "index 4 accepted" "4" "$(kcfg auroraerc QuantumLight ButtonSize)"

describe "--only restricts to one variant, by slug or by id"
sandbox_reset
run buttons.sh 3 --only dark >/dev/null
assert_eq "dark set" "3" "$(kcfg auroraerc QuantumDark ButtonSize)"
assert_eq "light untouched" "" "$(kcfg auroraerc QuantumLight ButtonSize)"
sandbox_reset
run buttons.sh 3 --only QuantumLight >/dev/null
assert_eq "the package id is accepted too" "3" "$(kcfg auroraerc QuantumLight ButtonSize)"
assert_eq "and dark is untouched" "" "$(kcfg auroraerc QuantumDark ButtonSize)"

describe "--base edits the theme's own rc, on every variant"
sandbox_reset
out="$(run buttons.sh --base 16)"
assert_eq "light rc base" "16" "$(rcval "$(rc light QuantumLight)" ButtonWidth)"
assert_eq "light rc height" "16" "$(rcval "$(rc light QuantumLight)" ButtonHeight)"
assert_eq "dark rc base" "16" "$(rcval "$(rc dark QuantumDark)" ButtonWidth)"
assert_contains "it warns that the rc is read once per KWin process" "$out" "KWin restarts"
assert_contains "and says how to restart" "$out" "kwin_x11 --replace"

describe "--base out of range is refused"
sandbox_reset
for bad in 2 65 abc; do
  out="$(run buttons.sh --base $bad)"
  assert_eq "--base $bad rejected" 1 "$(status)"
done
assert_eq "no rc was edited" "22" "$(rcval "$(rc light QuantumLight)" ButtonWidth)"

describe "--sync copies one variant's base onto the others"
sandbox_reset
sed -i 's/^ButtonWidth=.*/ButtonWidth=18/; s/^ButtonHeight=.*/ButtonHeight=18/' "$(rc light QuantumLight)"
out="$(run buttons.sh --variant light --sync)"
assert_eq "exits 0" 0 "$(status)"
assert_eq "dark now matches light" "18" "$(rcval "$(rc dark QuantumDark)" ButtonWidth)"

describe "--sync without a source variant is refused"
sandbox_reset
out="$(run buttons.sh --sync)"
assert_eq "exits non-zero" 1 "$(status)"
assert_contains "and says it needs a source" "$out" "--sync needs a source"

describe "drift between variants is reported"
sandbox_reset
sed -i 's/^ButtonWidth=.*/ButtonWidth=32/' "$(rc light QuantumLight)"
out="$(run buttons.sh)"
assert_contains "differing base sizes are flagged" "$out" "different base sizes"
assert_contains "and the fix is named" "$out" "--sync"

describe "an unknown size name is refused"
sandbox_reset
out="$(run buttons.sh enormous)"
assert_eq "exits non-zero" 1 "$(status)"
assert_contains "and lists the valid steps" "$out" "oversized"

finish
