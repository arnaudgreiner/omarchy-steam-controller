#!/usr/bin/env python3
"""Omarchy Steam Controller plugin backend.

Manages desktop-mode bindings for the controller:
  - reads/writes ~/.config/omarchy/steam-controller/bindings.json
  - generates an sc-controller profile (~/.config/scc/profiles/Omarchy.sccprofile)
  - applies the profile with `scc set-profile Omarchy`

Supported binding types:
  combo <KEY1 KEY2 ...>   -> simultaneous key presses (e.g. Super C)
  app <command>           -> runs a raw shell command
  launch <app>            -> runs `omarchy launch <app>`

Usage:
  backend.py status
  backend.py list-inputs
  backend.py list-keys
  backend.py get
  backend.py bind <input> combo <KEY1> [KEY2 ...]
  backend.py bind <input> app <command...>
  backend.py bind <input> launch <app>
  backend.py bind <input> clear
  backend.py apply
"""

import json
import os
import re
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_DIR = os.path.join(HOME, ".config", "omarchy", "steam-controller")
BINDINGS_FILE = os.path.join(CONFIG_DIR, "bindings.json")
SCC_PROFILES_DIR = os.path.join(HOME, ".config", "scc", "profiles")
PROFILE_NAME = "Omarchy"
PROFILE_FILE = os.path.join(SCC_PROFILES_DIR, PROFILE_NAME + ".sccprofile")

# Buttons exposed for binding (JSON keys of the sc-controller profile).
INPUTS = [
    "A", "B", "X", "Y",
    "LB", "RB",
    "BACK", "START", "C",
    "LPAD", "RPAD",
    "LGRIP", "RGRIP",
    "LT", "RT",
    "LSTICKPRESS", "RSTICKPRESS",
]

INPUT_LABELS = {
    "A": "A", "B": "B", "X": "X", "Y": "Y",
    "LB": "Left bumper", "RB": "Right bumper",
    "BACK": "Back", "START": "Start", "C": "Steam button",
    "LPAD": "Left pad press", "RPAD": "Right pad press",
    "LGRIP": "Left grip", "RGRIP": "Right grip",
    "LT": "Left trigger", "RT": "Right trigger",
    "LSTICKPRESS": "Left stick press", "RSTICKPRESS": "Right stick press",
}

# Noms conviviaux -> constantes Keys du parseur sc-controller.
KEY_ALIASES = {
    "super": "KEY_LEFTMETA", "meta": "KEY_LEFTMETA", "win": "KEY_LEFTMETA",
    "ctrl": "KEY_LEFTCTRL", "control": "KEY_LEFTCTRL",
    "shift": "KEY_LEFTSHIFT",
    "alt": "KEY_LEFTALT",
    "enter": "KEY_ENTER", "return": "KEY_ENTER",
    "esc": "KEY_ESC", "escape": "KEY_ESC",
    "space": "KEY_SPACE",
    "tab": "KEY_TAB",
    "backspace": "KEY_BACKSPACE",
    "up": "KEY_UP", "down": "KEY_DOWN", "left": "KEY_LEFT", "right": "KEY_RIGHT",
    "home": "KEY_HOME", "end": "KEY_END",
    "pageup": "KEY_PAGEUP", "pagedown": "KEY_PAGEDOWN",
    "delete": "KEY_DELETE", "del": "KEY_DELETE", "insert": "KEY_INSERT",
    "minus": "KEY_MINUS", "equal": "KEY_EQUAL",
    "comma": "KEY_COMMA", "dot": "KEY_DOT", "slash": "KEY_SLASH",
    "semicolon": "KEY_SEMICOLON", "apostrophe": "KEY_APOSTROPHE",
    "grave": "KEY_GRAVE", "backslash": "KEY_BACKSLASH",
    "leftbrace": "KEY_LEFTBRACE", "rightbrace": "KEY_RIGHTBRACE",
    "capslock": "KEY_CAPSLOCK", "numlock": "KEY_NUMLOCK",
    "menu": "KEY_MENU", "compose": "KEY_COMPOSE",
    "print": "KEY_SYSRQ", "pause": "KEY_PAUSE",
}
for _i in range(1, 13):
    KEY_ALIASES["f%d" % _i] = "KEY_F%d" % _i
for _c in "abcdefghijklmnopqrstuvwxyz":
    KEY_ALIASES[_c] = "KEY_" + _c.upper()
for _d in "0123456789":
    KEY_ALIASES[_d] = "KEY_" + _d

