#!/usr/bin/env python3
"""Own org.freedesktop.ScreenSaver and report whether an Inhibit cookie is held.

Browsers ask xdg-desktop-portal to inhibit the screensaver while a video is
playing. The portal calls this well-known name. Nothing on this session owned
it, so those calls failed and Omarchy's idle timer still locked the screen.

This process only reports cookie state on stdout ("1" or "0"). The bar widget
turns that into a Wayland idle inhibitor, which is what the idle timer honors.
"""

from __future__ import annotations

import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

NAME = "org.freedesktop.ScreenSaver"
PATH = "/org/freedesktop/ScreenSaver"
IFACE = "org.freedesktop.ScreenSaver"


class ScreenSaver(dbus.service.Object):
    def __init__(self, bus: dbus.Bus) -> None:
        super().__init__(bus, PATH)
        self.bus = bus
        self.cookies: dict[int, str] = {}
        self.next_cookie = 1
        self.watched: set[str] = set()
        self.active = False
        bus.add_signal_receiver(
            self._name_owner_changed,
            signal_name="NameOwnerChanged",
            dbus_interface="org.freedesktop.DBus",
            path="/org/freedesktop/DBus",
        )

    def _set_active(self, active: bool) -> None:
        if active == self.active:
            return
        self.active = active
        sys.stdout.write("1\n" if active else "0\n")
        sys.stdout.flush()

    def _name_owner_changed(self, name: str, _old: str, new: str) -> None:
        name = str(name)
        if str(new) or name not in self.watched:
            return
        self.watched.discard(name)
        before = len(self.cookies)
        self.cookies = {cookie: sender for cookie, sender in self.cookies.items() if sender != name}
        if len(self.cookies) != before:
            self._set_active(bool(self.cookies))

    def _inhibit(self, application_name: str, reason: str, sender: str | None) -> dbus.UInt32:
        cookie = self.next_cookie
        self.next_cookie = self.next_cookie + 1 if self.next_cookie < 0xFFFFFFFF else 1
        owner = str(sender or "")
        self.cookies[cookie] = owner
        if owner:
            self.watched.add(owner)
        self._set_active(True)
        return dbus.UInt32(cookie)

    def _uninhibit(self, cookie: int) -> None:
        self.cookies.pop(int(cookie), None)
        self._set_active(bool(self.cookies))

    @dbus.service.method(IFACE, in_signature="ss", out_signature="u", sender_keyword="sender")
    def Inhibit(self, application_name: str, reason: str, sender: str | None = None) -> dbus.UInt32:
        return self._inhibit(application_name, reason, sender)

    @dbus.service.method(IFACE, in_signature="u", out_signature="")
    def UnInhibit(self, cookie: int) -> None:
        self._uninhibit(cookie)

    @dbus.service.method(IFACE, in_signature="", out_signature="b")
    def GetActive(self) -> bool:
        return False

    @dbus.service.method(IFACE, in_signature="", out_signature="u")
    def GetActiveTime(self) -> dbus.UInt32:
        return dbus.UInt32(0)

    @dbus.service.method(IFACE, in_signature="", out_signature="b")
    def GetSessionIdle(self) -> bool:
        return False

    @dbus.service.method(IFACE, in_signature="", out_signature="")
    def Lock(self) -> None:
        return None

    @dbus.service.method(IFACE, in_signature="", out_signature="")
    def SimulateUserActivity(self) -> None:
        return None


def main() -> int:
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    ScreenSaver(bus)
    reply = bus.request_name(
        NAME,
        dbus.bus.NAME_FLAG_ALLOW_REPLACEMENT | dbus.bus.NAME_FLAG_REPLACE_EXISTING,
    )
    if reply not in (
        dbus.bus.REQUEST_NAME_REPLY_PRIMARY_OWNER,
        dbus.bus.REQUEST_NAME_REPLY_ALREADY_OWNER,
    ):
        sys.stderr.write(f"could not own {NAME} (reply {reply})\n")
        return 1

    def name_lost(name: str) -> None:
        if str(name) == NAME:
            sys.exit(0)

    bus.add_signal_receiver(
        name_lost,
        signal_name="NameLost",
        dbus_interface="org.freedesktop.DBus",
        path="/org/freedesktop/DBus",
    )

    sys.stdout.write("0\n")
    sys.stdout.flush()
    GLib.MainLoop().run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
