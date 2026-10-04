#!/usr/bin/env bash
# Run the unit suites. No Plasma, no root, no dependencies beyond bash and python3.
#
#   tests/run-unit-tests.sh                 every suite
#   tests/run-unit-tests.sh uninstall       only suites whose name matches
#   tests/run-unit-tests.sh --list          names only
#
# Each suite runs in its own sandbox: a throwaway $HOME with its own XDG directories, a
# fake /usr/share, stub KDE binaries that record every call, and a private copy of the
# repo - because retint.sh, opacity.sh and buttons.sh --base all edit the source tree by
# design. Nothing here touches the real session, so this is safe to run on a desktop
# that is using the theme.
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$ROOT" || exit 1

filter="${1:-}"
mapfile -t suites < <(find tests/unit -name 'test_*.sh' -type f | sort)

if [[ "$filter" == "--list" ]]; then
  for s in "${suites[@]}"; do basename "$s" | sed 's/^test_//; s/\.sh$//'; done
  exit 0
fi

[[ ${#suites[@]} -gt 0 ]] || { echo "no suites found under tests/unit" >&2; exit 1; }

ran=0; failed=0; checks=0; t0=$SECONDS
declare -a broken=()

for s in "${suites[@]}"; do
  name="$(basename "$s" | sed 's/^test_//; s/\.sh$//')"
  [[ -n "$filter" && "$name" != *"$filter"* ]] && continue
  ran=$((ran+1))
  printf '\033[1;36m══ %s\033[0m\n' "$name"
  out="$("$s" 2>&1)"; rc=$?
  printf '%s\n' "$out"
  # the summary line each suite prints, e.g. "test_x.sh: 23 checks passed"
  n="$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '[0-9]+ (of [0-9]+ )?checks' | grep -oE '[0-9]+' | tail -1)"
  checks=$((checks + ${n:-0}))
  [[ $rc -ne 0 ]] && { failed=$((failed+1)); broken+=("$name"); }
done

echo
printf '════════════════════════════════════════════\n'
printf '%d suite(s), %d checks, %ds\n' "$ran" "$checks" "$((SECONDS - t0))"
if [[ $failed -eq 0 ]]; then
  printf '\033[1;32mall unit suites passed\033[0m\n'
else
  printf '\033[1;31m%d suite(s) failed: %s\033[0m\n' "$failed" "${broken[*]}"
fi
exit $(( failed > 0 ))
