#!/usr/bin/env bash
# Derive <ID>.colors from the installed base Breeze scheme, with the Header groups
# forced to the Window colours.
#
# Why: Breeze sets [Colors:Header] BackgroundNormal away from [Colors:Window] in both
# variants - lighter in Breeze Dark, darker in Breeze Light - and Kirigami-era apps
# (Dolphin's toolbar, System Settings, Discover) paint their top strip with the Header
# colour. So even with the titlebar retinted to the Window colour there is still a step
# where the titlebar meets the toolbar. Making Header == Window closes it.
#
# Nothing is hardcoded: every value is read out of the installed system scheme, so this
# stays correct across Breeze updates.
#
# Usage:  colorscheme.sh --variant light           # write ~/.local/share/color-schemes/<ID>.colors
#         colorscheme.sh --variant light --diff    # show what would change, write nothing
# UNTESTED.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

SRC_SCHEME="${SRC_SCHEME:-$BASE_SCHEME_FILE}"
DIFF=0
[[ "${1:-}" == "--diff" ]] && DIFF=1

[[ -f "$SRC_SCHEME" ]] || die "missing $SRC_SCHEME (apt install breeze)"

python3 - "$SRC_SCHEME" "$SCHEME_DEST" "$DIFF" "$NAME" "$ID" <<'PY'
import sys, re, os
src, dest, diff, name, ident = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4], sys.argv[5]

lines = open(src, encoding="utf-8").read().splitlines()

# parse into ordered groups
groups, order, cur = {}, [], None
for ln in lines:
    m = re.match(r'^\[(.+)\]\s*$', ln)
    if m:
        cur = m.group(1)
        if cur not in groups:
            groups[cur] = []; order.append(cur)
        continue
    if cur is None:
        continue
    groups[cur].append(ln)

def kv(group):
    out = {}
    for ln in groups.get(group, []):
        if "=" in ln and not ln.strip().startswith("#"):
            k, v = ln.split("=", 1); out[k.strip()] = v.strip()
    return out

win       = kv("Colors:Window")
win_inact = kv("Colors:Window][Inactive") or win
changes   = []

def force(group, source):
    """Replace every key in `group` that also exists in `source`."""
    if group not in groups:
        return
    new = []
    for ln in groups[group]:
        if "=" in ln and not ln.strip().startswith("#"):
            k, v = ln.split("=", 1); k = k.strip(); v = v.strip()
            if k in source and source[k] != v:
                changes.append(f"  [{group}] {k}: {v} -> {source[k]}")
                new.append(f"{k}={source[k]}"); continue
        new.append(ln)
    groups[group] = new

force("Colors:Header", win)
force("Colors:Header][Inactive", win_inact)

# the titlebar colours apps read from [WM], so they agree with the decoration too
bg  = win.get("BackgroundNormal")
fg  = win.get("ForegroundNormal")
ifg = win.get("ForegroundInactive", fg)
if "WM" in groups and bg:
    new = []
    for ln in groups["WM"]:
        if "=" in ln and not ln.strip().startswith("#"):
            k, v = ln.split("=", 1); k = k.strip(); v = v.strip()
            repl = {"activeBackground": bg, "inactiveBackground": bg,
                    "activeForeground": fg, "inactiveForeground": ifg}.get(k)
            if repl and repl != v:
                changes.append(f"  [WM] {k}: {v} -> {repl}")
                new.append(f"{k}={repl}"); continue
        new.append(ln)
    groups["WM"] = new

out = []
for g in order:
    out.append(f"[{g}]")
    for ln in groups[g]:
        if g == "General" and re.match(r'^\s*Name\s*=', ln):
            out.append(f"Name={name}"); continue
        if g == "General" and re.match(r'^\s*ColorScheme\s*=', ln):
            out.append(f"ColorScheme={ident}"); continue
        out.append(ln)
body = "\n".join(out).rstrip() + "\n"
if "[General]" not in body:
    body = f"[General]\nName={name}\n\n" + body
elif not re.search(r'^Name=', body, re.M):
    body = body.replace("[General]", f"[General]\nName={name}", 1)

print(f"derived {ident} from {src}")
print(f"{len(changes)} value(s) changed:")
for c in changes:
    print(c)
if diff:
    print("\n--diff: nothing written")
else:
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, "w", encoding="utf-8").write(body)
    print(f"\nwrote {dest}")
PY
