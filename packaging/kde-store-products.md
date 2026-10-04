---
type: runbook
subject: Quantum global themes
artifact: KDE Store / opendesktop product definitions
status: unverified against the live form — https://www.opendesktop.org/product/add is behind robots.txt and a login, so the field list below is reconstructed from live product pages and maintainer threads, not from the form itself. Correct it on first upload.
owner: Valdemar Lemche
concepts: [KDE Store, opendesktop, pling, KNewStuff, product metadata]
tags: [kde, publishing, store, release]
sources:
  - https://store.kde.org/p/1284575
  - https://store.kde.org/p/1307867
  - https://discuss.kde.org/t/how-to-upload-to-kde-store/36690
  - https://forum.opendesktop.org/t/what-is-the-correct-way-to-publish-a-plasmoid-widget-category/21255
date: 2026-10-04
---

# KDE Store product definitions

Upload form: <https://www.opendesktop.org/product/add> (same account and backend as
store.kde.org; the credentials work on both).

**Three products, not two and not six.** Store products are per *artifact type*, not per
variant, so one repo and one tag produce three product pages, each carrying one file per
variant. `packaging/make-release.sh --list` prints the same mapping from the code.

## The form's fields

| field | confirmed? | notes |
|---|---|---|
| Category | live pages | A dropdown. Pick it first — it decides which `Get New …` dialog in Plasma shows the product at all. Changeable afterwards via Edit on the product page. |
| Title | live pages | Shown in listings and in the KNewStuff dialog. |
| Summary | live pages | The one-liner under the title in browse listings. Distinct from the long description. |
| Description | live pages | Long, formatted. First line is what people read before deciding. |
| Version | live pages | Often left blank by others. Don't: a maintainer thread explicitly asks for semantic versioning here. |
| Licence | live pages | A dropdown; "GPLv3" is how it renders. |
| Tags | live pages | Compatibility tags — `plasma-6` and similar. Moe carries both `plasma-5` and `plasma-6`. |
| Changelog | live pages | Per-version notes. |
| Files | live pages | Several per product, each with its own label. Either uploaded or given as an external link. |
| Preview images | live pages | The first one is the listing thumbnail. |
| Source link | inferred | No dedicated field was visible; product pages carry a prompt to "add the source-code … on opencode.net", and the practice in the upload thread is to link GitHub from the description instead. |
| Video link | live pages | Optional YouTube URL. |

Not available: a source-code upload field, and any supported publish API for third
parties. Upload is manual, per product, by hand.

## Product 1 — Global Themes

| field | value |
|---|---|
| **Category** | `Global Themes (Plasma 6)` |
| **Title** | Quantum |
| **Summary** | One uninterrupted colour from titlebar to window body, with a translucent panel. Light and dark. |
| **Version** | 2.1.1 |
| **Licence** | GPL-3.0-or-later |
| **Tags** | `plasma-6` |
| **Files** | `QuantumLight-lookandfeel-2.1.1.tar.gz` — label: Quantum Light<br>`QuantumDark-lookandfeel-2.1.1.tar.gz` — label: Quantum Dark |

## Product 2 — Window Decorations

| field | value |
|---|---|
| **Category** | `Plasma 6 Window Decorations` |
| **Title** | Quantum |
| **Summary** | jomada's Moe decoration, retinted so the titlebar is the same colour as the window body. |
| **Version** | 2.1.1 |
| **Licence** | GPL-3.0-or-later |
| **Tags** | `plasma-6` |
| **Files** | `QuantumLight-aurorae-2.1.1.tar.gz` — label: Quantum Light<br>`QuantumDark-aurorae-2.1.1.tar.gz` — label: Quantum Dark |

**This product redistributes someone else's GPLv3 artwork.** The description must credit
jomada and link upstream, and the licence field must say GPLv3 — see *Attribution* below.

## Product 3 — Plasma Styles

| field | value |
|---|---|
| **Category** | `Plasma 6 Themes` |
| **Title** | Quantum |
| **Summary** | A thin translucent layer over Breeze: panel at 65%, popups and tooltips at 75%. |
| **Version** | 2.1.1 |
| **Licence** | LGPL-3.0-or-later |
| **Tags** | `plasma-6` |
| **Files** | `QuantumLight-plasmastyle-2.1.1.tar.gz` — label: Quantum Light<br>`QuantumDark-plasmastyle-2.1.1.tar.gz` — label: Quantum Dark |

## The first line of every description

Paste this at the top of all three, before anything else. It is the single most useful
sentence on the page, because the store cannot deliver what it implies:

