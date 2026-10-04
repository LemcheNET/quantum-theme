---
type: runbook
subject: Workstation desktop
artifact: Quantum global themes for KDE Plasma 6
status: verified for install — install.sh --apply and verify.sh run clean for both variants on quantum (Plasma 6.6.6, Kubuntu 26.04) 2026-10-04; shellcheck and the tests/ gates pass. uninstall.sh was rewritten after that round trip found three defects in its backup replay and now reverts to stock Breeze: UNTESTED in this form. Also unexercised: retint.sh, opacity.sh, buttons.sh, whichbg.sh, gtk.sh --rebuild, icons.sh
owner: Valdemar Lemche
concepts: [KDE Plasma, Aurorae, look-and-feel package, Plasma style, window decoration, breeze-gtk]
tags: [desktop, plasma, theming, kde]
sources:
  - https://gitlab.com/jomada/moe-theme
  - https://github.com/L4ki/Slot-Plasma-Themes
  - https://develop.kde.org/docs/plasma/theme/theme-details/
  - https://develop.kde.org/docs/plasma/aurorae/
  - https://invent.kde.org/plasma/breeze-gtk
  - https://github.com/vinceliuice/WhiteSur-kde/issues/130
date: 2026-10-04
---

# Quantum

Two Plasma 6 global themes — **Quantum Light** and **Quantum Dark** — that each make the
titlebar, the toolbar beneath it and the window body a single uninterrupted colour, and
make Plasma's own surfaces translucent. Stock Breeze underneath; jomada's **Moe** Aurorae
decoration retinted to match; l4k1's **Slot** icons; a thin translucent Plasma style.
Targets Plasma 6.6 on Kubuntu 26.04.

