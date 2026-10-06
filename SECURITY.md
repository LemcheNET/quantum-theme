# Security policy

## What this project is, in security terms

Two components with different trust levels. Keep them apart in your head, because the
second one is optional and nothing in the first depends on it.

### The desktop themes — `bin/`, `lib/`, `variants/`

SVG artwork, config files, a prebuilt GTK theme, and ten shell scripts that copy them
into place and set appearance keys.

- **No privileged code.** Nothing here runs as root or calls `sudo`, `pkexec` or
  `systemctl`. The only mentions of `sudo` are in messages telling *you* to install a
  distribution package. Nothing is setuid, and no systemd unit is installed.
- **No daemon and no listener.** Nothing runs in the background, nothing binds a port.
- **Per-user scope.** Everything is written under `$XDG_DATA_HOME`, `$XDG_CONFIG_HOME`,
  `$XDG_CACHE_HOME` and `$XDG_STATE_HOME` (by default `~/.local/share`, `~/.config`,
  `~/.cache`, `~/.local/state`). No system path is touched.
- **Two network paths**, both `git clone`, both opt-in. They are listed under
  *Known and accepted risks* below.

The realistic worst case here is not privilege escalation. It is third-party content
landing in your icon or theme path, or a delete aimed somewhere unintended.

### The Plymouth boot theme — `plymouth/` (optional, **runs as root**)

A boot splash. It has to be installed system-wide, because the splash is drawn from the
initramfs before any user exists, so these scripts are run with `sudo` and they:

- write `/usr/share/plymouth/themes/<name>/`
- edit `/etc/plymouth/plymouthd.conf` (`Theme=`) and the `default.plymouth` alternative
- edit `/etc/default/grub` (`GRUB_GFXMODE`, `GRUB_GFXPAYLOAD_LINUX`, optionally
  `GRUB_BACKGROUND` and `GRUB_CMDLINE_LINUX_DEFAULT`) and copy an image to
  `/boot/grub/`
- run `update-grub` and rebuild the initramfs for **every** installed kernel
- only if `prepare-boot-graphics.sh --apply` is run: append the display driver to
  `/etc/initramfs-tools/modules` and write one file under
  `/etc/initramfs-tools/conf.d/`

None of it reaches the network. State and rollback records live in
`/var/lib/quantum-plymouth/` (directory 0700, records 0600). The static gates fail if a
root-level operation ever appears outside `plymouth/`, so the per-user guarantee above
stays enforced rather than asserted.

The worst case here is different in kind: **a mistake affects booting, not only how the
desktop looks.** See risk 5 below.

## Supported versions

| version | supported |
|---|---|
| latest release | yes |
| anything older | no |

This is a single-maintainer project. Fixes go on top of `main` and into the next
release; there are no backports. If you are on an older tag, upgrading is the fix.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

1. **Preferred:** GitHub's private vulnerability reporting — the *Report a vulnerability*
   button under this repository's **Security** tab.
2. **Or email:** valdemar@lemche.net, with `quantum-theme` in the subject.

Useful in a report: which script and which version, what an attacker controls, and what
they achieve with it. A proof of concept against a throwaway user account is ideal — the
test harness in `tests/unit/` stands up a disposable `$HOME` and a fake `/usr/share`, so
a reproduction usually fits in one of those sandboxes without touching a real session.

**What you can expect.** This is a personal project, not a product. I will acknowledge a
report when I see it, and I would rather tell you a realistic date than quote an SLA I
cannot keep. If something is genuinely exploitable I will fix it ahead of everything else
here. If I conclude it is not a vulnerability I will say so and why, and you are free to
disagree in public. Credit in the release notes if you want it.

## What counts

**In scope**

- A path that escapes the per-user directories listed above, or a delete that reaches
  outside them.
- Command injection, or any execution of attacker-controlled content, through a
  filename, a variant name, an environment variable, or a colour-scheme or SVG file
  these scripts parse.
- A network path that fetches without the stated validation, or a change that makes one
  fetch silently.
- A path that writes a secret, token or credential anywhere, including into
  `~/.local/state/quantum-*/`. Nothing here should ever handle one.
- Anything that makes `uninstall.sh` fail to remove what it installed, or remove what it
  did not.
- For `plymouth/`: any write outside the paths listed above, a rollback record that
  restores the wrong state, or a way for an unprivileged user to influence what the
  root scripts write - through a path, a file in the checkout, or the environment.

**Out of scope**

- Cosmetic defects, wrong colours, a theme that does not apply. Those are ordinary
  issues — please file them.
- Bugs in KDE Plasma, KWin, Qt, Breeze or `kde-gtk-config`. Report those to KDE.
- Vulnerabilities in the upstream artwork projects themselves — jomada's Moe and l4k1's
  Slot. Report those to their authors; see `README.md` for links. If an upstream
  compromise changes how this project should fetch, that *is* in scope.