> **Installing from this page alone will not give you the full theme.** *Get New Global
> Themes* resolves no dependencies, so it installs only the look-and-feel package — not
> the Aurorae decoration, not the Plasma style, and not the icon theme. For the complete
> theme, download `quantum-theme-2.1.1.tar.gz` from
> <https://github.com/LemcheNET/quantum-theme/releases> and run
> `bin/install.sh --variant dark --apply` (or `--variant light`). The three store
> products here are for discovery and for anyone who wants one piece on its own.

## Shared description body

Then the substance, trimmed per product:

> Two Plasma 6 global themes that each make the titlebar, the toolbar beneath it and the
> window body a single uninterrupted colour, and make Plasma's own surfaces translucent.
> Stock Breeze underneath — this is a thin layer over it, not a fork of it.
>
> **What it sets**
>
> - Colour scheme derived from the installed Breeze at install time, with
>   `[Colors:Header]` forced to `[Colors:Window]` so Kirigami app toolbars stop
>   stepping away from the titlebar
> - Window decoration: jomada's Moe, retinted to the window background
> - Plasma style: panel 65%, popups, plasmoids and tooltips 75%
> - Icons: l4k1's Slot (a dependency, fetched by `bin/icons.sh` — 13k–19k files)
> - Application style: Breeze. Cursors: `breeze_cursors`
> - **No desktop layout**, so applying it does not touch your panels
>
> **What it deliberately does not do**
>
> - Panel opacity is a per-panel setting in Plasma 6 and overrides any style; set it to
>   Translucent yourself
> - Application windows (Dolphin, Kate) are out of scope — that needs Kvantum plus
>   kwin-effects-forceblur, which would replace Breeze
>
> Rollback reverts to KDE's stock Breeze: `bin/uninstall.sh --variant dark`.
>
> Targets Plasma 6.6 on Kubuntu 26.04. Source, full documentation and the
> install/uninstall scripts: <https://github.com/LemcheNET/quantum-theme>

## Attribution — required, not courtesy

Include in the **Window Decorations** description, and in the Global Themes description:

> Window decoration artwork is **Moe** by **jomada**, GPLv3, redistributed under the same
> licence with `decoration.svg` recoloured to match the window background. The other
> seven SVGs are unmodified. Upstream: <https://gitlab.com/jomada/moe-theme> ·
> <https://store.kde.org/p/1284575>
>
> The decoration installs under the id `QuantumLight`/`QuantumDark` rather than
> `Moe`, so installing or updating upstream Moe cannot change your titlebars.
>
> Icon themes are **Slot** by **l4k1**, GPLv3, not redistributed here —
> `bin/icons.sh` fetches them from the author's repository.
> <https://github.com/L4ki/Slot-Plasma-Themes> · <https://store.kde.org/p/2234789>

## Changelog for 2.1.1

> Consolidated the light and dark variants into one repository. Previously they were
> forked packages whose descriptions, versions and metadata had drifted apart.
>
> - Reverting now goes to KDE's stock Breeze by default, which removes a class of
>   rollback failure where the uninstaller restored a theme it was about to delete
> - The colour scheme, GTK theme and XDG-portal light/dark preference are kept in step
>   with the active variant
> - Titlebar button size is set across both variants at once, since Aurorae keys it
>   per theme and the two otherwise diverge silently
> - 255 automated checks run on every change
> - A security policy documenting the two scripts that reach the network, and full
>   REUSE licence compliance

## Per-release checklist

```bash
packaging/make-release.sh --list      # confirm the product/file mapping
packaging/make-release.sh             # runs the full suite, then builds dist/
```

Then, before touching the store:

- [ ] `dist/SHA256SUMS` exists and the tarball names match the tables above
- [ ] each per-package tarball has a **single top-level directory** named for the
      package id — that is what KNewStuff unpacks into `~/.local/share/`
- [ ] preview images are **real screenshots**, not the generated composites
- [ ] the GitHub release is published first, so the description's link resolves
- [ ] `VERSION`, the git tag and the Version field all agree

On each product page:

- [ ] category set before anything else
- [ ] the dependency warning is the first line of the description
- [ ] licence matches the table (GPLv3 for products 1 and 2, LGPLv3 for 3)
- [ ] both variant files attached, each labelled
- [ ] attribution block present on products 1 and 2
- [ ] changelog entry added
- [ ] GitHub link in the description

## Open before any of this

1. **The name.** There are existing Quantum-named products on the store and the product
   URLs are permanent. Settle it before the pages exist, not after.
2. **`VERSION` is 2.1.1.** 2.1.1 was tagged at a commit whose CI failed `reuse lint`,
   so its release job never ran. 2.1.1 is the first release that builds; nothing in
   the installed theme differs from 2.1.1.
3. **Previews.** Still generated composites. Both variants run correctly now, so this is
   a screenshot away.
