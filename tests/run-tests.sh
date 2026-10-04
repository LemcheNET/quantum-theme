#!/usr/bin/env bash
# Offline checks. No Plasma session needed, nothing installed, nothing changed.
#
#   tests/run-tests.sh                 static gates, then the unit suites
#   tests/run-tests.sh --static-only   just the gates below
#
# The unit suites live in tests/unit/ and are run by tests/run-unit-tests.sh. This file
# is the static half: lint, shape, licensing and generated-file freshness - the things
# that need no sandbox because they only read the repo.
#
# These are the gates that stop the drift this repo was created to end. The two
# variants were forked before, and every failure below is something that went wrong
# once: a palette literal left in shared code, a description still naming the other
# variant, a version that disagreed with its siblings, a C2PA manifest stamped into
# GPL'd artwork on its way through a file bridge.
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$ROOT" || { echo "cannot cd to $ROOT" >&2; exit 1; }

fails=0
pass() { printf '  \033[1;32mok\033[0m    %s\n' "$*"; }
fail() { printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; fails=$((fails+1)); }
head_() { printf '\033[1m%s\033[0m\n' "$*"; }

mapfile -t SCRIPTS < <(find bin lib tests -name '*.sh' -type f | sort; ls ./*.sh 2>/dev/null)
mapfile -t VARIANTS < <(find variants -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

head_ "shell syntax"
for s in "${SCRIPTS[@]}"; do
  bash -n "$s" 2>/dev/null && pass "$s" || fail "$s does not parse"
done

head_ "shellcheck"
if command -v shellcheck >/dev/null; then
  for s in "${SCRIPTS[@]}"; do
    shellcheck -x -S warning "$s" >/dev/null 2>&1 && pass "$s" || { fail "$s"; shellcheck -x -S warning "$s" | sed 's/^/        /'; }
  done
else
  echo "  --    shellcheck not installed; skipped (apt install shellcheck)"
fi

head_ "no variant literals in shared code"
# The whole point of lib/ + bin/ is that a variant's name, palette source, icon theme
# and portal preference appear only in variants/<slug>/variant.env. Hex colours are
# exempt: retint.sh carries the set of frame colours the artwork has ever had, which
# has to span both variants so you can retint in either direction.
# 'prefer-dark' is matched only standalone: gtk-application-prefer-dark-theme is a
# GTK key name, not this variant's portal value. Whole-line comments are allowed to
# use a variant as an example.
LITERALS='QuantumLight|QuantumDark|Slot-Light-Icons|Slot-Dark-Icons|BreezeLight|BreezeDark|quantum-light|quantum-dark|[^-]prefer-(light|dark)[^-]'
hits=$(grep -nE "$LITERALS" bin/*.sh lib/*.sh ./*.sh 2>/dev/null \
       | grep -vE ':[0-9]+:[[:space:]]*#' || true)
if [[ -z "$hits" ]]; then
  pass "bin/, lib/ and the root wrappers are variant-neutral"
else
  fail "variant literals in shared code:"; echo "$hits" | sed 's/^/        /'
fi

head_ "variant definitions"
REQUIRED=(SLUG ID NAME BASE_SCHEME ICON_THEME ICON_SUBDIR CURSOR_THEME PORTAL_PREF GTK_PREFER_DARK STOCK_LNF)
for v in "${VARIANTS[@]}"; do
  env="variants/$v/variant.env"
  [[ -f "$env" ]] || { fail "$env missing"; continue; }
  miss=()
  for k in "${REQUIRED[@]}"; do grep -q "^$k=" "$env" || miss+=("$k"); done
  [[ ${#miss[@]} -eq 0 ]] && pass "$env defines all ${#REQUIRED[@]} keys" || fail "$env missing: ${miss[*]}"
  slug=$(grep -m1 '^SLUG=' "$env" | cut -d= -f2)
  [[ "$slug" == "$v" ]] && pass "$env SLUG matches its directory" || fail "$env says SLUG=$slug but lives in variants/$v"
done

head_ "generated files are current"
if python3 packaging/stamp-metadata.py --check >/dev/null 2>&1; then
  pass "metadata.json, metadata.desktop and contents/defaults match VERSION + variant.env"
else
  fail "generated files are stale - run packaging/stamp-metadata.py"
  python3 packaging/stamp-metadata.py --check 2>&1 | sed 's/^/        /'
fi

head_ "version agreement"
VER="$(cat VERSION)"
bad_ver=$(grep -rh '"Version"' variants/*/*/*/metadata.json variants/*/plasma/desktoptheme/*/metadata.json 2>/dev/null \
          | grep -v "\"$VER\"" || true)
[[ -z "$bad_ver" ]] && pass "every package reports $VER" || { fail "a package disagrees with VERSION=$VER:"; echo "$bad_ver" | sed 's/^/        /'; }

head_ "the store product sheet agrees with the build"
# packaging/kde-store-products.md names the tarballs and categories by hand. The whole
# point of this repo is that nothing is typed twice without a check, so the sheet is
# gated against what make-release.sh actually emits.
SHEET=packaging/kde-store-products.md
if [[ -f "$SHEET" ]]; then
  sheet_names=$(grep -oE 'Quantum(Light|Dark)-[a-z]+-[0-9.]+\.tar\.gz' "$SHEET" | sort -u)
  build_names=$(./packaging/make-release.sh --list | grep -oE 'Quantum(Light|Dark)-[a-z]+-[0-9.]+\.tar\.gz' | sort -u)
  if [[ "$sheet_names" == "$build_names" ]]; then
    pass "every tarball the sheet names is one the build produces"
  else
    fail "the sheet and the build disagree about filenames:"
    diff <(echo "$build_names") <(echo "$sheet_names") | sed 's/^/        /'
  fi
  stale=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$SHEET" | sort -u | grep -v "^$VER$" || true)
  [[ -z "$stale" ]] && pass "the sheet quotes no version other than $VER" \
                    || { fail "the sheet quotes a stale version:"; echo "$stale" | sed 's/^/        /'; }
  for c in 'Global Themes (Plasma 6)' 'Plasma 6 Window Decorations' 'Plasma 6 Themes'; do
    grep -qF "$c" "$SHEET" && pass "names the $c category" || fail "the sheet is missing the $c category"
  done
else
  fail "$SHEET missing - the store upload has no definition"
fi

head_ "variant tree parity"
# The forked packages lost files from one side without anyone noticing. Compare the
# relative shape of each tree, with the id substituted out.
ref="${VARIANTS[0]}"
ref_id=$(grep -m1 '^ID=' "variants/$ref/variant.env" | cut -d= -f2)
shape() {  # slug, id
  find "variants/$1" -mindepth 1 \( -type f -o -type l \) -printf '%P\n' \
    | sed "s/$2/<ID>/g" | grep -v '^variant\.env$' | sort
}
for v in "${VARIANTS[@]:1}"; do
  id=$(grep -m1 '^ID=' "variants/$v/variant.env" | cut -d= -f2)
  if diff <(shape "$ref" "$ref_id") <(shape "$v" "$id") >/dev/null; then
    pass "variants/$v has the same file set as variants/$ref"
  else
    fail "variants/$v differs in shape from variants/$ref:"
    diff <(shape "$ref" "$ref_id") <(shape "$v" "$id") | sed 's/^/        /'
  fi
done

head_ "per-variant entry points resolve"
for v in "${VARIANTS[@]}"; do
  broken=()
  while read -r l; do [[ -e "$l" ]] || broken+=("$l"); done < <(find "variants/$v" -maxdepth 1 -type l)
  [[ ${#broken[@]} -eq 0 ]] && pass "variants/$v symlinks resolve" || fail "dangling: ${broken[*]}"
done

head_ "artwork is retinted, not upstream"
# #f7f9f9 is upstream Moe's frame colour. If it survives, retint.sh has not run and the
# titlebar will be a near-white frame around the window body.
for v in "${VARIANTS[@]}"; do
  id=$(grep -m1 '^ID=' "variants/$v/variant.env" | cut -d= -f2)
  d="variants/$v/aurorae/$id/decoration.svg"
  [[ -f "$d" ]] || { fail "$d missing"; continue; }
  grep -qi '#f7f9f9' "$d" && fail "$d still carries upstream Moe's #f7f9f9 - run bin/retint.sh --variant $v" \
                          || pass "$d is retinted"
done

head_ "no C2PA manifests in artwork"
# Copying images through a file bridge can stamp a provenance manifest into every SVG
# and PNG. On GPL'd artwork that is both bloat and a false statement about authorship.
c2pa=$(grep -rl c2pa variants/*/aurorae variants/*/plasma 2>/dev/null || true)
[[ -z "$c2pa" ]] && pass "decoration and Plasma style assets are clean" \
                 || { fail "C2PA manifests found:"; echo "$c2pa" | sed 's/^/        /'; }

head_ "licensing"
for f in LICENSE LICENSES/GPL-3.0-or-later.txt LICENSES/LGPL-3.0-or-later.txt REUSE.toml; do
  [[ -s "$f" ]] && pass "$f present" || fail "$f missing or empty"
done
for v in "${VARIANTS[@]}"; do
  id=$(grep -m1 '^ID=' "variants/$v/variant.env" | cut -d= -f2)
  [[ -s "variants/$v/aurorae/$id/LICENSE" ]] && pass "variants/$v/aurorae/$id/LICENSE travels with the artwork" \
                                             || fail "variants/$v/aurorae/$id/LICENSE missing - required when redistributing Moe"
done
if command -v reuse >/dev/null; then
  reuse lint -q && pass "reuse lint" || { fail "reuse lint"; reuse lint | tail -20 | sed 's/^/        /'; }
else
  echo "  --    reuse not installed; skipped (pipx install reuse)"
fi

head_ "previews"
# The README says status: untested. Composed previews of an unverified theme are the
# fastest way to get comments you do not want, so this is a warning, not a failure.
for v in "${VARIANTS[@]}"; do
  id=$(grep -m1 '^ID=' "variants/$v/variant.env" | cut -d= -f2)
  p="variants/$v/look-and-feel/$id/contents/previews/preview.png"
  if grep -qs c2pa "$p"; then
    echo "  --    $p is still a generated composite, not a screenshot"
  else
    pass "$p looks like a real screenshot"
  fi
done

echo
if [[ $fails -eq 0 ]]; then
  printf '\033[1;32mall static checks passed\033[0m\n'
else
  printf '\033[1;31m%d static check(s) failed\033[0m\n' "$fails"
fi

if [[ "${1:-}" == "--static-only" ]]; then
  exit $(( fails > 0 ))
fi

echo
head_ "unit suites"
./tests/run-unit-tests.sh || fails=$((fails+1))
exit $(( fails > 0 ))
