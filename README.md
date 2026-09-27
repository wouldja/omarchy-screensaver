# Screensaver

Bar widget for the Omarchy screensaver: turn it on or off, choose how long
to wait after idle, and pause the screensaver and the password lock while a
video is playing.

## Install

```sh
omarchy plugin add https://github.com/wouldja/omarchy-screensaver.git --enable
```

The widget lands on the right of the bar. If it does not appear immediately:

```sh
omarchy-shell shell rescanPlugins
```

## Remove

```sh
omarchy plugin remove io.github.wouldja.screensaver
```

## What it changes

- On/off uses `omarchy toggle screensaver` (`~/.local/state/omarchy/toggles/screensaver-off`).
- Wait time writes `idle.screensaver` in `~/.config/omarchy/shell.json`.
- Pause-while-video is stored in `~/.local/state/omarchy/screensaver-panel.json`.

While that pause is on, the widget keeps the lock from appearing during playback:

- It owns `org.freedesktop.ScreenSaver` so browser and player inhibit requests
  (the ones xdg-desktop-portal forwards) are actually accepted.
- It watches MPRIS for a player whose status is Playing.
- Either of those holds a Wayland idle inhibitor. Omarchy's lock timer follows
  that protocol. A logind `systemd-inhibit` does not, which is why the password
  prompt used to show up on schedule during a video.

The inhibitor is released when playback stops, the player drops its inhibit
request, or the pause toggle is turned off.

## License

MIT. See [LICENSE](LICENSE). Needs Omarchy (Quickshell) and Python 3 with
`dbus-python`, both already on a standard Omarchy install. No extra packages.

