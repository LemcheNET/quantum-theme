#!/usr/bin/env bash
# gtk-follow.sh keeps gtk-theme in step with color-scheme. The failure it exists for is
# silent - GTK3 apps just stay on the old variant - so the cases worth pinning are the
# mapping, the no-op paths (nothing to do must mean nothing written) and the watch loop.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/harness.sh"
sandbox_up; trap sandbox_down EXIT
# The gsettings stub keeps its store under $SANDBOX, and runs as a child process.
export SANDBOX

S=org.gnome.desktop.interface
set_gs()  { "$SANDBOX/bin/gsettings" set "$S" "$1" "$2" >/dev/null; : > "$CALL_LOG"; }
get_gs()  { "$SANDBOX/bin/gsettings" get "$S" "$1" | tr -d "'"; }
install_themes() { mkdir -p "$XDG_DATA_HOME/themes/QuantumLight" "$XDG_DATA_HOME/themes/QuantumDark"; }
install_icons()  { mkdir -p "$XDG_DATA_HOME/icons/Slot-Light-Icons" "$XDG_DATA_HOME/icons/Slot-Dark-Icons"; }
SET_THEME="gsettings set $S gtk-theme"
SET_ICONS="gsettings set $S icon-theme"
install_icons

describe "the preference picks the variant that declares it"
install_themes
set_gs color-scheme prefer-light; set_gs gtk-theme QuantumDark
out="$(run gtk-follow.sh --once)"
assert_eq "exit 0" 0 "$(status)"
assert_eq "light preference sets the light theme" QuantumLight "$(get_gs gtk-theme)"
assert_contains "and says what changed" "$out" "QuantumDark -> QuantumLight"

set_gs color-scheme prefer-dark; set_gs gtk-theme QuantumLight
run gtk-follow.sh --once >/dev/null
assert_eq "dark preference sets the dark theme" QuantumDark "$(get_gs gtk-theme)"

describe "nothing to do means nothing written"
set_gs color-scheme prefer-dark; set_gs gtk-theme QuantumDark
run gtk-follow.sh --once >/dev/null
assert_not_called "already in step: no gtk-theme write" "$SET_THEME"

set_gs color-scheme default; set_gs gtk-theme Adwaita
out="$(run gtk-follow.sh --once)"
assert_not_called "an undeclared preference leaves the theme alone" "$SET_THEME"
assert_contains "and says why" "$out" "leaving the GTK theme alone"

describe "a theme that is not installed is not selected"
rm -rf "$XDG_DATA_HOME/themes/QuantumLight"
set_gs color-scheme prefer-light; set_gs gtk-theme QuantumDark
out="$(run gtk-follow.sh --once)"
assert_eq "still exits 0" 0 "$(status)"
assert_not_called "no write: a missing theme would fall back to Adwaita" "$SET_THEME"
assert_contains "points at gtk.sh" "$out" "bin/gtk.sh --variant light"
install_themes

describe "settings files already present are kept current, absent ones are not created"
mkdir -p "$XDG_CONFIG_HOME/gtk-3.0"
printf '[Settings]\ngtk-theme-name=QuantumDark\ngtk-application-prefer-dark-theme=1\n' > "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
set_gs color-scheme prefer-light; set_gs gtk-theme QuantumDark
run gtk-follow.sh --once >/dev/null
ini="$(cat "$XDG_CONFIG_HOME/gtk-3.0/settings.ini")"
assert_contains "gtk-3.0 theme name follows" "$ini" "gtk-theme-name=QuantumLight"
assert_contains "gtk-3.0 prefer-dark flag follows" "$ini" "gtk-application-prefer-dark-theme=0"
assert_no_file "gtk-4.0/settings.ini is not created" "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
assert_no_file "~/.gtkrc-2.0 is not created" "$HOME/.gtkrc-2.0"

describe "the icon theme follows the variant too"
set_gs color-scheme prefer-dark; set_gs gtk-theme QuantumDark; set_gs icon-theme Slot-Light-Icons
out="$(run gtk-follow.sh --once)"
assert_eq "dark preference sets the dark icons" Slot-Dark-Icons "$(get_gs icon-theme)"
assert_contains "and says what changed" "$out" "Slot-Light-Icons -> Slot-Dark-Icons"
assert_not_called "the theme was already right: no gtk-theme write" "$SET_THEME"
: > "$CALL_LOG"
run gtk-follow.sh --once >/dev/null
assert_not_called "icons already in step: no icon-theme write" "$SET_ICONS"
printf '[Settings]\ngtk-theme-name=QuantumDark\ngtk-icon-theme-name=Slot-Dark-Icons\n' > "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
set_gs color-scheme prefer-light; set_gs icon-theme Slot-Dark-Icons
run gtk-follow.sh --once >/dev/null
assert_contains "gtk-3.0 icon theme name follows" "$(cat "$XDG_CONFIG_HOME/gtk-3.0/settings.ini")" "gtk-icon-theme-name=Slot-Light-Icons"
rm -rf "$XDG_DATA_HOME/icons/Slot-Dark-Icons"
set_gs color-scheme prefer-dark; set_gs icon-theme Slot-Light-Icons
out="$(run gtk-follow.sh --once)"
assert_eq "missing icons: still exits 0" 0 "$(status)"
assert_not_called "missing icons are not selected" "$SET_ICONS"
assert_contains "and it points at icons.sh" "$out" "bin/icons.sh --variant dark"
install_icons

