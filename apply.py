#!/usr/bin/env python3
"""Read and persist Omarchy screensaver enablement, wait time, and video pause."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

HOME = Path(os.environ.get("HOME", str(Path.home())))
SHELL_JSON = HOME / ".config" / "omarchy" / "shell.json"
TOGGLE_FLAG = HOME / ".local" / "state" / "omarchy" / "toggles" / "screensaver-off"
STATE_FILE = HOME / ".local" / "state" / "omarchy" / "screensaver-panel.json"
DEFAULT_SECONDS = 150


def run(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, check=False, text=True, capture_output=True)


class ConfigError(Exception):
    """Existing config could not be loaded, so it must not be rewritten."""


def load_object(path: Path) -> dict:
    """Return a JSON object. A missing file is empty. Anything else is left untouched."""
    if not path.exists():
        return {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ConfigError(f"{path} could not be read ({exc}); leaving it unchanged") from exc
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"{path} is not valid JSON; leaving it unchanged") from exc
    if not isinstance(payload, dict):
        raise ConfigError(f"{path} is not a JSON object; leaving it unchanged")
    return payload


def read_json(path: Path) -> dict:
    try:
        return load_object(path)
    except ConfigError:
        return {}


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, indent=2) + "\n"
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def screensaver_enabled() -> bool:
    return not TOGGLE_FLAG.exists()


def set_enabled(enabled: bool) -> None:
    run(["omarchy-toggle", "screensaver-off", "off" if enabled else "on"])


def screensaver_seconds() -> int:
    idle = read_json(SHELL_JSON).get("idle")
    if not isinstance(idle, dict):
        return DEFAULT_SECONDS
    try:
        value = int(idle.get("screensaver", DEFAULT_SECONDS))
    except (TypeError, ValueError):
        return DEFAULT_SECONDS
    return max(60, min(1800, value))


def set_seconds(seconds: int) -> None:
    seconds = max(60, min(1800, int(seconds)))
    data = load_object(SHELL_JSON)
    idle = data.get("idle")
    if idle is None:
        idle = {}
        data["idle"] = idle
    elif not isinstance(idle, dict):
        raise ConfigError(f"{SHELL_JSON} key idle is not an object; leaving the file unchanged")
    idle["screensaver"] = seconds
    if "lock" not in idle:
        idle["lock"] = 300
    write_json(SHELL_JSON, data)


def pause_on_video() -> bool:
    state = read_json(STATE_FILE)
    if "pauseOnVideo" not in state:
        return True
    return bool(state.get("pauseOnVideo"))


def set_pause_on_video(enabled: bool) -> None:
    state = load_object(STATE_FILE)
    state["pauseOnVideo"] = bool(enabled)
    write_json(STATE_FILE, state)


def current_state() -> dict:
    return {
        "enabled": screensaver_enabled(),
        "seconds": screensaver_seconds(),
        "pauseOnVideo": pause_on_video(),
    }


def dismiss_screensaver() -> None:
    run(["pkill", "-f", "[o]rg.omarchy.screensaver"])


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        sys.stderr.write("usage: apply.py get | set-enabled <true|false> | set-seconds <n> | set-pause <true|false> | dismiss\n")
        return 2

    command = sys.argv[1]
    try:
        return dispatch(command)
    except ConfigError as exc:
        sys.stderr.write(f"{exc}\n")
        return 1


def dispatch(command: str) -> int:
    if command == "get":
        json.dump(current_state(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    if command == "set-enabled":
        if len(sys.argv) < 3:
            raise SystemExit("set-enabled requires true or false")
        set_enabled(sys.argv[2].lower() in ("true", "1", "yes", "on"))
        json.dump(current_state(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    if command == "set-seconds":
        if len(sys.argv) < 3:
            raise SystemExit("set-seconds requires an integer")
        set_seconds(int(float(sys.argv[2])))
        json.dump(current_state(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    if command == "set-pause":
        if len(sys.argv) < 3:
            raise SystemExit("set-pause requires true or false")
        set_pause_on_video(sys.argv[2].lower() in ("true", "1", "yes", "on"))
        json.dump(current_state(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    if command == "dismiss":
        dismiss_screensaver()
        json.dump(current_state(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    sys.stderr.write(f"unknown command: {command}\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