- The KDE Store listings and the opendesktop platform.
- "Running shell scripts from the internet is risky." True, and the whole repository is
  readable; `bin/verify.sh` changes nothing and is a reasonable first run.

## Known and accepted risks

These are design choices, documented rather than quietly carried. If one of them is
unacceptable for you, each has a way around it.

### 1. `bin/icons.sh` installs unpinned third-party content

It shallow-clones `github.com/L4ki/Slot-Plasma-Themes` at whatever `HEAD` is today — no
pinned commit, no signature — and copies 13,000–19,000 files into
`~/.local/share/icons/`. The only check is that `index.theme` carries the expected
`Name=`, and a mismatch is a warning rather than a refusal.

A compromise of that repository would place arbitrary SVGs and an `index.theme` in a
path Qt and GTK read. Icon rendering is a parser, and parsers have had CVEs.

**If you would rather not:** skip the script. Fetch the theme yourself, inspect it, and
install from your own copy with `bin/icons.sh --variant <slug> --from <dir>`, which does
no network access at all. Or install an icon theme from your distribution and change
`ICON_THEME` in `variants/<slug>/variant.env`.

### 2. `bin/gtk.sh --rebuild` executes third-party build code

It clones `invent.kde.org/plasma/breeze-gtk` — KDE's own, over HTTPS, also unpinned —
and runs its `build_theme.sh`. That is third-party code executing as you.

**If you would rather not:** the default path does not do this. `bin/gtk.sh` without
`--rebuild` unpacks the GTK theme already in the repository and reaches no network.
`--rebuild` exists only for hosts whose Breeze differs from the one the bundle was built
against.

### 3. The scripts trust the repository they run from

`variants/<slug>/variant.env` supplies the package id, and that id composes the paths
`uninstall.sh` deletes. Someone who can edit your clone can therefore aim those deletes.
This is the ordinary trust you extend to any checkout you run, stated explicitly because
the scripts delete things.

**Mitigations in place:** `lib/common.sh` refuses to proceed unless every required key
in `variant.env` is non-empty, so an id can never be blank and collapse a delete onto a
parent directory; `QUANTUM_ROOT` is validated to contain `lib/common.sh` and `variants/`
before it is trusted, so a stale value in your environment cannot redirect the scripts;
and deletes are confined to paths built from `$XDG_*` plus that id.

### 4. Releases are checksummed, not signed

`packaging/make-release.sh` writes `dist/SHA256SUMS`, and the tarballs are reproducible
(fixed mtime, sorted names, no uid/gid), so two builds of one tag match. But nothing is
GPG-signed and the tags are not signed either. The checksums tell you a download was not
corrupted; they do not prove who built it.

**If that matters to you:** build from a tag yourself — `packaging/make-release.sh`
produces byte-identical artifacts.

### 5. `plymouth/` edits the bootloader configuration and rebuilds every initramfs

A wrong GRUB key, a failed initramfs rebuild or a broken theme does not make the
machine unbootable in the usual case — the kernel and the system still start, and a
missing splash falls back to text — but it is boot-path configuration, edited as root,
and that deserves more caution than anything else here.

**Mitigations in place:** every run copies `/etc/default/grub` and `plymouthd.conf` to
a timestamped snapshot first; `--dry-run` prints every key and file it would change; the
first install records the original values, and the installer refuses to start if that
record would name the theme being installed; after rebuilding, it checks that the theme
is inside every initrd and exits non-zero, telling you not to reboot, if it is not.

**Not yet verified:** `plymouth/uninstall.sh` has only ever been run with `--dry-run`.
The renamed, driver-aware version of the whole component has not run on hardware. Keep
the snapshots in `/var/lib/quantum-plymouth/backups/` until you have rebooted once
after any change.

**If you would rather not:** skip `plymouth/` entirely. Nothing else depends on it.

## Hardening, if you want it

- `bin/verify.sh` is read-only. Run it first, and after anything else.
- `bin/install.sh` without `--apply` copies files and changes no settings.
- `bin/install.sh --apply` records your previous appearance settings to
  `~/.local/state/quantum-<slug>/`, including timestamped copies of `kdeglobals`,
  `kwinrc`, `plasmarc` and `kcminputrc`. Copying one of those back is the most reliable
  rollback available.
- `bin/uninstall.sh` reverts to KDE's stock Breeze and removes only this theme's own
  packages.
- Nothing here needs network access except the two scripts named above. Running the rest
  offline is fine.
- `plymouth/` is the only part that needs root, and it is optional. Every script there
  takes `--dry-run`; read that plan before running it for real.
