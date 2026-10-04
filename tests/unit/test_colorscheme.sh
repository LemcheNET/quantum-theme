#!/usr/bin/env bash
# colorscheme.sh closes the second seam: Breeze puts [Colors:Header] away from
# [Colors:Window], and Kirigami apps paint their toolbar with Header, so a retinted
# titlebar still meets a differently-coloured strip one row down.
#
# The fixture schemes in the harness carry the real Breeze values measured on quantum,
# so these assertions are about the actual colour arithmetic, not invented numbers.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/harness.sh"
sandbox_up; trap sandbox_down EXIT

group_value() {  # file, group, key
  awk -v g="[$2]" -v k="^$3=" '$0==g{f=1;next} /^\[/{f=0} f&&$0~k{sub(k,"");print;exit}' "$1"
}

describe "light: Header is pulled up to Window"
out="$(run colorscheme.sh --variant light)"
scheme="$XDG_DATA_HOME/color-schemes/QuantumLight.colors"
assert_eq "exits 0" 0 "$(status)"
assert_file "writes the derived scheme" "$scheme"
assert_eq "[Colors:Window] is Breeze Light's, untouched" \
  "239,240,241" "$(group_value "$scheme" "Colors:Window" BackgroundNormal)"
assert_eq "[Colors:Header] now equals Window (was 222,224,226)" \
  "239,240,241" "$(group_value "$scheme" "Colors:Header" BackgroundNormal)"
assert_eq "[WM] activeBackground equals Window (was 227,229,231)" \
  "239,240,241" "$(group_value "$scheme" WM activeBackground)"
assert_eq "the scheme is renamed" "Quantum Light" "$(group_value "$scheme" General Name)"
assert_eq "and self-identifies by id" "QuantumLight" "$(group_value "$scheme" General ColorScheme)"
assert_contains "it reports what it changed" "$out" "value(s) changed"

describe "dark: the same fix, opposite direction"
sandbox_reset
out="$(run colorscheme.sh --variant dark)"
scheme="$XDG_DATA_HOME/color-schemes/QuantumDark.colors"
assert_file "writes the derived scheme" "$scheme"
assert_eq "[Colors:Window] is Breeze Dark's" \
  "32,35,38" "$(group_value "$scheme" "Colors:Window" BackgroundNormal)"
assert_eq "[Colors:Header] pulled DOWN to Window (was 41,44,48 - lighter)" \
  "32,35,38" "$(group_value "$scheme" "Colors:Header" BackgroundNormal)"
assert_eq "[WM] activeBackground equals Window (was 39,44,49)" \
  "32,35,38" "$(group_value "$scheme" WM activeBackground)"
assert_eq "named for the dark variant" "Quantum Dark" "$(group_value "$scheme" General Name)"
# The forked packages both claimed "Breeze Light"; this is the assertion that would
# have caught that class of defect in the scheme itself.
assert_not_contains "no light values leaked into the dark scheme" "$(cat "$scheme")" "239,240,241"

describe "idempotent over its own output"
# The README's claim: a second pass over the result reports zero changes.
out="$(SRC_SCHEME="$scheme" run colorscheme.sh --variant dark)"
assert_contains "re-deriving from the output changes nothing" "$out" "0 value(s) changed"

describe "--diff writes nothing"
sandbox_reset
out="$(run colorscheme.sh --variant light --diff)"
assert_eq "exits 0" 0 "$(status)"
assert_no_file "no scheme written" "$XDG_DATA_HOME/color-schemes/QuantumLight.colors"
assert_contains "and says so" "$out" "nothing written"

describe "a missing base scheme is an error, not a silent empty scheme"
sandbox_reset
rm -f "$QUANTUM_SYSTEM_DATA/color-schemes/BreezeLight.colors"
out="$(run colorscheme.sh --variant light)"
assert_eq "exits non-zero" 1 "$(status)"
assert_contains "and names the missing file" "$out" "BreezeLight.colors"
assert_no_file "nothing written" "$XDG_DATA_HOME/color-schemes/QuantumLight.colors"

describe "it reads the installed scheme rather than hardcoding"
# The whole point: a Breeze update changes the numbers and this must follow.
sandbox_reset
sed -i 's/^BackgroundNormal=239,240,241/BackgroundNormal=200,201,202/' \
  "$QUANTUM_SYSTEM_DATA/color-schemes/BreezeLight.colors"
run colorscheme.sh --variant light >/dev/null
scheme="$XDG_DATA_HOME/color-schemes/QuantumLight.colors"
assert_eq "a changed Breeze Window value is picked up" \
  "200,201,202" "$(group_value "$scheme" "Colors:Window" BackgroundNormal)"
assert_eq "and Header follows it" \
  "200,201,202" "$(group_value "$scheme" "Colors:Header" BackgroundNormal)"

finish
