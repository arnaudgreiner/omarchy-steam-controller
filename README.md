# Steam Controller for Omarchy

Use a [Steam Controller](https://en.wikipedia.org/wiki/Steam_Controller) as a
desktop input device on Omarchy (Hyprland / Wayland), and configure its
bindings from the bar.

- 🎮 Bar widget showing the controller status (dims when disconnected).
- Bind controller buttons to **keyboard combos** (e.g. `Super + C`) or to
  **app launches** (`omarchy launch browser`, any shell command).
- Browse and switch between sc-controller profiles, with a live readout of
  what each profile has bound.
- The Steam/guide button opens Steam; profile selection lives in the widget
  instead of the on-screen menu.

It is powered by [sc-controller](https://github.com/C0rn3j/sc-controller), a
user-mode driver that emulates mouse/keyboard/gamepad through `uinput`, which
is why desktop input works under Wayland where Steam Input's X11 emulation
does not.

## Requirements

- Omarchy with the Quattro shell (Hyprland).
- The `sc-controller` package (available in the Arch and Omarchy repositories).
- The Steam Controller paired to its wireless USB dongle (or connected by
  cable).

## Installation

```bash
omarchy plugin add https://github.com/arnaudgreiner/omarchy-steam-controller
```

Then enable the widget in the bar:

```bash
omarchy plugin enable io.github.arnaudgreiner.steam-controller --section right
```

## Usage

1. Click the 🎮 icon in the bar to open the configuration panel.
2. **Profile** — pick a profile and press *Activer le profil* (or just read
   what is already bound in each profile).
3. **Nouveau binding** — choose an input, an action type, and a value, then
   press *Enregistrer*.
4. Press *Appliquer* to regenerate and activate the `Omarchy` profile.

The sc-controller daemon must be running for the controller to work. Pressing
*Appliquer* starts it if needed. To start it automatically at login, add this
to your Hyprland autostart (`~/.config/hypr/autostart.lua`):

```lua
o.exec_on_start("scc-daemon start")
```

### Binding types

| Type | Example | Effect |
|------|---------|--------|
| Combo clavier | `super c` | Sends `Super + C` (an Omarchy keybinding) |
| App (commande) | `alacritty -e htop` | Runs a raw shell command |
| App (omarchy launch) | `browser` | Runs `omarchy launch browser` |

Accepted keys: `super`/`meta`/`win`, `ctrl`, `shift`, `alt`, letters `a-z`,
digits `0-9`, `f1`-`f12`, `enter`, `space`, `tab`, `esc`, arrows, `home`,
`end`, `pageup`/`pagedown`, `delete`, `insert`, `backspace`, punctuation, or
raw `KEY_*` names.

## Notes

- The Steam button launches Steam. When Steam is running it takes over the
  controller (normal behaviour); quit Steam to return to desktop input.
- Bindings are stored in `~/.config/omarchy/steam-controller/bindings.json`.
- The generated profile is written to `~/.config/scc/profiles/Omarchy.sccprofile`.
- No privileged access is required.

## Removal

```bash
omarchy plugin remove io.github.arnaudgreiner.steam-controller
```

User data left behind (safe to delete manually if desired):

- `~/.config/omarchy/steam-controller/`
- `~/.config/scc/profiles/Omarchy.sccprofile`

## License

[MIT](LICENSE)
