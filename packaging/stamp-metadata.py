#!/usr/bin/env python3
"""Generate the KPlugin fields of every package's metadata.json from one source.

The two variants were forked, so their metadata drifted: the dark look-and-feel and
Plasma style both still described themselves as "Breeze Light throughout", the Aurorae
packages claimed "SVG artwork unmodified" when decoration.svg is retinted, and the
Aurorae Version said 1.9 while everything else said 1.0.

Descriptions, names, ids and the version now come from here plus VERSION plus
variants/<slug>/variant.env. Nothing is typed twice, so nothing can disagree.

It also generates the legacy aurorae metadata.desktop and the look-and-feel's
contents/defaults, both of which are pure functions of the variant.

    packaging/stamp-metadata.py            rewrite the files
    packaging/stamp-metadata.py --check    exit 1 if any file is out of date (CI gate)
"""
import json
import pathlib
import shlex
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = (ROOT / "VERSION").read_text().strip()

# One template per package kind. {name}, {base} and {id} come from the variant.
DESCRIPTIONS = {
    "aurorae": (
        "Moe window decorations by jomada, repackaged under the id {id} for the {name} "
        "global theme so an upstream Moe update cannot change your titlebars. "
        "decoration.svg is retinted to the window background; the other seven SVGs are "
        "jomada's artwork unmodified."
    ),
    "look-and-feel": (
        "{base} throughout, with the Moe Aurorae window decoration and a translucent "
        "Plasma style. Carries no panel layout, so applying it changes appearance only."
    ),
    "desktoptheme": (
        "{base} with a translucent panel, popups and plasmoids. Inherits every asset it "
        "does not override from Breeze."
    ),
}

LICENSES = {
    "aurorae": "GPL-3.0-or-later",       # redistributes jomada's GPLv3 artwork
    "look-and-feel": "GPL-3.0-or-later", # ships alongside it
    "desktoptheme": "LGPL-3.0-or-later", # original work, Breeze-derived assets
}

BASE_LABEL = {"BreezeLight": "Breeze Light", "BreezeDark": "Breeze Dark"}

# Variant-neutral and deliberately the same for both: Breeze button convention, no
# panel layout, and the plugin id KWin itself writes on Plasma 6.6.
AURORAE_PLUGIN = "org.kde.kwin.aurorae.v2"
BUTTONS_LEFT = "M"
BUTTONS_RIGHT = "IAX"
WIDGET_STYLE = "Breeze"

DESKTOP_TEMPLATE = """[Desktop Entry]
Name={name}

X-KDE-PluginInfo-Author=jomada
X-KDE-PluginInfo-Email=gicalucejo@gmail.com
X-KDE-PluginInfo-Name={id}
X-KDE-PluginInfo-Version={version}
X-KDE-PluginInfo-Category=
X-KDE-PluginInfo-Depends=
X-KDE-PluginInfo-License=GPL_V3
X-KDE-PluginInfo-EnabledByDefault=true
X-KDE-PluginInfo-blur=false
"""

# No [kwinrc][Desktop] layout section anywhere in here on purpose: a look-and-feel that
# carries one replaces the user's panels when applied.
DEFAULTS_TEMPLATE = """[kdeglobals][General]
ColorScheme={id}

[kdeglobals][KDE]
widgetStyle={widget_style}

[kdeglobals][Icons]
Theme={icon_theme}

[kcminputrc][Mouse]
cursorTheme={cursor_theme}

[plasmarc][Theme]
name={id}

[kwinrc][DesktopSwitcher]
LayoutName=org.kde.breeze.desktop

[kwinrc][WindowSwitcher]
LayoutName=org.kde.breeze.desktop

[kwinrc][org.kde.kdecoration2]
library={plugin}
theme=__aurorae__svg__{id}
ButtonsOnLeft={buttons_left}
ButtonsOnRight={buttons_right}
BorderSize=Normal
BorderSizeAuto=false
"""


def read_env(path):
    """Parse a variant.env without executing anything but `set`-style assignments."""
    out = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = shlex.split(v)[0] if v else ""
    return out


def packages(slug, env):
    ident = env["ID"]
    return [
        ("aurorae", ROOT / "variants" / slug / "aurorae" / ident / "metadata.json"),
        ("look-and-feel", ROOT / "variants" / slug / "look-and-feel" / ident / "metadata.json"),
        ("desktoptheme", ROOT / "variants" / slug / "plasma" / "desktoptheme" / ident / "metadata.json"),
    ]


def render_desktop(env):
    return DESKTOP_TEMPLATE.format(name=env["NAME"], id=env["ID"], version=VERSION)


def render_defaults(env):
    return DEFAULTS_TEMPLATE.format(
        id=env["ID"],
        widget_style=WIDGET_STYLE,
        icon_theme=env["ICON_THEME"],
        cursor_theme=env["CURSOR_THEME"],
        plugin=AURORAE_PLUGIN,
        buttons_left=BUTTONS_LEFT,
        buttons_right=BUTTONS_RIGHT,
    )


def generated(slug, env):
    """Non-JSON files that are also pure functions of the variant."""
    ident = env["ID"]
    return [
        (ROOT / "variants" / slug / "aurorae" / ident / "metadata.desktop",
         render_desktop(env)),
        (ROOT / "variants" / slug / "look-and-feel" / ident / "contents" / "defaults",
         render_defaults(env)),
    ]


def stamp(kind, path, env):
    doc = json.loads(path.read_text())
    plugin = doc["KPlugin"]
    base = BASE_LABEL.get(env["BASE_SCHEME"], env["BASE_SCHEME"])
    plugin["Id"] = env["ID"]
    plugin["Name"] = env["NAME"]
    plugin["Version"] = VERSION
    plugin["License"] = LICENSES[kind]
    plugin["Description"] = DESCRIPTIONS[kind].format(
        id=env["ID"], name=env["NAME"], base=base
    )
    return json.dumps(doc, indent=4, ensure_ascii=False) + "\n"


def main():
    check = "--check" in sys.argv[1:]
    stale = []
    for env_file in sorted((ROOT / "variants").glob("*/variant.env")):
        slug = env_file.parent.name
        env = read_env(env_file)
        targets = [(path, stamp(kind, path, env)) for kind, path in packages(slug, env)
                   if path.exists()]
        for kind, path in packages(slug, env):
            if not path.exists():
                print(f"missing: {path.relative_to(ROOT)}", file=sys.stderr)
                stale.append(path)
        targets += generated(slug, env)

        for path, want in targets:
            if path.exists() and path.read_text() == want:
                continue
            stale.append(path)
            if check:
                print(f"out of date: {path.relative_to(ROOT)}")
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(want)
                print(f"stamped: {path.relative_to(ROOT)}")
    if check and stale:
        print("\nrun packaging/stamp-metadata.py", file=sys.stderr)
        return 1
    if not stale:
        print("every generated file already matches VERSION and variant.env")
    return 0


if __name__ == "__main__":
    sys.exit(main())