describe "--check reports and changes nothing"
set_gs color-scheme prefer-light; set_gs gtk-theme QuantumLight; set_gs icon-theme Slot-Light-Icons
out="$(run gtk-follow.sh --check)"
assert_eq "in step: exit 0" 0 "$(status)"
assert_contains "in step: says so" "$out" "follows color-scheme"
set_gs gtk-theme QuantumDark
out="$(run gtk-follow.sh --check)"
assert_eq "out of step: exit 1" 1 "$(status)"
assert_contains "out of step: names the expected theme" "$out" "QuantumLight"
set_gs gtk-theme QuantumLight; set_gs icon-theme Slot-Dark-Icons
out="$(run gtk-follow.sh --check)"
assert_eq "icons out of step: exit 1" 1 "$(status)"
assert_contains "icons out of step: names the expected icons" "$out" "Slot-Light-Icons"
assert_not_called "--check never writes" "$SET_THEME"
assert_not_called "--check never writes icons" "$SET_ICONS"

describe "watch mode re-applies when the preference changes"
# A shim ahead of the stub on PATH: `monitor` flips the preference and prints one change
# line, the way the real one would when Plasma switches; everything else is the stub.
mkdir -p "$SANDBOX/shim"
cat > "$SANDBOX/shim/gsettings" <<SHIM
#!/usr/bin/env bash
if [[ "\${1:-}" == monitor ]]; then
  "$SANDBOX/bin/gsettings" set $S color-scheme prefer-dark >/dev/null
  echo "color-scheme: 'prefer-dark'"
  exit 0
fi
exec "$SANDBOX/bin/gsettings" "\$@"
SHIM
chmod +x "$SANDBOX/shim/gsettings"
set_gs color-scheme prefer-light; set_gs gtk-theme QuantumDark
out="$(PATH="$SANDBOX/shim:$PATH" run gtk-follow.sh)"
assert_contains "applied the starting preference" "$out" "QuantumDark -> QuantumLight"
assert_contains "applied the change it was told about" "$out" "QuantumLight -> QuantumDark"
assert_eq "ended on the dark theme" QuantumDark "$(get_gs gtk-theme)"
assert_eq "an ended monitor is a failure, so the unit restarts it" 1 "$(status)"

describe "the unit and the script agree"
unit="$QUANTUM_ROOT/systemd/quantum-gtk-follow.service"
assert_file "the unit template ships" "$unit"
assert_contains "it runs the script in bin/" "$(cat "$unit")" "@QUANTUM_ROOT@/bin/gtk-follow.sh"

describe "--install-service"
printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$CALL_LOG"\n' > "$SANDBOX/bin/systemctl"
chmod +x "$SANDBOX/bin/systemctl"; : > "$CALL_LOG"
out="$(run gtk-follow.sh --install-service)"
inst="$XDG_CONFIG_HOME/systemd/user/quantum-gtk-follow.service"
assert_eq "exit 0" 0 "$(status)"
assert_file "the unit lands in the user's systemd directory" "$inst"
assert_contains "ExecStart points at this tree's script" "$(cat "$inst")" "ExecStart=$QUANTUM_ROOT/bin/gtk-follow.sh --watch"
assert_not_contains "no placeholder is left behind" "$(cat "$inst")" "@QUANTUM_ROOT@"
assert_called "reloads the user manager" "systemctl --user daemon-reload"
assert_called "enables and starts the unit, for the user" "systemctl --user enable --now quantum-gtk-follow.service"
assert_not_contains "every systemctl call is --user" "$(calls | grep '^systemctl' | grep -v -- '--user')" "systemctl"

describe "--uninstall-service"
: > "$CALL_LOG"
run gtk-follow.sh --uninstall-service >/dev/null
assert_eq "exit 0" 0 "$(status)"
assert_no_file "the unit file is removed" "$inst"
assert_called "disables and stops it, for the user" "systemctl --user disable --now quantum-gtk-follow.service"
assert_not_contains "every systemctl call is --user" "$(calls | grep '^systemctl' | grep -v -- '--user')" "systemctl"

describe "a path containing sed's delimiter still installs correctly"
# The template is filled with parameter expansion, not sed, because a checkout under a
# path with a | or & in it would otherwise corrupt the unit.
odd="$SANDBOX/odd|&dir"; mkdir -p "$odd"; cp -a "$QUANTUM_ROOT"/. "$odd"/
QUANTUM_ROOT="$odd" run_cmd "$odd/bin/gtk-follow.sh" --install-service >/dev/null
assert_contains "ExecStart carries the odd path verbatim" "$(cat "$inst")" "ExecStart=$odd/bin/gtk-follow.sh"

finish
