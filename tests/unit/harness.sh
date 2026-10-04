#!/usr/bin/env bash
# Test harness. Sourced by every tests/unit/test_*.sh; not executable on its own.
#
# Each test gets a throwaway $HOME with its own XDG directories, a fake $SYSDATA
# standing in for /usr/share, and a PATH of stub KDE binaries that record every call.
# Nothing here touches the real session, so the suite is safe on a developer's desktop
# and needs no Plasma at all on a CI runner.
#
# The stubs are not mere no-ops. kreadconfig6 and kwriteconfig6 are a working key-value
# store, and plasma-apply-lookandfeel actually parses the package's contents/defaults and
# applies it - so an install-then-verify test exercises the real data files rather than
# just checking that a command was called.

QUANTUM_REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
export QUANTUM_REPO

_total=0
_failed=0

describe() { printf '\n\033[1m%s\033[0m\n' "$*"; }
pass()     { _total=$((_total+1)); printf '  \033[1;32mok\033[0m    %s\n' "$*"; }
fail()     { _total=$((_total+1)); _failed=$((_failed+1)); printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; }
_detail()  { printf '          %s\n' "$*"; }

# ---- assertions --------------------------------------------------------------
assert_eq() {  # label, expected, actual
  if [[ "$2" == "$3" ]]; then pass "$1"
  else fail "$1"; _detail "expected: ${2:-<empty>}"; _detail "actual:   ${3:-<empty>}"; fi
}
assert_contains() {  # label, haystack, needle
  if [[ "$2" == *"$3"* ]]; then pass "$1"
  else fail "$1"; _detail "looked for: $3"; _detail "in: $(printf '%s' "$2" | head -5 | tr '\n' '|')"; fi
}
assert_not_contains() {
  if [[ "$2" != *"$3"* ]]; then pass "$1"
  else fail "$1"; _detail "should not contain: $3"; fi
}
assert_file() {    [[ -f "$2" ]] && pass "$1" || { fail "$1"; _detail "missing file: $2"; }; }
assert_no_file() { [[ ! -e "$2" ]] && pass "$1" || { fail "$1"; _detail "should not exist: $2"; }; }
assert_dir() {     [[ -d "$2" ]] && pass "$1" || { fail "$1"; _detail "missing dir: $2"; }; }
assert_no_dir() { [[ ! -d "$2" ]] && pass "$1" || { fail "$1"; _detail "should be gone: $2"; }; }

assert_ok() {  # label, command...
  local label="$1"; shift
  local out; if out="$("$@" 2>&1)"; then pass "$label"
  else fail "$label"; _detail "exit $?"; printf '%s\n' "$out" | tail -5 | sed 's/^/          /'; fi
}
assert_fails() {  # label, command... - a non-zero exit is the expected result
  local label="$1"; shift
  local out; if out="$("$@" 2>&1)"; then fail "$label"; _detail "expected failure, got success"
  else pass "$label"; fi
}

# What did the scripts actually ask the system to do?
calls() { cat "$CALL_LOG" 2>/dev/null; }
assert_called() {     assert_contains "$1" "$(calls)" "$2"; }
assert_not_called() { assert_not_contains "$1" "$(calls)" "$2"; }

# Read a value back out of the sandbox's real INI files, the way a test asserts on it.
kcfg() {  # file, group, key
  "$SANDBOX/bin/_kconfig" read "$XDG_CONFIG_HOME/$1" "[$2]" "$3"
}

finish() {
  echo
  if [[ $_failed -eq 0 ]]; then printf '\033[1;32m%s: %d checks passed\033[0m\n' "$(basename "$0")" "$_total"
  else printf '\033[1;31m%s: %d of %d checks failed\033[0m\n' "$(basename "$0")" "$_failed" "$_total"; fi
  exit $(( _failed > 0 ))
}

