#!/usr/bin/env bash
# The merge replaced two forked packages with one codebase plus a variant selector.
# If that selector is wrong, every script operates on the wrong theme - so it is the
# first thing worth testing.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/harness.sh"
sandbox_up; trap sandbox_down EXIT

# opacity.sh with no arguments is read-only and names the variant it resolved, which
# makes it the cheapest probe for the selector.
probe() { run opacity.sh "$@"; }

describe "explicit --variant"
out="$(probe --variant light)"
assert_contains "--variant light resolves Quantum Light" "$out" "Quantum Light"
out="$(probe --variant dark)"
assert_contains "--variant dark resolves Quantum Dark" "$out" "Quantum Dark"
out="$(probe --variant=dark)"
assert_contains "--variant=dark (equals form) also works" "$out" "Quantum Dark"
out="$(probe -v light)"
assert_contains "-v is accepted as a short form" "$out" "Quantum Light"

describe "QUANTUM_VARIANT from the environment"
out="$(QUANTUM_VARIANT=dark probe)"
assert_contains "the environment resolves the variant" "$out" "Quantum Dark"
out="$(QUANTUM_VARIANT=dark probe --variant light)"
assert_contains "an explicit flag beats the environment" "$out" "Quantum Light"

describe "inferred from the per-variant symlink path"
# variants/<slug>/opacity.sh -> ../../bin/opacity.sh, so the invocation path carries
# the variant. This is what preserves the pre-merge muscle memory.
out="$(cd "$QUANTUM_ROOT/variants/dark" && ./opacity.sh 2>&1)"
assert_contains "variants/dark/opacity.sh infers dark" "$out" "Quantum Dark"
out="$(cd "$QUANTUM_ROOT/variants/light" && ./opacity.sh 2>&1)"
assert_contains "variants/light/opacity.sh infers light" "$out" "Quantum Light"
out="$("$QUANTUM_ROOT/variants/dark/opacity.sh" 2>&1)"
assert_contains "the symlink works by absolute path too" "$out" "Quantum Dark"

describe "refusing to guess"
out="$(probe)"; st="$(status)"
assert_eq "no variant and no hint exits non-zero" 1 "$st"
assert_contains "and says how to supply one" "$out" "--variant"
assert_contains "and lists what is available" "$out" "dark|light"

out="$(probe --variant medium)"; st="$(status)"
assert_eq "an unknown variant exits non-zero" 1 "$st"
assert_contains "and names what it does have" "$out" "dark light"

describe "a variant missing a required key is rejected, not half-loaded"
# Guards against someone adding a variant and forgetting a key: the scripts would
# otherwise run with an empty ID and operate on paths like ~/.local/share/aurorae/themes/
broken="$QUANTUM_ROOT/variants/broken"
mkdir -p "$broken"
printf 'SLUG=broken\nID=Broken\n' > "$broken/variant.env"
out="$(probe --variant broken)"; st="$(status)"
rm -rf "$broken"
assert_eq "an incomplete variant.env exits non-zero" 1 "$st"
assert_contains "and names the first missing key" "$out" "does not define"

describe "a variant.env whose SLUG disagrees with its directory"
odd="$QUANTUM_ROOT/variants/odd"
mkdir -p "$odd"
sed 's/^SLUG=light/SLUG=somethingelse/' "$QUANTUM_ROOT/variants/light/variant.env" > "$odd/variant.env"
out="$(probe --variant odd)"; st="$(status)"
rm -rf "$odd"
assert_eq "a mismatched SLUG exits non-zero" 1 "$st"
assert_contains "and says which file is wrong" "$out" "variant.env says SLUG="

describe "library lookups"
# quantum_variant_get reads another variant's facts without disturbing the current one -
# buttons.sh depends on this to report every variant from one invocation.
out="$(
  export QUANTUM_VARIANT=light
  cd "$QUANTUM_ROOT" || exit 1
  # shellcheck source=/dev/null
  . lib/common.sh
  quantum_init
  printf '%s|%s|%s|%s\n' "$ID" "$(quantum_variant_get dark ID)" "$(quantum_variant_get dark STOCK_LNF)" "$ID"
)"
assert_eq "reading a sibling's keys leaves the current variant intact" \
  "QuantumLight|QuantumDark|org.kde.breezedark.desktop|QuantumLight" "$out"

out="$(cd "$QUANTUM_ROOT" && . lib/common.sh && quantum_variants | paste -sd, -)"
assert_eq "quantum_variants lists both, in directory order" "dark,light" "$out"

out="$(cd "$QUANTUM_ROOT" && . lib/common.sh && quantum_is_variant light && echo yes || echo no)"
assert_eq "quantum_is_variant accepts a real slug" "yes" "$out"
out="$(cd "$QUANTUM_ROOT" && . lib/common.sh && quantum_is_variant nope && echo yes || echo no)"
assert_eq "quantum_is_variant rejects an unknown slug" "no" "$out"

finish