The two variants are one codebase. Everything that differs between them lives in
`variants/<slug>/variant.env`; everything else is shared. See
[How the variants stay in step](#how-the-variants-stay-in-step) for why that matters.

**Verified for the install path.** `bin/install.sh --variant <slug> --apply` followed by
`bin/verify.sh --variant <slug>` runs clean for both variants on `quantum`, Plasma 6.6.6
on Kubuntu 26.04. That round trip found three defects in `uninstall.sh`, which has since
been rewritten to revert to stock Breeze and is **untested in its current form**. Also
unexercised: `retint.sh`, `opacity.sh`, `buttons.sh`, `whichbg.sh`, `icons.sh`, and
`gtk.sh --rebuild`. Start with the read-only `bin/verify.sh`.

## The two variants

| | Quantum Light | Quantum Dark |
|---|---|---|
| slug | `light` | `dark` |
| package id | `QuantumLight` | `QuantumDark` |
| derived from | `BreezeLight` | `BreezeDark` |
| window background | `#eff0f1` | `#202326` |
| `[Colors:Header]` in stock Breeze | `#dee0e2` — *darker* than Window | `#292c30` — *lighter* than Window |
| icons | `Slot-Light-Icons` | `Slot-Dark-Icons` |
| cursors | `breeze_cursors` | `breeze_cursors` |
| portal preference | `prefer-light` | `prefer-dark` |

Shared by both, and defined once in `theme.env`: Breeze application style, no desktop
layout, buttons on the right (`ButtonsOnLeft=M`, `ButtonsOnRight=IAX`), the Aurorae
plugin id, and the `kwinrc` group name. Panel at 65% and popups at 75%.

**The application style is checked, not just reported.** `contents/defaults` sets
`widgetStyle`, so a different live value means either `plasma-apply-lookandfeel` did not
write it or something changed it since — `verify.sh` found Fusion on `quantum` while the
look-and-feel declared Breeze. The colour scheme does still reach a non-Breeze Qt style
through the platform theme, so this is not necessarily a returning colour seam; what
changes is how widgets are *drawn*, which is not what the theme was designed or previewed
against. It is now an assertion rather than a printed value.

## One colour across the whole window

Upstream Moe paints its frame `#f7f9f9`, a near-white. Left alone against Breeze Dark's
`#202326` that is not a seam so much as a collision; against Breeze Light's `#eff0f1` it
is a visible step.

The frame is a single flat colour on every slice — active and inactive, all four edges,
all four corners, no gradients and no border strokes. That was verified by rendering each
of the eighteen slices and taking a colour histogram: 100% one colour. So matching the
decoration to the application style is one substitution, and after it the titlebar, the
toolbar beneath it and the window's own background are the same value with nothing
between them. The window reads as one surface, separated from the desktop by Moe's drop
shadow rather than by a colour change.

`bin/retint.sh` does this, and can retarget it:

```bash
bin/retint.sh --variant dark                      # match the installed BreezeDark
bin/retint.sh --variant dark '#31363b'            # some other colour
bin/retint.sh --variant dark --from /path/to.colors
```

It reads `[Colors:Window] BackgroundNormal` out of the scheme file rather than trusting a
hardcoded value, and it is idempotent. `bin/verify.sh` cross-checks the installed
decoration against the live scheme and tells you to re-run it if they have drifted apart
— which they will if you ever change colour scheme.

The buttons are untouched: Moe's pink-red close (`#ff597d`), blue maximize (`#538fff`),
teal minimize (`#19c0ca`). They are the only colour in the frame, which is the point.

### The second seam: `[Colors:Header]`

Retinting the decoration is only half of it. Breeze separates `[Colors:Window]` from
`[Colors:Header]`, and Kirigami-era apps — Dolphin's toolbar, System Settings, Discover —
paint their top strip with **Header**, not Window. So a retinted titlebar still meets a
differently-coloured toolbar and the line reappears one row lower. Both variants have the
gap; they have it in opposite directions.

`bin/colorscheme.sh` fixes it by deriving `<ID>.colors` from the *installed* base scheme
and forcing `[Colors:Header]`, `[Colors:Header][Inactive]` and `[WM] activeBackground` to
the Window values. Nothing is hardcoded, so it stays right across Breeze updates, and it
is idempotent — a second run over its own output reports zero changes.

```bash
bin/colorscheme.sh --variant light --diff    # show what would change, write nothing
bin/colorscheme.sh --variant light           # write ~/.local/share/color-schemes/QuantumLight.colors
```

`bin/install.sh --apply` runs it. `bin/verify.sh` asserts Header == Window in whichever
scheme is actually active. To keep stock Breeze instead, set `ColorScheme=<base>` in the
look-and-feel's `contents/defaults` and accept the toolbar step.

## Icons

`Slot-Light-Icons` / `Slot-Dark-Icons` by l4k1, GPLv3 —
[KDE Store 2234789](https://store.kde.org/p/2234789/), source
[github.com/L4ki/Slot-Plasma-Themes](https://github.com/L4ki/Slot-Plasma-Themes).

**Not bundled**, and the two sets are not the same size. Measured installed on `quantum`,
2026-10-04:

| | files | on disk | `Inherits=` |
|---|---|---|---|
| `Slot-Light-Icons` | 13,435 | 182 MiB | `breeze,Adwaita,hicolor` |
| `Slot-Dark-Icons` | 19,436 | 215 MiB | `breeze-dark,Adwaita,hicolor` |

Against about 700 KiB for everything else in a variant — two orders of magnitude, so it
is a dependency, fetched on demand. Run `bin/icons.sh --variant <slug> --check` for your
own host rather than trusting the table; upstream changes it, and these numbers are one
measurement on one machine.

```bash
bin/icons.sh --variant dark              # sparse clone, install to ~/.local/share/icons
bin/icons.sh --variant dark --dedupe     # then hardlink identical files
bin/icons.sh --variant dark --check      # report what is installed, change nothing
bin/icons.sh --variant dark --from <dir> # install from a clone you already have
```

The sparse clone pulls only the one icon theme, not the 559 MiB repo.

`--dedupe` is worth knowing about: a large fraction of each theme is byte-identical
duplicates, and hardlinking them reclaims real space. **The ratio is not verified for the
installed versions.** An earlier note here claimed 62% against a 130 MiB baseline and
19,873 files — which is within a few hundred of the *dark* theme's file count while being
quoted in both variants' docs, so it had been carried across the fork like the
descriptions were. `icons.sh --dedupe` prints the actual before and after, which is the
number to trust. The catch is that editing one icon afterwards edits every identical
copy, so it is opt-in. Re-run without `--dedupe` to get a clean tree back.

Two things about these themes that matter here:

- **`Inherits=breeze,Adwaita,hicolor`.** Anything Slot does not provide falls back to
  Breeze, which is exactly the relationship the rest of this package has with Breeze.
  `verify.sh` asserts it — a theme that did not inherit breeze would leave blank icons.
- **`FollowsColorScheme=true`**, so it recolours with the active scheme rather than
  fighting it.

The light and dark sets are counterparts, so the two themes look like siblings rather
than two unrelated icon packs.

`install.sh` refuses to `--apply` if the icon theme is missing, rather than applying a
global theme that points at icons you do not have. `--force-icons` overrides.
`uninstall.sh` restores your previous icon theme but leaves Slot on disk.

## Cursors

`breeze_cursors`, set in `contents/defaults` and applied explicitly with
`plasma-apply-cursortheme`, because that pokes the running session and XWayland rather
than only writing `kcminputrc`.

Both variants use it. Kubuntu's `breeze-cursor-theme` installs two themes —
`breeze_cursors` (dark, with a light outline) and `Breeze_Snow` (white). The light
outline is what keeps the dark pointer visible on dark surfaces, and it is what KDE's own
Breeze Dark uses, so both variants keep it. If you want a white pointer on the dark
theme, change `CURSOR_THEME` in `variants/dark/variant.env` — `verify.sh` reads the same
file, so the check follows the change rather than fighting it.

`cursorSize` is deliberately left alone: it is yours, and a global theme overwriting a
pointer size you chose for a 4K panel would be rude.

If some windows keep the old X11 arrow after applying — typically Qt5 or GTK apps under
XWayland — that is a Plasma integration gap rather than a theme problem. Check
`~/.icons/default/index.theme` first (`verify.sh` reports it if present; a stale
`Inherits=` there can override `kcminputrc` for X11 clients). The blunt fallback is
`XCURSOR_THEME=breeze_cursors` in the environment, but reach for it last — it papers over
a missing integration package rather than fixing it, and this package does not set it for
you.

## GTK applications

GTK2, GTK3 and GTK4 themes named after the variant, generated by **KDE's own
`breeze-gtk`** from the variant's colour scheme rather than hand-written.
`breeze-gtk`'s `build_theme.sh` takes a scheme *by name* and looks in
`~/.local/share/color-schemes/` — exactly where `colorscheme.sh` puts it. So the GTK
palette is derived from the same single source as the Plasma side and cannot drift from
it.

```bash
bin/gtk.sh --variant light              # install the bundled prebuilt theme, point GTK at it
bin/gtk.sh --variant light --rebuild    # regenerate from the scheme installed on THIS host
bin/gtk.sh --variant light --check      # report what is installed and active
bin/gtk.sh --variant light --libadwaita # also force it on libadwaita apps (see below)
```

Each variant ships its theme prebuilt as `variants/<slug>/gtk/<ID>-gtk.tar.gz` (280
files, 1.6 MiB unpacked) so you need no build tools. `--rebuild` is the honest option if
your installed Breeze differs from the one the bundle was built against; it needs `sassc`
and `python3-cairo`.

`gtk.sh` writes `gtk-theme-name` into `~/.config/gtk-3.0/settings.ini`,
`~/.config/gtk-4.0/settings.ini` and `~/.gtkrc-2.0`, sets the `gsettings` keys, and
updates `xsettingsd` if you run it.

### Light/dark preference, and apps that look inverted

Qt apps follow the Plasma colour scheme directly. **GTK apps, and anything reading the
XDG portal's `org.freedesktop.appearance color-scheme` — which includes Electron apps —
do not.** They follow whatever `gtk.sh` last set.

Applying a Plasma theme without updating that leaves them one theme behind. Alternate
between the two variants and it reads as the preference being *inverted*: you apply the
light theme and those apps go dark, you apply the dark theme and they go light. They are
not inverted, they are stale.

`install.sh --apply` syncs it — it runs `gtk.sh` when the GTK theme is installed, and
otherwise sets the `gsettings` key and `gtk-application-prefer-dark-theme` directly from
the variant's `PORTAL_PREF` and `GTK_PREFER_DARK`. `verify.sh` compares the live value
against the variant's and says so when they disagree. To check what those apps are
actually being told:

```bash
gsettings get org.gnome.desktop.interface color-scheme
busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
  org.freedesktop.portal.Settings Read ss org.freedesktop.appearance color-scheme
```

The portal value is authoritative: `1` means prefer-dark, `2` means prefer-light.

**Two things it cannot fix:**

- **libadwaita.** GTK4 apps built on libadwaita largely ignore themes by design. The
  bundled GTK4 CSS helps plain GTK4 apps; `--libadwaita` copies it to
  `~/.config/gtk-4.0/gtk.css`, which forces it globally. That is a blunt instrument — if
  a GTK4 app misrenders, delete that file. Opt-in for exactly that reason.
- **`kde-gtk-config` will fight you.** Turn OFF System Settings → Colors → Options →
  "apply colors to non-Qt applications", or it regenerates GTK colours from the active
  scheme and overwrites this. Upstream `breeze-gtk`'s own README says the same.

## Button size

Already customizable, and not by anything this theme added — Aurorae supports it and
System Settings has the control: **Window Decorations → the configure (gear) button on
the theme → Button size**, seven steps from Tiny to Oversized.

From `aurorae/v2/decoration.cpp`:

```cpp
const KConfigGroup group(m_auroraerc, m_themeName);
const int buttonSize = group.readEntry("ButtonSize", 1);
setButtonSizeFactor(1.0 + (buttonSize - 1) * 0.2);
```

So it is `~/.config/auroraerc`, group `[<ID>]`, key `ButtonSize` (0–6), and every button
is drawn at its theme size times that factor. The titlebar follows on its own —
`v2/decorationtheme.cpp:159` computes

```cpp
titleHeight = max(TitleHeight, ButtonHeight * factor + ButtonMarginTop)
```

### Every variant, not one

**Every button-size control in KDE is per-theme.** The `auroraerc` group is the theme
name, so `[QuantumLight]` and `[QuantumDark]` are separate settings, and the gear button
in System Settings only ever touches the theme you clicked. The two diverge the moment
you adjust one, and you will not notice until you switch.

`bin/buttons.sh` therefore writes **every variant** by default — every `auroraerc` group,
every variant's rc file, and every installed copy. It reports them side by side and warns
when they have drifted apart.

```bash
bin/buttons.sh                              # every variant, with the pixels they work out to
bin/buttons.sh large                        # or an index 0-6 — applied to all
bin/buttons.sh --base 16                    # set ButtonWidth/ButtonHeight on all
bin/buttons.sh --variant light --sync       # copy light's base onto the others
bin/buttons.sh --base 16 --only dark        # deliberately set just one
```

It needs no `--variant` to report or to set a size, because it works across all of them;
`--sync` is the one mode that needs a source variant.

### Two independent knobs

There are **two** things that change button size, and they multiply:

| | where | scope |
|---|---|---|
| `ButtonWidth`/`ButtonHeight` | the variant's own `<ID>rc` | per theme, `--base` |
| `ButtonSize` 0–6 | `~/.config/auroraerc` `[<ID>]` | per theme, the gear in System Settings |

A 2× difference between the variants with identical bases means the `auroraerc`
`ButtonSize` differs — Oversized is 2.0× against Normal's 1.0×. `buttons.sh` with no
arguments prints both knobs for every variant and warns on either mismatch. It also
prints the **installed** base next to the source one: the installed copy under
`~/.local/share/aurorae/themes/` is what KWin actually reads, while the source in this
repo is only what the next `install.sh` will copy over it.

### The rc is read once per KWin process

`<ID>rc` is **not** re-read on `qdbus reconfigure`. From
`aurorae/v2/decorationtheme.cpp:57` the rc is parsed in the `DecorationTheme`
constructor, and `DecorationTheme::open()` hands back a cached instance for any theme
name it has already loaded:

```cpp
for (DecorationTheme *theme : std::as_const(*globalThemes)) {
    if (theme->m_themeName == themeName) {
        return theme->shared_from_this();   // rc never re-read
    }
}
```

`Decoration::onDecorationSettingsChanged()` reparses only `auroraerc`. So:

| change | takes effect |
|---|---|
| `auroraerc` `ButtonSize` | immediately, on reconfigure |
| `<ID>rc` `ButtonWidth`/`ButtonHeight` and every other `[Layout]` value | **only after a KWin restart** |

This is how two themes with byte-identical rc files end up drawing different button
sizes: each keeps whatever was on disk the first time KWin loaded it this session.
Measured on `quantum` — light drew 43px buttons and dark 21px while both rc files said
16, because light had been loaded back when its rc said 32 (32 × 1.4 = 44.8) and dark
when it said 16 (16 × 1.4 = 22.4).

Restart KWin: `kwin_x11 --replace &` on X11, or log out and back in on Wayland.
`buttons.sh` prints this reminder whenever it touches an rc.

### Numbers

Against a base of `ButtonWidth=ButtonHeight=12`, `ButtonMarginTop=2`, `TitleHeight=15`,
`TitleEdge{Top,Bottom}=4`, at 96 dpi:

| idx | name | factor | button | titlebar |
|---|---|---|---|---|
| 0 | Tiny | 0.8× | 10px | 23px |
| 1 | Normal | 1.0× | 12px | 23px |
| 2 | Large | 1.2× | 14px | 24px |
| 3 | Very Large | 1.4× | 17px | 27px |
| 4 | Huge | 1.6× | 19px | 29px |
| 5 | Very Huge | 1.8× | 22px | 32px |
| 6 | Oversized | 2.0× | 24px | 34px |

`--base` is for granularity the seven steps cannot give; the factor then multiplies the
new base. Moe's button SVGs are 21×21 natural, so much past that they soften.

**Everything in `[Layout]` is additionally scaled by DPI**: `themeconfig.cpp:118` sets
`scaleFactor = primaryScreen.logicalDotsPerInchX() / 96`, applied to every border, edge,
title and button value before the factor above. The table assumes 96 dpi.

Aurorae also supports per-button widths — `ButtonWidthMinimize`,
`ButtonWidthMaximizeRestore`, `ButtonWidthClose` and so on, each defaulting to
`ButtonWidth`. Note the capitalisation upstream actually reads:
`ButtonWidthAlldesktops`, `ButtonWidthKeepabove`, `ButtonWidthKeepbelow` — lowercase
second word. Spelled the obvious way they silently do nothing.

## Translucency

The Plasma style makes Plasma's own surfaces translucent: **panel at 65%, popups,
plasmoids and tooltips at 75%**. It ships five background files and inherits everything
else from Breeze via `[Settings] FallbackTheme=default`, so it is a thin layer over
Breeze rather than a fork of it.

**`[ContrastEffect]` is off, and that is the setting that decides whether any of this
reads as glass.** KWin's background-contrast effect homogenises whatever sits behind a
translucent surface so text stays legible. Over a fairly uniform wallpaper it erases
every cue that the surface is transparent at all.

On `quantum` the light variant measured a consistent `#BCBDBD` and looked like opaque
grey paint — while being perfectly translucent the whole time. A surface cannot render
*darker* than its own fill unless it is blending with something behind it, so one colour
measurement proved the transparency worked and moved the search to what was hiding it.
The same check works on dark with the sign flipped. Measure first, theorise second:

| measured against the variant's window colour | verdict |
|---|---|
| exactly equal | opaque — the theme is not reaching that surface |
| lighter | translucent over a brighter backdrop |
| darker | translucent over a darker backdrop |

Turn the contrast effect back on if you move to a busy wallpaper and popup text gets hard
to read — `contrast=0.2 intensity=1.1 saturation=1.1` is a reasonable starting point.
`verify.sh` reports its state, because it is the first thing to check whenever the theme
"looks opaque".

Retune without hand-editing five SVGs:

```bash
bin/opacity.sh --variant light              # show current values
bin/opacity.sh --variant light 65 75        # panel 65%, popups 75%
bin/opacity.sh --variant light 50 60 3      # glassier still
```

It refuses percentages outside 0–100, warns below ~40% where legibility goes, and prints
the *stacked* Kickoff figure rather than the nominal one — see below for why that is the
number that matters.

### The Application Launcher

Kickoff needs `widgets/plasmoidheading.svg` as well as `dialogs/background.svg`. The
dialog background is the sheet; the heading is the search row at the top and the
user/power row at the bottom, and if the style does not ship it, Plasma falls back to
**Breeze's opaque bands** — a translucent launcher with two solid strips across it.

The trap is that the heading is painted *on top of* the dialog background, so opacity
compounds. A second 88% band over an 88% dialog is 98.6% opaque — visually solid. So the
heading is a **3% tint of the text colour**, not a repeat of the dialog value:

| | alone | over the dialog |
|---|---|---|
| dialog background | 75.0% | — |
| heading at 0.03 (shipped) | 3% | **75.8%** |
| heading at 0.75 (the obvious mistake) | 75% | 93.8% |

The result is one uniform translucent sheet with the search and power rows just barely
delineated. `opacity.sh` keeps this honest: it prints the stacked figure and warns if the
heading contributes more than about 8 points. For perfectly flat glass set `opacity` to
`0` on the `header-*` and `footer-*` elements; for visible bands raise it to about `0.10`
— past that it starts to read as solid.

KDE's own guidance is that **`plasmoidheading.svg`'s margin hints must equal
`dialogs/background.svg`'s**, or the header sits misaligned against the dialog edge. Both
are 4px here and `verify.sh` asserts it.

This file is also used by every system-tray popup and the calendar, so they pick up the
same treatment. The search field itself keeps Breeze's `lineedit.svg`, which is opaque —
deliberately, since a translucent text field hurts legibility while you are typing.

The backgrounds use the Breeze `#current-color-scheme` stylesheet with
`fill:currentColor`, so they follow the active colour scheme; translucency is element
`opacity`, which leaves that substitution intact. Use `opacity.sh` rather than editing
the files by hand.

`plasmarc` turns on `[BlurBehindEffect]` and a mild `[ContrastEffect]` so text stays
legible over a busy wallpaper. `[AdaptiveTransparency]` is off on purpose — adaptive
makes the panel opaque whenever a window is maximised, which reads as the translucency
having broken.

**Two things a Plasma style cannot do, and this one does not pretend to:**

- **Panel opacity is a per-panel setting in Plasma 6 and it wins.** Edit Mode → More
  Options → Opacity → Translucent. On the default (Adaptive) the panel goes opaque under
  a maximised window no matter what the style says. `verify.sh` prints the current
  `panelOpacity` keys.
- **Application windows are out of scope.** Dolphin and Kate being translucent is not a
  Plasma style feature — KWin only blurs windows that ask, so it needs Kvantum as the
  widget style plus the third-party `kwin-effects-forceblur`. Kvantum would replace
  Breeze, so this theme stays out of it.

## Layout

```
quantum-theme/
├── VERSION                       one version for every package in every variant
├── bin/                          ten scripts, one copy each, --variant <slug>
│   ├── install.sh  uninstall.sh  verify.sh      uninstall reverts to stock Breeze
│   ├── retint.sh   colorscheme.sh  opacity.sh  whichbg.sh
│   └── icons.sh    gtk.sh          buttons.sh
├── lib/common.sh                 variant resolution, paths, output helpers
├── variants/
│   ├── light/
│   │   ├── variant.env           THE ONLY file where light differs from dark
│   │   ├── aurorae/QuantumLight/           -> ~/.local/share/aurorae/themes/
│   │   │   ├── metadata.json               KPackageStructure: aurorae  (generated)
│   │   │   ├── metadata.desktop            legacy, harmless on Plasma 6  (generated)
│   │   │   ├── QuantumLightrc              layout + text colours (name must match the dir)
│   │   │   ├── LICENSE                     GPLv3, from upstream
│   │   │   └── *.svg                       8 files, jomada's artwork, frame retinted
│   │   ├── plasma/desktoptheme/QuantumLight/   -> ~/.local/share/plasma/desktoptheme/
│   │   │   ├── plasmarc                    FallbackTheme=default, blur, contrast
│   │   │   ├── widgets/panel-background.svg    65%
│   │   │   ├── widgets/{background,tooltip}.svg  75%
│   │   │   ├── widgets/plasmoidheading.svg     header-*/footer-*, 3% tint
│   │   │   ├── dialogs/background.svg          75%  (margins must match ^)
│   │   │   └── translucent/{dialogs,widgets}/… the same four, used while blur is on
│   │   ├── look-and-feel/QuantumLight/     -> ~/.local/share/plasma/look-and-feel/
│   │   │   ├── metadata.json               (generated)
│   │   │   └── contents/{defaults,previews/}   defaults is generated
│   │   ├── gtk/QuantumLight-gtk.tar.gz     prebuilt GTK2/3/4 theme
│   │   └── *.sh                            symlinks into ../../bin/
│   └── dark/                               the same shape, QuantumDark
├── packaging/
│   ├── stamp-metadata.py         generates every metadata/defaults file; --check in CI
│   └── make-release.sh           builds the store tarballs and the source tarball
├── tests/
│   ├── run-tests.sh              static gates, then the unit suites
│   ├── run-unit-tests.sh         the unit suites alone
│   └── unit/                     harness.sh plus eight test_*.sh, 255 checks
└── install.sh  uninstall.sh  verify.sh    thin wrappers over bin/
```

The Slot icon themes are NOT in this tree — `bin/icons.sh` fetches them.

No `colors` file in the Plasma style, on purpose: without one Plasma follows the system
colour scheme, which is what keeps each variant in step with its Breeze base.

No `contents/layouts/`: Moe's own look-and-feel ships a desktop layout, and applying a
global theme that carries one replaces your panels. Leaving it out makes these themes
appearance-only.

## Install

```bash
bin/verify.sh    --variant dark          # read-only: shows current state, changes nothing
bin/icons.sh     --variant dark          # fetch the icon theme first - --apply refuses without it
bin/colorscheme.sh --variant dark --diff # preview the Header fix (--apply applies it)
bin/install.sh   --variant dark          # copies all three packages, applies nothing
bin/install.sh   --variant dark --apply  # backs up appearance keys, applies, clears the SVG
                                         # cache, enables KWin blur if it was off, restarts
                                         # plasmashell, syncs the GTK/portal preference
bin/verify.sh    --variant dark          # confirm
```

Then set the panel to Opacity → Translucent by hand, as above.

Equivalent, if you prefer the old muscle memory — each variant directory carries symlinks
and infers the variant from the path:

```bash
cd variants/dark && ./install.sh --apply
```

`QUANTUM_VARIANT=dark` in the environment works too.

### Rollback

`bin/uninstall.sh --variant dark` reverts to **KDE's own stock global theme** —
`org.kde.breezedark.desktop` for the dark variant, `org.kde.breeze.desktop` for light,
resolved against what the host actually has — and then removes that variant's packages.
The icon theme is left in place.

That is one `plasma-apply-lookandfeel` call, and KDE's package sets its own colour
scheme, widget style, Plasma style, decoration and cursors from its own
`contents/defaults`. **Stated plainly: if you had a third-party global theme or a
hand-built colour scheme before installing this, stock Breeze is not where you were.**

`install.sh --apply` still records eleven appearance keys into
`~/.local/state/quantum-<slug>/backup-<stamp>.env` before changing anything, alongside
timestamped copies of `kdeglobals`, `kwinrc`, `plasmarc` and `kcminputrc`. Two ways back:

```bash
bin/uninstall.sh --variant dark                   # stock Breeze - the default
bin/uninstall.sh --variant dark --restore-backup  # replay the recorded keys, best-effort
```

Reverting to stock is the default because replaying the backup is where every rollback
defect found on `quantum` came from. The backup can name the variant being deleted
(applying dark while dark is live records `OLD_LNF=QuantumDark`, and restoring that then
deleting the packages left KWin logging `Could not find decoration svg for
"QuantumDark"`); it can name something since removed; and with both variants installed
"what was there before" is ambiguous, since light's backup records dark. Two of the
eleven keys were also captured and never written back, so an uninstall deleted
`<ID>.colors` while leaving `kdeglobals` pointing at it.

Copying one of the timestamped config files back is the most reliable rollback available
— a file copy beats replaying eleven keys — and `--restore-backup` warns that it is
best-effort before it starts.

Applying from System Settings works too, but if the KCM offers to apply a desktop layout,
decline it. These packages ship none.

## How the variants stay in step

The two variants were forked packages — `quantum-light` and `quantum-dark`, each a
self-contained copy. Self-containment cost 92 KB of duplicated bash across ten scripts
whose only differences were a palette name and an id, and it was already failing:

| defect found at merge | cause |
|---|---|
| dark's look-and-feel described itself as "Breeze Light throughout" | copy-paste from light |
| dark's Plasma style, same | copy-paste from light |
| both Aurorae packages claimed "SVG artwork unmodified" | written before `retint.sh` existed; `decoration.svg` has 16 substitutions |
| Aurorae `Version` 1.9 against 1.0 everywhere else | bumped in one package only |
| `buttons.sh` reached into `../quantum-dark/` by relative path | the variants were never really independent |

So the fork is gone. What replaced it:

- **`variants/<slug>/variant.env` is the only place a variant differs.** Nine keys. The
  scripts in `bin/` contain no variant name, no palette source, no icon theme.
  `tests/run-tests.sh` greps for those literals and fails if one reappears.
- **Generated, not written twice.** `packaging/stamp-metadata.py` produces all six
  `metadata.json` files, both `metadata.desktop` files and both `contents/defaults` from
  `VERSION` plus `variant.env`. Descriptions come from one template per package kind, so
  a description can no longer name the wrong variant. `--check` is a CI gate.
- **`buttons.sh` enumerates variants** rather than knowing about a sibling directory, so
  it still writes every `auroraerc` group — which is the behaviour the per-theme KDE
  setting demands — without either variant depending on the other's path.
- **Tree parity is asserted.** The test suite compares the file sets of every variant
  with the id substituted out, because the forked copies had lost files from one side
  before.

## Tests

```bash
tests/run-tests.sh               # static gates, then the unit suites
tests/run-tests.sh --static-only # lint, shape, licensing, generated-file freshness
tests/run-unit-tests.sh          # the unit suites alone
tests/run-unit-tests.sh uninstall    # one suite by name
tests/run-unit-tests.sh --list   # what there is
```

**255 checks across eight suites, no dependencies beyond bash and python3.** No Plasma
session, no root, and safe to run on a desktop that is currently using the theme.

Each suite gets a sandbox: a throwaway `$HOME` with its own XDG directories, a fake
`/usr/share` seeded with the real Breeze colour values measured on `quantum`, stub KDE
binaries that record every call, and a private copy of this repo — because `retint.sh`,
`opacity.sh` and `buttons.sh --base` all edit the source tree by design.

The stubs are not no-ops. `kreadconfig6` and `kwriteconfig6` read and write real
KConfig INI files where KDE puts them, because `buttons.sh` and `verify.sh` both *call*
`kwriteconfig6` and then *parse the resulting file themselves*; a stub that kept values
anywhere else would let those parses silently find nothing. `plasma-apply-lookandfeel`
applies the package's own `contents/defaults`, so an install-then-verify test exercises
the real data files rather than asserting that a command was called.

| suite | what it pins down |
|---|---|
| `variant_resolution` | all four ways a variant is chosen, and every way of refusing to guess |
| `colorscheme` | Header pulled to Window in both directions, idempotence, `--diff` writing nothing, and that the values come from the installed scheme rather than a constant |
| `retint` | the 16 frame substitutions, idempotence, and that bad input leaves the artwork untouched |
| `opacity` | the five SVGs, the `translucent/` copies, and the stacked Kickoff arithmetic — 75% + a 3% tint is 75.8%, not 78% |
| `buttons` | the documented pixel table, writing every variant by default, `--only`, `--sync`, and drift reporting |
| `install` | all three packages, the icon-theme refusal, the Plasma 6 gate, the applied state, the portal preference per variant, and that the backup never names the variant being installed |
| `uninstall` | reverting to the variant's stock theme, the fallback chain, the sibling surviving, `--restore-backup` refusing a self-referential backup, and a double round trip leaving no residue |
| `verify` | that a clean install has no failures, and that each verdict is about the right variant |

Several cases exist because the behaviour was once wrong on a live host, and those are
marked as such in the test files. The uninstall suite in particular encodes the three
defects the first real round trip found.

Three environment variables exist for the harness and are useful outside it:
`QUANTUM_ROOT` (run the scripts against a tree other than their own),
`QUANTUM_SYSTEM_DATA` (where the distribution's themes live, for prefixes other than
`/usr/share`) and `QUANTUM_RESTART_DELAY` (seconds between quitting and relaunching
plasmashell; the suite sets it to 0).

### In CI

`.github/workflows/ci.yml` runs on every pull request and on every push to `main` —
which is how a merge arrives — in two parallel jobs:

| job | needs | what it does |
|---|---|---|
| `static` | `shellcheck`, `reuse` | `tests/run-tests.sh --static-only`, with a step that fails if either linter is missing rather than letting the suite skip it |
| `unit` | nothing | `tests/run-unit-tests.sh` |

A `v*` tag additionally runs `release`, which requires both jobs, asserts that the tag
matches `VERSION`, and builds the artifacts with `make-release.sh` — which runs the
whole suite again, so the same gate covers the artifacts as the merge.

## Releases, and the KDE Store

```bash
packaging/make-release.sh --list    # the product map, builds nothing
packaging/make-release.sh           # runs tests/, then builds dist/
```

Store products are per **artifact type**, not per variant, so one repo and one tag
produce three product pages with two files each:

| store product | category | files |
|---|---|---|
| Quantum | Global Themes (Plasma 6) | `QuantumLight-lookandfeel-<ver>.tar.gz`, `QuantumDark-…` |
| Quantum | Plasma 6 Window Decorations | `QuantumLight-aurorae-<ver>.tar.gz`, `QuantumDark-…` |
| Quantum | Plasma 6 Themes | `QuantumLight-plasmastyle-<ver>.tar.gz`, `QuantumDark-…` |

Each tarball has a single top-level directory named after the package id, which is what
KNewStuff and the KCMs unpack into `~/.local/share/`.

**The limitation to state on every product page, first line.** A global theme installed
through *Get New Global Themes* lands only in `~/.local/share/plasma/look-and-feel/`.
KNewStuff resolves no dependencies, so it will not fetch the Aurorae decoration, the
Plasma style or the Slot icons. One-click install of the Global Theme product alone gives
a user a look-and-feel pointing at three things they do not have. The store is for
discovery; `dist/quantum-theme-<ver>.tar.gz` plus `bin/install.sh` is the install path.

Upload is manual — `store.kde.org/product/add`, one product per category. There is no
supported publish API for third parties, so the GitHub release is the automated half and
the store pages are updated by hand.

## Known rough edges

- **Plasma 6.6 ignores button positions from global themes**
  ([WhiteSur-kde#130](https://github.com/vinceliuice/WhiteSur-kde/issues/130)): applying a
  look-and-feel writes `library` and `theme` but not `ButtonsOnLeft`/`ButtonsOnRight`.
  `install.sh --apply` writes them explicitly. Applying from System Settings instead:
  ```bash
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight IAX
  qdbus6 org.kde.KWin /KWin reconfigure
  ```
- **The config group is still `org.kde.kdecoration2`** on Plasma 6.6 despite the
  kdecoration3 plugin API. If a release renames it, `packaging/stamp-metadata.py` and
  `bin/install.sh` need updating together.
- **The Aurorae plugin id — measured on `quantum`, Plasma 6.6.6:**
  ```
  /usr/lib/x86_64-linux-gnu/qt6/plugins/org.kde.kdecoration3/org.kde.kwin.aurorae.so
  /usr/lib/x86_64-linux-gnu/qt6/plugins/org.kde.kdecoration3/org.kde.kwin.aurorae.v2.so
  ```
  **Both ids exist, and they live under `org.kde.kdecoration3`** while the config group
  is still `[org.kde.kdecoration2]`. The plugin directory moved to 3; the kwinrc group
  name did not. `contents/defaults` uses `.v2`, which is what KWin itself had written.

  **v2.0 had a bug here.** It read the id during pre-checks and wrote it back *after*
  `plasma-apply-lookandfeel`, clobbering the value the look-and-feel had just applied with
  a stale reading — a detection added to prevent a bug that became one. The fix: the
  explicit `kwriteconfig6` block writes **only** `ButtonsOnLeft`/`ButtonsOnRight`, the two
  keys Plasma 6.6 genuinely drops, and leaves `library` and `theme` to the look-and-feel
  that owns them. If the titlebar ever comes back as Breeze, check `library` first:
  ```bash
  kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key library
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae.v2
  qdbus6 org.kde.KWin /KWin reconfigure
  ```
- **The Plasma style's `metadata.json` has no `KPackageStructure`.** It mirrors Moe's
  Plasma 6 theme, which is known to load. Breeze's own may declare one. `verify.sh`
  checks whether `plasma-apply-desktoptheme --list-themes` actually sees the style, which
  is the test that matters.
- **A new Plasma style is invisible until the SVG cache is dropped.** `install.sh --apply`
  removes `~/.cache/plasma_theme_*.kcache` and restarts plasmashell. If the panel still
  looks like stock Breeze, that cache is the first thing to check.
- **Small titlebar.** `TitleHeight=15` plus 4px edges gives roughly a 23px titlebar with
  12px buttons — upstream Moe's geometry. Raise `TitleHeight` and
  `ButtonWidth`/`ButtonHeight` in `<ID>rc`, or use `bin/buttons.sh --base`.
- **No menu-button artwork.** Moe ships no `menu.svg`, so the `M` button falls back to
  the window icon. If that looks wrong, set `ButtonsOnLeft=` (empty) in
  `packaging/stamp-metadata.py` and re-stamp.
- **Content Credentials get injected on copy.** Copying files to this host through a file
  bridge signs every *image* with a C2PA provenance manifest — about 7.7 KiB of base64
  inside `<metadata>` in each SVG. Harmless to rendering (QSvg ignores `<metadata>`) but
  it bloats the files and, for the GPLv3 artwork, misstates what they are. Stripped, and
  `tests/run-tests.sh` fails if one comes back.
- **The preview images are composed, not screenshots.** Built from the real decoration
  and button SVGs at the real geometry, with a mocked window body. Replace
  `contents/previews/` with actual screenshots before publishing.

## Diagnosing "it looks opaque"

In order, cheapest first:

1. **Measure the colour** with a picker and compare against the variant's window
   background. Anything else means the surface is already translucent and something is
   hiding it — go to 2. Exactly equal means the theme is not being applied — go to 3.
2. **`[ContrastEffect]`** in the installed `plasmarc`. See above. This is the usual answer.
3. **`bin/whichbg.sh --variant <slug>`** paints every surface a different flat colour and
   reloads, so one look says which file Plasma resolved — or that it resolved none of ours.

   **Run `--restore` when you are done.** A forgotten test card is indistinguishable from
   a theme bug: on `quantum` it survived several rounds and surfaced later as bright green
   notification popups — `0.92 × 0xCC = 0xBB`, the exact green the script paints onto
   `translucent/dialogs/background.svg`. It drops a `.whichbg-active` marker and
   `verify.sh` shouts about it until you restore.

   | | |
   |---|---|
   | panel magenta / orange | the style is live |
   | launcher red | `dialogs/background.svg` |
   | launcher green | `translucent/dialogs/background.svg` |
   | launcher blue | `solid/dialogs/background.svg` |
   | unchanged | none of ours — Breeze's copies are in use |

   Notifications read `translucent/dialogs/background.svg`, so they are a good second
   surface to check — confirmed on `quantum`, where the launcher did not but they did.
4. **The SVG cache**: `rm -rf ~/.cache/plasma_theme_*.kcache` then
   `kquitapp6 plasmashell; plasmashell &`.

### Why `translucent/` is shipped twice

From libplasma, `ThemePrivate::updateKSvgSelectors()`:

```cpp
backgroundContrastActive = s_blurEffectWatcher->isEffectActive();
if (backgroundContrastActive) {
    kSvgImageSet->setSelectors({QStringLiteral("translucent")});
} else {
    kSvgImageSet->setSelectors({});
}
```

Whenever KWin's blur effect is active — the normal state, and the state this theme
*wants* — Plasma resolves four specific paths through a `translucent/` selector. A theme
that does not ship them loses those four surfaces to Breeze's copies. Breeze ships
exactly:

```
translucent/dialogs/background.svg
translucent/widgets/background.svg
translucent/widgets/panel-background.svg
translucent/widgets/tooltip.svg
```

and nothing else — `plasmoidheading.svg` is not selector-resolved, which is why the
Kickoff header tint worked while the sheet behind it did not. Both variants ship the same
four in both places: `translucent/` for the blur-on case, top-level for blur-off.
`opacity.sh` retunes both copies, and `verify.sh` fails if the set is incomplete or the
two copies drift apart.

## Licensing and upstream

Per-directory, declared in `REUSE.toml`.

| | licence | holder |
|---|---|---|
| `variants/*/aurorae/**` | GPL-3.0-or-later | jomada, modified by Valdemar Lemche |
| `variants/*/plasma/**` | LGPL-3.0-or-later | Valdemar Lemche; assets inherit from Breeze |
| `variants/*/gtk/**` | LGPL-3.0-or-later | generated by KDE's `breeze-gtk` |
| everything else | GPL-3.0-or-later | Valdemar Lemche |

The Aurorae artwork and the Plasma style are independent works that happen to ship
together — mere aggregation, not a combined work — so they keep their own licences.

**Moe** by jomada, GPLv3 — <https://gitlab.com/jomada/moe-theme>,
[KDE Store 1284575](https://store.kde.org/p/1284575/). These packages redistribute the
`aurorae/Moe` artwork with `decoration.svg` recoloured, under the same licence. `LICENSE`
and the attribution in `metadata.json` travel with it. Reproduce from a fresh clone with
`sed -i 's/#f7f9f9/<window colour>/g' decoration.svg`, or `bin/retint.sh`.

**Slot icon themes** by l4k1, GPLv3 — <https://github.com/L4ki/Slot-Plasma-Themes>,
[KDE Store 2234789](https://store.kde.org/p/2234789/). Not redistributed here;
`bin/icons.sh` fetches them from the author's repository.

The decoration installs as `QuantumLight`/`QuantumDark`, not `Moe`, so installing or
updating upstream Moe from the KDE Store cannot change your titlebars. The cost is that a
Moe update is a manual re-copy plus a re-run of `retint.sh`.