# ---- sandbox -----------------------------------------------------------------
sandbox_up() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/quantum-test.XXXXXX")"
  export HOME="$SANDBOX/home"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CACHE_HOME="$HOME/.cache"
  export XDG_STATE_HOME="$HOME/.local/state"
  export QUANTUM_SYSTEM_DATA="$SANDBOX/usr/share"
  export QUANTUM_QT_PLUGIN_DIRS="$SANDBOX/usr/lib/qt6/plugins/org.kde.kdecoration3"
  export CALL_LOG="$SANDBOX/calls.log"
  mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" \
           "$QUANTUM_SYSTEM_DATA" "$QUANTUM_QT_PLUGIN_DIRS" "$SANDBOX/bin"
  : > "$CALL_LOG"
  export PATH="$SANDBOX/bin:$PATH"
  _write_stubs
  seed_system
  # Every test gets its own copy of the repo. retint.sh, opacity.sh, buttons.sh --base
  # and whichbg.sh all edit the SOURCE tree by design, so running them against the
  # working tree would leave a test run showing up in git status. QUANTUM_ROOT points
  # the library at the copy; lib/common.sh validates it before trusting it.
  export QUANTUM_ROOT="$SANDBOX/repo"
  mkdir -p "$QUANTUM_ROOT"
  # cp rather than tar: tar warns about files whose timestamps are a fraction of a
  # second in the future, which happens whenever a test file was just written.
  for item in "$QUANTUM_REPO"/*; do
    [[ "$(basename "$item")" == dist ]] && continue
    cp -a "$item" "$QUANTUM_ROOT/"
  done
  # Unset anything the developer's own shell might be exporting.
  export QUANTUM_RESTART_DELAY=0
  unset QUANTUM_VARIANT QUANTUM_VARIANT_OPTIONAL
}

sandbox_down() {
  [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] || return 0
  # install.sh ends with `(setsid plasmashell &)`, a deliberately detached subshell, so
  # the stub can append to the call log a moment after the script itself has exited.
  # That recreates a file under the sandbox while rm is walking it, and rm reports
  # "Directory not empty". Retry rather than assume the race cannot be lost - on a cold
  # /tmp it is lost every time.
  local attempt
  for attempt in 1 2 3; do
    rm -rf "$SANDBOX" 2>/dev/null && return 0
    echo "sandbox teardown retry $attempt" >> "${CALL_LOG:-/dev/null}" 2>/dev/null || true
    sleep 0.3
  done
  rm -rf "$SANDBOX" 2>/dev/null
  return 0
}

# A fresh sandbox per test case, so one case cannot leak state into the next.
sandbox_reset() { sandbox_down; sandbox_up; }

# ---- the fake system ---------------------------------------------------------
# Enough stock Breeze for the scripts to find what they look for. The colour values
# are the real ones measured on quantum, so the Header-fix assertions are meaningful.
seed_system() {
  local cs="$QUANTUM_SYSTEM_DATA/color-schemes"
  mkdir -p "$cs"
  cat > "$cs/BreezeLight.colors" <<'SCHEME'
[General]
Name=Breeze Light
ColorScheme=BreezeLight

[Colors:Window]
BackgroundNormal=239,240,241
ForegroundNormal=35,38,41
ForegroundInactive=112,125,138

[Colors:Header]
BackgroundNormal=222,224,226
BackgroundAlternate=239,240,241
ForegroundNormal=35,38,41

[Colors:View]
BackgroundNormal=255,255,255

[WM]
activeBackground=227,229,231
inactiveBackground=239,240,241
activeForeground=35,38,41
inactiveForeground=112,125,138
SCHEME
  cat > "$cs/BreezeDark.colors" <<'SCHEME'
[General]
Name=Breeze Dark
ColorScheme=BreezeDark

[Colors:Window]
BackgroundNormal=32,35,38
ForegroundNormal=252,252,252
ForegroundInactive=161,169,177

[Colors:Header]
BackgroundNormal=41,44,48
BackgroundAlternate=32,35,38
ForegroundNormal=252,252,252

[Colors:View]
BackgroundNormal=27,30,32

[WM]
activeBackground=39,44,49
inactiveBackground=32,36,40
activeForeground=252,252,252
inactiveForeground=161,169,177
SCHEME

  # stock global themes, with the keys a real package carries
  local lnf="$QUANTUM_SYSTEM_DATA/plasma/look-and-feel"
  for pkg in org.kde.breeze.desktop org.kde.breezedark.desktop; do
    mkdir -p "$lnf/$pkg/contents"
    local scheme=BreezeLight
    [[ "$pkg" == *dark* ]] && scheme=BreezeDark
    cat > "$lnf/$pkg/contents/defaults" <<DEFAULTS
[kdeglobals][General]
ColorScheme=$scheme

[kdeglobals][KDE]
widgetStyle=Breeze

[kdeglobals][Icons]
Theme=breeze

[plasmarc][Theme]
name=default

[kwinrc][org.kde.kdecoration2]
library=org.kde.breeze
theme=Breeze
DEFAULTS
  done

  # stock Plasma style, icon theme, cursors
  mkdir -p "$QUANTUM_SYSTEM_DATA/plasma/desktoptheme/default"
  printf '[Settings]\n' > "$QUANTUM_SYSTEM_DATA/plasma/desktoptheme/default/plasmarc"
  mkdir -p "$QUANTUM_SYSTEM_DATA/icons/breeze"
  printf '[Icon Theme]\nName=breeze\nInherits=hicolor\n' > "$QUANTUM_SYSTEM_DATA/icons/breeze/index.theme"
  mkdir -p "$QUANTUM_SYSTEM_DATA/icons/breeze_cursors/cursors"
  : > "$QUANTUM_SYSTEM_DATA/icons/breeze_cursors/cursors/left_ptr"

  # both Aurorae plugins, as measured on quantum
  : > "$QUANTUM_QT_PLUGIN_DIRS/org.kde.kwin.aurorae.so"
  : > "$QUANTUM_QT_PLUGIN_DIRS/org.kde.kwin.aurorae.v2.so"

  # a starting appearance state, so a backup has something to record
  _kcfg_set kdeglobals KDE LookAndFeelPackage org.kde.breeze.desktop
  _kcfg_set kdeglobals General ColorScheme BreezeLight
  _kcfg_set kdeglobals KDE widgetStyle Breeze
  _kcfg_set kdeglobals Icons Theme breeze
  _kcfg_set plasmarc Theme name default
  _kcfg_set kwinrc org.kde.kdecoration2 library org.kde.breeze
  _kcfg_set kwinrc org.kde.kdecoration2 theme Breeze
  _kcfg_set kcminputrc Mouse cursorTheme breeze_cursors
  _kcfg_set kcminputrc Mouse cursorSize 24
}

_kcfg_set() { "$SANDBOX/bin/_kconfig" write "$XDG_CONFIG_HOME/$1" "[$2]" "$3" "$4"; }

# Install the variant's icon theme into the fake system, for the paths that require it.
seed_icon_theme() {  # theme name
  mkdir -p "$XDG_DATA_HOME/icons/$1"
  printf '[Icon Theme]\nName=%s\nInherits=breeze,Adwaita,hicolor\nFollowsColorScheme=true\n' "$1" \
    > "$XDG_DATA_HOME/icons/$1/index.theme"
}

# ---- stubs -------------------------------------------------------------------
_write_stubs() {
  local b="$SANDBOX/bin"

  # A real KConfig INI writer, not a key-value side-store. This matters: buttons.sh and
  # verify.sh both CALL kwriteconfig6 and then PARSE the resulting file themselves with
  # awk. A stub that kept values anywhere else would let those parses silently find
  # nothing, and the test would be green about code that never ran.
  cat > "$b/_kconfig" <<'STUB'
#!/usr/bin/env python3
"""kconfig INI read/write, KDE's group syntax: [group] or [outer][inner]."""
import os, re, sys

def parse(path):
    groups, order = {}, []
    cur = None
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            if re.match(r'^\s*\[.+\]\s*$', line):
                cur = line.strip()
                if cur not in groups:
                    groups[cur] = []; order.append(cur)
                continue
            if cur is None:
                continue
            groups[cur].append(line)
    return groups, order

def write(path, groups, order):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = []
    for g in order:
        out.append(g)
        # blank lines inside a group body would otherwise accumulate one per write
        out.extend(ln for ln in groups[g] if ln.strip())
        out.append("")
    open(path, "w", encoding="utf-8").write("\n".join(out).rstrip() + "\n")

def main():
    mode, path, header, key = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    groups, order = parse(path)
    if mode == "read":
        for line in groups.get(header, []):
            if "=" in line:
                k, v = line.split("=", 1)
                if k.strip() == key:
                    print(v.strip()); return 0
        return 0
    value = sys.argv[5] if len(sys.argv) > 5 else ""
    if header not in groups:
        groups[header] = []; order.append(header)
    body, done = [], False
    for line in groups[header]:
        if "=" in line and line.split("=", 1)[0].strip() == key:
            if not done:
                body.append(f"{key}={value}"); done = True
            continue
        body.append(line)
    if not done:
        body.append(f"{key}={value}")
    groups[header] = body
    write(path, groups, order)
    return 0

sys.exit(main())
STUB

  cat > "$b/kwriteconfig6" <<'STUB'
#!/usr/bin/env bash
echo "kwriteconfig6 $*" >> "$CALL_LOG"
f=""; header=""; k=""; v=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)  exit 0 ;;
    --file)  f="$2"; shift 2 ;;
    --group) header="$header[$2]"; shift 2 ;;
    --key)   k="$2"; shift 2 ;;
    *)       v="$1"; shift ;;
  esac
done
[[ -n "$f" && -n "$k" ]] || exit 1
# A bare name goes under XDG_CONFIG_HOME, which is where the scripts read it from.
[[ "$f" == /* ]] || f="$XDG_CONFIG_HOME/$f"
exec _kconfig write "$f" "$header" "$k" "$v"
STUB

  cat > "$b/kreadconfig6" <<'STUB'
#!/usr/bin/env bash
echo "kreadconfig6 $*" >> "$CALL_LOG"
f=""; header=""; k=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)  f="$2"; shift 2 ;;
    --group) header="$header[$2]"; shift 2 ;;
    --key)   k="$2"; shift 2 ;;
    *)       shift ;;
  esac
done
[[ -n "$f" && -n "$k" ]] || exit 0
[[ "$f" == /* ]] || f="$XDG_CONFIG_HOME/$f"
exec _kconfig read "$f" "$header" "$k"
STUB

  cat > "$b/plasma-apply-lookandfeel" <<'STUB'
#!/usr/bin/env bash
echo "plasma-apply-lookandfeel $*" >> "$CALL_LOG"
if [[ "${1:-}" == "--list" ]]; then
  for root in "$XDG_DATA_HOME/plasma/look-and-feel" "$QUANTUM_SYSTEM_DATA/plasma/look-and-feel"; do
    [[ -d "$root" ]] || continue
    for d in "$root"/*; do [[ -d "$d" ]] && basename "$d"; done
  done | sort -u
  exit 0
fi
[[ "${1:-}" == "-a" || "${1:-}" == "--apply" ]] || exit 2
id="${2:?}"
pkg=""
for root in "$XDG_DATA_HOME/plasma/look-and-feel" "$QUANTUM_SYSTEM_DATA/plasma/look-and-feel"; do
  [[ -d "$root/$id" ]] && { pkg="$root/$id"; break; }
done
[[ -n "$pkg" ]] || { echo "no such look-and-feel: $id" >&2; exit 1; }
_kconfig write "$XDG_CONFIG_HOME/kdeglobals" "[KDE]" LookAndFeelPackage "$id"
# Apply the package's own contents/defaults, exactly as Plasma does. This is what makes
# an install-then-verify test exercise the real data files rather than the stub.
if [[ -f "$pkg/contents/defaults" ]]; then
  # Parsed with parameter expansion rather than a regex: [[ =~ ]] with a bracket
  # expression inside an escaped-bracket pattern silently matched nothing here, and a
  # stub that silently applies none of the defaults makes every assertion about the
  # applied state wrong while every command still "succeeds".
  cf=""; grp=""
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == "#"* ]] && continue
    if [[ "$line" == \[*\]\[*\] ]]; then
      rest="${line#\[}"; cf="${rest%%\]*}"
      rest="${line#*\]\[}"; grp="[${rest%\]}]"
      continue
    fi
    [[ "$line" == *=* && -n "$cf" ]] || continue
    _kconfig write "$XDG_CONFIG_HOME/$cf" "$grp" "${line%%=*}" "${line#*=}"
  done < "$pkg/contents/defaults"
fi
exit 0
STUB

  cat > "$b/plasma-apply-desktoptheme" <<'STUB'
#!/usr/bin/env bash
echo "plasma-apply-desktoptheme $*" >> "$CALL_LOG"
if [[ "${1:-}" == "--list-themes" ]]; then
  for root in "$XDG_DATA_HOME/plasma/desktoptheme" "$QUANTUM_SYSTEM_DATA/plasma/desktoptheme"; do
    [[ -d "$root" ]] || continue
    for d in "$root"/*; do [[ -d "$d" ]] && basename "$d"; done
  done | sort -u
  exit 0
fi
exit 0
STUB

  cat > "$b/plasma-apply-cursortheme" <<'STUB'
#!/usr/bin/env bash
echo "plasma-apply-cursortheme $*" >> "$CALL_LOG"
t="${1:-}"
for d in "$XDG_DATA_HOME/icons/$t" "$QUANTUM_SYSTEM_DATA/icons/$t"; do
  [[ -d "$d/cursors" ]] && { _kconfig write "$XDG_CONFIG_HOME/kcminputrc" "[Mouse]" cursorTheme "$t"; exit 0; }
done
echo "no such cursor theme: $t" >&2; exit 1
STUB

  cat > "$b/plasmashell" <<'STUB'
#!/usr/bin/env bash
echo "plasmashell $*" >> "$CALL_LOG"
[[ "${1:-}" == "--version" ]] && { echo "plasmashell ${QUANTUM_TEST_PLASMA_VERSION:-6.6.6}"; exit 0; }
exit 0
STUB

  cat > "$b/gsettings" <<'STUB'
#!/usr/bin/env bash
echo "gsettings $*" >> "$CALL_LOG"
if [[ "${1:-}" == "get" ]]; then
  p="$SANDBOX/gsettings/${2//\//_}/${3:-}"
  [[ -f "$p" ]] && cat "$p" || echo "'default'"
  exit 0
fi
if [[ "${1:-}" == "set" ]]; then
  d="$SANDBOX/gsettings/${2//\//_}"; mkdir -p "$d"; printf '%s' "${4:-}" > "$d/${3:-x}"
fi
exit 0
STUB

  cat > "$b/xdpyinfo" <<'STUB'
#!/usr/bin/env bash
echo "xdpyinfo $*" >> "$CALL_LOG"
echo "  resolution:    96x96 dots per inch"
STUB

  # Everything whose only job is to be called.
  for t in qdbus6 qdbus kquitapp6 kbuildsycoca6 pkill setsid gtk-update-icon-cache; do
    cat > "$b/$t" <<STUB
#!/usr/bin/env bash
echo "$t \$*" >> "\$CALL_LOG"
exit 0
STUB
  done

  cat > "$b/journalctl" <<'STUB'
#!/usr/bin/env bash
echo "journalctl $*" >> "$CALL_LOG"
exit 0
STUB

  chmod +x "$b"/*
}

# ---- running the scripts under test ------------------------------------------
# Captures stdout+stderr together, because these scripts talk to the operator on both.
#
# The exit status goes through a FILE, not a variable: run() is nearly always called in
# a command substitution, and a variable set inside that subshell never reaches the
# caller. Read it with status().
# errexit is SAVED and restored, not switched on. An earlier version ended with a bare
# `set -e`, which turned errexit on for the rest of a suite that had never enabled it -
# so the first non-zero command anywhere afterwards killed the run. It passed on a warm
# machine and died on a cold one, which is the exact failure mode a test harness must
# not have.
_without_errexit() {  # command... -> output on stdout, status into last_status
  local out rc had_e=0
  [[ $- == *e* ]] && had_e=1
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  (( had_e )) && set -e
  printf '%s' "$rc" > "$SANDBOX/last_status"
  printf '%s' "$out"
}

run() {  # script-name, args... -> output on stdout; status() has the exit code
  local s="$1"; shift
  _without_errexit "$QUANTUM_ROOT/bin/$s" "$@"
}

# Same, for an arbitrary command (a per-variant symlink, say).
run_cmd() { _without_errexit "$@"; }

status() { cat "$SANDBOX/last_status" 2>/dev/null || echo "<no run recorded>"; }

# Paths inside the sandboxed copy of the repo.
src()  { printf '%s\n' "$QUANTUM_ROOT/$1"; }
# Paths inside the sandboxed install target.
dest() { printf '%s\n' "$XDG_DATA_HOME/$1"; }