KEY_DISPLAY = {
    "KEY_LEFTMETA": "Super", "KEY_RIGHTMETA": "Super(D)",
    "KEY_LEFTCTRL": "Ctrl", "KEY_RIGHTCTRL": "Ctrl(D)",
    "KEY_LEFTSHIFT": "Shift", "KEY_RIGHTSHIFT": "Shift(D)",
    "KEY_LEFTALT": "Alt", "KEY_RIGHTALT": "AltGr",
    "KEY_ENTER": "Enter", "KEY_ESC": "Esc",
    "KEY_SPACE": "Space", "KEY_TAB": "Tab",
    "KEY_BACKSPACE": "Backspace",
    "KEY_UP": "↑", "KEY_DOWN": "↓", "KEY_LEFT": "←", "KEY_RIGHT": "→",
    "KEY_HOME": "Home", "KEY_END": "End",
    "KEY_PAGEUP": "PgUp", "KEY_PAGEDOWN": "PgDn",
    "KEY_DELETE": "Del", "KEY_INSERT": "Ins",
    "KEY_CAPSLOCK": "CapsLock", "KEY_NUMLOCK": "NumLock",
    "KEY_MINUS": "-", "KEY_EQUAL": "=", "KEY_COMMA": ",",
    "KEY_DOT": ".", "KEY_SLASH": "/", "KEY_SEMICOLON": ";",
    "KEY_APOSTROPHE": "'", "KEY_GRAVE": "`", "KEY_BACKSLASH": "\\",
    "KEY_LEFTBRACE": "[", "KEY_RIGHTBRACE": "]",
    "BTN_LEFT": "Clic gauche", "BTN_RIGHT": "Clic droit", "BTN_MIDDLE": "Clic molette",
}


def key_display(name):
    if name in KEY_DISPLAY:
        return KEY_DISPLAY[name]
    if name.startswith("KEY_F") and name[4:].isdigit():
        return name[4:]
    if name.startswith("KEY_") and len(name) == 5 and name[4:].isalnum():
        return name[4:]
    return name


def describe_action(action):
    if not action:
        return "—"
    m = re.search(r"shell\(\s*[\"'](.*?)[\"']\s*\)", action)
    if m:
        return "Cmd: " + m.group(1)
    if "REL_WHEEL" in action or "REL_HWHEEL" in action:
        return "Scroll wheel"
    if "dpad(" in action:
        return "D-pad"
    keys = re.findall(r"Keys\.(KEY_[A-Z0-9_]+|BTN_[A-Z0-9_]+)", action)
    if keys:
        return " + ".join(key_display(k) for k in keys)
    if "menu(" in action:
        return "OSD menu"
    if "mouse(" in action:
        return "Mouse"
    if "keyboard()" in action:
        return "Keyboard"
    if "turnoff()" in action:
        return "Power off"
    return action.strip()[:50]

# Base profile: fixed Desktop (without the failing left haptics).
BASE_PROFILE = {
    "_": "",
    "buttons": {
        "A": {"action": "button(Keys.KEY_ENTER)"},
        "B": {"action": "button(Keys.KEY_ESC)"},
        "BACK": {"action": "button(Keys.KEY_BACKSPACE)"},
        "C": {"action": "shell(\"uwsm-app -- steam\")"},
        "CPADPRESS": {"action": "button(Keys.BTN_LEFT)"},
        "LB": {"action": "button(Keys.KEY_LEFTCTRL)"},
        "RB": {"action": "button(Keys.KEY_LEFTALT)"},
        "RPAD": {"action": "button(Keys.BTN_LEFT)"},
        "START": {"action": "button(Keys.KEY_LEFTSHIFT)"},
        "X": {"action": "button(Keys.KEY_SPACE)"},
        "Y": {"action": "button(Keys.KEY_TAB)"},
    },
    "cpad": {"action": "mouse()"},
    "gyro": {},
    "is_template": False,
    "menus": {},
    "pad_left": {"action": "ball(XY(mouse(Rels.REL_HWHEEL, 1.0), mouse(Rels.REL_WHEEL, 1.0)))"},
    "pad_right": {"action": "smooth(8, 0.78, 2.0, feedback(RIGHT, 256, ball(mouse())))"},
    "lstick": {"action": "dpad(button(Keys.KEY_UP), button(Keys.KEY_DOWN), button(Keys.KEY_LEFT), button(Keys.KEY_RIGHT))"},
    "rstick": {"action": "smooth(8, 0.78, 2.0, ball(mouse()))"},
    "trigger_left": {"action": "button(Keys.BTN_RIGHT)"},
    "trigger_right": {"action": "button(Keys.BTN_LEFT)"},
    "version": 1.6,
}


def load_bindings():
    if not os.path.exists(BINDINGS_FILE):
        return {"version": 1, "bindings": {}}
    try:
        with open(BINDINGS_FILE) as f:
            data = json.load(f)
        if "bindings" not in data:
            data["bindings"] = {}
        return data
    except (json.JSONDecodeError, OSError):
        return {"version": 1, "bindings": {}}


def save_bindings(data):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    tmp = BINDINGS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, BINDINGS_FILE)


def resolve_key(token):
    if token.startswith("KEY_"):
        return token
    k = KEY_ALIASES.get(token.lower())
    if k:
        return k
    return None


def action_for(binding):
    t = binding.get("type")
    if t == "combo":
        keys = []
        for tok in binding.get("keys", []):
            k = resolve_key(tok)
            if k is None:
                raise ValueError("Unknown key: %s" % tok)
            keys.append(k)
        if not keys:
            raise ValueError("Empty combo")
        parts = ["button(Keys.%s)" % k for k in keys]
        return " and ".join(parts)
    if t == "app":
        cmd = binding.get("command", "")
        if not cmd:
            raise ValueError("Missing command")
        return "shell(%s)" % json.dumps(cmd)
    if t == "launch":
        app = binding.get("app", "")
        if not app:
            raise ValueError("Missing app")
        return "shell(%s)" % json.dumps("omarchy launch %s" % app)
    raise ValueError("Unknown type: %s" % t)


def generate_profile():
    data = load_bindings()
    profile = json.loads(json.dumps(BASE_PROFILE))
    errors = []
    for inp, binding in data.get("bindings", {}).items():
        if inp not in INPUTS:
            errors.append("Input inconnu : %s" % inp)
            continue
        try:
            profile["buttons"][inp] = {"action": action_for(binding)}
        except ValueError as e:
            errors.append("%s : %s" % (inp, e))
    os.makedirs(SCC_PROFILES_DIR, exist_ok=True)
    tmp = PROFILE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(profile, f, indent=4)
        f.write("\n")
    os.replace(tmp, PROFILE_FILE)
    return profile, errors


def daemon_running():
    return os.path.exists(os.path.join(HOME, ".config", "scc", "daemon.pid"))


def controller_connected():
    try:
        out = subprocess.run(
            ["scc", "info"], capture_output=True, text=True, timeout=8
        ).stdout
        return "Controller Count: 1" in out
    except Exception:
        return False


def apply_profile():
    if not os.path.exists(PROFILE_FILE):
        generate_profile()
    if not daemon_running():
        subprocess.run(["scc-daemon", "start"], check=False)
    r = subprocess.run(["scc", "set-profile", PROFILE_NAME],
                       capture_output=True, text=True, timeout=15)
    return r.returncode, r.stdout + r.stderr


def current_profile_name():
    try:
        out = subprocess.run(
            ["scc", "info"], capture_output=True, text=True, timeout=8
        ).stdout
        for line in out.splitlines():
            if "Controller profile:" in line or "Current profile:" in line:
                rest = line.split(":", 1)[1].strip()
                path = rest.split()[-1]
                if path.endswith(".sccprofile"):
                    return os.path.basename(path)[:-len(".sccprofile")]
    except Exception:
        pass
    return None


def cmd_profiles():
    names = set()
    for d in (SCC_PROFILES_DIR, "/usr/share/scc/default_profiles"):
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith(".sccprofile") and not f.startswith("."):
                    names.add(f[:-len(".sccprofile")])
    print(json.dumps({"profiles": sorted(names), "current": current_profile_name()},
                     ensure_ascii=False))


def cmd_set_profile(args):
    if len(args) < 1:
        sys.stderr.write("Usage: backend.py set-profile <name>\n")
        return 2
    name = args[0]
    r = subprocess.run(["scc", "set-profile", name],
                       capture_output=True, text=True, timeout=15)
    if r.returncode == 0:
        print("OK profile %s" % name)
        return 0
    sys.stderr.write(r.stdout + r.stderr)
    return 1


PROFILE_INPUT_ORDER = [
    ("A", "A"), ("B", "B"), ("X", "X"), ("Y", "Y"),
    ("LB", "Left bumper"), ("RB", "Right bumper"),
    ("BACK", "Back"), ("START", "Start"), ("C", "Steam button"),
    ("LPAD", "Left pad press"), ("RPAD", "Right pad press"),
    ("LGRIP", "Left grip"), ("RGRIP", "Right grip"),
    ("LT", "Left trigger"), ("RT", "Right trigger"),
    ("LSTICKPRESS", "Left stick press"), ("RSTICKPRESS", "Right stick press"),
]

EXTRA_INPUT_ORDER = [
    ("pad_left", "Left pad (touch)"),
    ("pad_right", "Right pad (touch)"),
    ("lstick", "Left stick"),
    ("rstick", "Right stick"),
    ("trigger_left", "Left trigger (analog)"),
    ("trigger_right", "Right trigger (analog)"),
]


def find_profile_file(name):
    for d in (SCC_PROFILES_DIR, "/usr/share/scc/default_profiles"):
        p = os.path.join(d, name + ".sccprofile")
        if os.path.exists(p):
            return p
    return None


def cmd_profile_inputs(args):
    if len(args) < 1:
        sys.stderr.write("Usage: backend.py profile-inputs <name>\n")
        return 2
    name = args[0]
    path = find_profile_file(name)
    if not path:
        sys.stderr.write("Unknown profile: %s\n" % name)
        return 1
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception as e:
        sys.stderr.write("Read failed: %s\n" % e)
        return 1
    rows = []
    buttons = data.get("buttons", {})
    for inp, label in PROFILE_INPUT_ORDER:
        node = buttons.get(inp)
        action = node.get("action", "") if isinstance(node, dict) else ""
        rows.append({"input": inp, "label": label, "desc": describe_action(action)})
    for inp, label in EXTRA_INPUT_ORDER:
        node = data.get(inp)
        action = node.get("action", "") if isinstance(node, dict) else ""
        rows.append({"input": inp, "label": label, "desc": describe_action(action)})
    print(json.dumps({"profile": name, "inputs": rows}, ensure_ascii=False))
    return 0


def cmd_status():
    info = {
        "daemon": daemon_running(),
        "controller": controller_connected(),
        "profile": PROFILE_NAME,
        "profile_file": PROFILE_FILE,
        "bindings": load_bindings().get("bindings", {}),
        "inputs": INPUTS,
        "input_labels": INPUT_LABELS,
    }
    print(json.dumps(info, indent=2, ensure_ascii=False))


def cmd_list_inputs():
    for inp in INPUTS:
        print("%s\t%s" % (inp, INPUT_LABELS.get(inp, inp)))


def cmd_list_keys():
    keys = set(KEY_ALIASES.values())
    for k in sorted(keys):
        print(k)


def cmd_get():
    print(json.dumps(load_bindings(), indent=2, ensure_ascii=False))


def cmd_bind(args):
    if len(args) < 1:
        sys.stderr.write("Usage: backend.py bind <input> (combo|app|launch|clear) ...\n")
        return 2
    inp = args[0].upper()
    if inp not in INPUTS:
        sys.stderr.write("Unknown input: %s\n" % inp)
        return 1
    data = load_bindings()
    bindings = data.setdefault("bindings", {})
    if len(args) == 1:
        print(json.dumps(bindings.get(inp), ensure_ascii=False))
        return 0
    kind = args[1].lower()
    if kind == "clear":
        bindings.pop(inp, None)
        save_bindings(data)
        print("OK clear %s" % inp)
        return 0
    if kind == "combo":
        tokens = args[2:]
        for t in tokens:
            if resolve_key(t) is None:
                sys.stderr.write("Unknown key: %s\n" % t)
                return 1
        bindings[inp] = {"type": "combo", "keys": tokens}
    elif kind == "app":
        cmd = " ".join(args[2:])
        if not cmd:
            sys.stderr.write("Missing command\n")
            return 1
        bindings[inp] = {"type": "app", "command": cmd}
    elif kind == "launch":
        app = " ".join(args[2:])
        if not app:
            sys.stderr.write("Missing app\n")
            return 1
        bindings[inp] = {"type": "launch", "app": app}
    else:
        sys.stderr.write("Unknown type: %s\n" % kind)
        return 1
    save_bindings(data)
    print("OK bind %s -> %s" % (inp, json.dumps(bindings[inp], ensure_ascii=False)))
    return 0


def cmd_apply():
    try:
        profile, errors = generate_profile()
    except Exception as e:
        sys.stderr.write("Generation failed: %s\n" % e)
        return 1
    rc, output = apply_profile()
    if errors:
        for e in errors:
            sys.stderr.write("Warning: %s\n" % e)
    if rc == 0:
        print("OK profile %s applied (%s)" % (PROFILE_NAME, PROFILE_FILE))
        return 0
    sys.stderr.write(output)
    return 1


def main():
    args = sys.argv[1:]
    if not args:
        sys.stderr.write(__doc__)
        return 2
    cmd = args[0]
    if cmd == "status":
        cmd_status()
    elif cmd == "list-inputs":
        cmd_list_inputs()
    elif cmd == "list-keys":
        cmd_list_keys()
    elif cmd == "get":
        cmd_get()
    elif cmd == "bind":
        return cmd_bind(args[1:])
    elif cmd == "profiles":
        cmd_profiles()
    elif cmd == "profile-inputs":
        return cmd_profile_inputs(args[1:])
    elif cmd == "set-profile":
        return cmd_set_profile(args[1:])
    elif cmd == "apply":
        return cmd_apply()
    elif cmd == "generate":
        try:
            profile, errors = generate_profile()
            for e in errors:
                sys.stderr.write("Warning: %s\n" % e)
            print(PROFILE_FILE)
            return 0
        except Exception as e:
            sys.stderr.write("Error: %s\n" % e)
            return 1
    else:
        sys.stderr.write("Commande inconnue : %s\n" % cmd)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
