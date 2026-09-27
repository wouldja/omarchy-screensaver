import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.wouldja.screensaver"
  ipcTarget: "io.github.wouldja.screensaver"

  property bool saverEnabled: true
  property int seconds: 150
  property bool pauseOnVideo: true
  property bool loaded: false
  property bool applyQueued: false
  property var pendingCommand: []

  property string focusSection: "header"
  property int selectedIndex: -1
  property bool cursorActive: false
  property int playingPlayers: 0
  property bool dbusInhibited: false
  property bool busWanted: false

  readonly property int minutes: Model.minutesFromSeconds(root.seconds)
  readonly property int minuteIndex: Model.nearestMinuteStop(root.minutes)
  readonly property bool mediaPlaying: root.playingPlayers > 0
  readonly property bool inhibiting: root.pauseOnVideo && (root.mediaPlaying || root.dbusInhibited)
  readonly property var visibleSections: ["header", "wait", "video"]

  function scriptPath(fileName) {
    var url = String(Qt.resolvedUrl(fileName))
    var path = url.indexOf("file://") === 0 ? url.slice(7) : url
    if (path.indexOf("%") !== -1) {
      try { path = decodeURIComponent(path) } catch (e) {}
    }
    return path
  }

  function syncBus() {
    root.busWanted = root.loaded && root.pauseOnVideo
  }

  function applyParsed(parsed) {
    root.saverEnabled = parsed.enabled
    root.seconds = parsed.seconds
    root.pauseOnVideo = parsed.pauseOnVideo
    root.loaded = true
  }

  function refresh() {
    if (getProc.running) return
    getProc.command = ["python3", scriptPath("apply.py"), "get"]
    getProc.running = true
  }

  function queueCommand(argv) {
    root.pendingCommand = argv
    root.applyQueued = true
    if (!setProc.running) flushCommand()
  }

  function flushCommand() {
    if (!root.applyQueued) return
    root.applyQueued = false
    setProc.command = root.pendingCommand
    setProc.running = true
  }

  function setEnabled(enabled) {
    root.saverEnabled = !!enabled
    queueCommand(["python3", scriptPath("apply.py"), "set-enabled", root.saverEnabled ? "true" : "false"])
  }

  function setMinutes(value) {
    var minutes = Model.minutesFromSeconds(Model.secondsFromMinutes(value))
    root.seconds = Model.secondsFromMinutes(minutes)
    queueCommand(["python3", scriptPath("apply.py"), "set-seconds", String(root.seconds)])
  }

  function setPauseOnVideo(enabled) {
    root.pauseOnVideo = !!enabled
    queueCommand(["python3", scriptPath("apply.py"), "set-pause", root.pauseOnVideo ? "true" : "false"])
  }

  function dismissScreensaver() {
    queueCommand(["python3", scriptPath("apply.py"), "dismiss"])
  }

  function moveCursor(delta) {
    var sections = visibleSections
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = "header"
      selectedIndex = 0
      return
    }
    var next = sIdx + delta
    if (next < 0) next = 0
    if (next > sections.length - 1) next = sections.length - 1
    focusSection = sections[next]
    selectedIndex = focusSection === "wait" ? -1 : 0
  }

  function moveCursorH(delta) {
    if (focusSection === "wait") {
      var next = root.minuteIndex + delta
      if (next < 0) next = 0
      if (next > Model.stops().length - 1) next = Model.stops().length - 1
      root.setMinutes(Model.stops()[next])
    }
  }

  function activateCursor() {
    if (focusSection === "header") setEnabled(!root.saverEnabled)
    else if (focusSection === "video") setPauseOnVideo(!root.pauseOnVideo)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onLoadedChanged: syncBus()
  onPauseOnVideoChanged: syncBus()

  onOpenedChanged: if (opened) {
    refresh()
    focusSection = "header"
    selectedIndex = 0
    cursorActive = false
  }

  onInhibitingChanged: if (root.inhibiting) root.dismissScreensaver()

  Process {
    id: getProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyParsed(Model.parseState(text))
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyParsed(Model.parseState(text))
    }
    onRunningChanged: if (!running && root.applyQueued) root.flushCommand()
  }

  // Mpris.players is a live model, but a binding that reads isPlaying does not
  // subscribe to later changes on players that already exist. Watch each one.
  Instantiator {
    model: Mpris.players
    delegate: Item {
      id: watch
      required property var modelData
      property bool playing: false

      function readPlaying() {
        return !!(watch.modelData && watch.modelData.isPlaying)
      }

      function publish(next) {
        next = !!next
        if (next === watch.playing) return
        watch.playing = next
        root.playingPlayers = Math.max(0, root.playingPlayers + (next ? 1 : -1))
      }

      Component.onCompleted: publish(readPlaying())
      Component.onDestruction: if (watch.playing) root.playingPlayers = Math.max(0, root.playingPlayers - 1)

      Connections {
        target: watch.modelData
        function onIsPlayingChanged() { watch.publish(watch.readPlaying()) }
        function onPlaybackStateChanged() { watch.publish(watch.readPlaying()) }
      }
    }
  }

  Process {
    id: busProc
    running: root.busWanted
    command: ["python3", "-u", root.scriptPath("screensaver_bus.py")]
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line).trim()
        if (text === "1" || text === "0") root.dbusInhibited = text === "1"
      }
    }
    onRunningChanged: if (!running) root.dbusInhibited = false
    onExited: function(exitCode, exitStatus) {
      root.dbusInhibited = false
      if (!root.busWanted) return
      root.busWanted = false
      busRestart.restart()
    }
  }

  Timer {
    id: busRestart
    interval: 1000
    repeat: false
    onTriggered: if (root.loaded && root.pauseOnVideo) root.busWanted = true
  }

  // systemd-inhibit only blocks logind. Omarchy locks from the Wayland idle
  // notification, which honors a zwp_idle_inhibitor on a mapped surface.
  PanelWindow {
    id: inhibitWindow
    visible: root.inhibiting
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 1
    implicitHeight: 1
    anchors.top: true
    anchors.left: true
    mask: Region {}
    WlrLayershell.namespace: "io.github.wouldja.screensaver.inhibit"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    IdleInhibitor {
      window: inhibitWindow
      enabled: root.inhibiting
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.saverEnabled ? (root.inhibiting ? "󰈈" : "󱄄") : "󰀝"
    tooltipText: root.saverEnabled
      ? (root.inhibiting ? "Screensaver paused for video" : "Screensaver on")
      : "Screensaver off"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.setEnabled(!root.saverEnabled)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(14)

        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight
          readonly property bool ringVisible: root.cursorActive && root.focusSection === "header"
          function focusHero() {
            root.cursorActive = true
            root.focusSection = "header"
            root.selectedIndex = 0
          }

          PanelHero {
            id: hero
            width: parent.width
            title: "Screensaver"
            meta: !root.saverEnabled
              ? "TURNED OFF"
              : (root.inhibiting ? "PAUSED FOR VIDEO" : Model.durationLabel(Model.stops()[Math.round(waitSlider.dragging ? waitSlider.liveValue : root.minuteIndex)]))
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconOpacity: root.saverEnabled ? 1.0 : 0.45
            iconComponent: heroIcon
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                checked: root.saverEnabled
                hasCursor: header.ringVisible
                foreground: hero.foreground
                onHovered: function(on) { if (on) header.focusHero() }
                onToggled: root.setEnabled(!root.saverEnabled)
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(6)
          opacity: root.saverEnabled ? 1 : 0.45

          Item {
            width: parent.width
            implicitHeight: Math.max(waitHeader.implicitHeight, waitValue.implicitHeight)

            PanelSectionHeader {
              id: waitHeader
              text: "WAIT"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: waitValue
              textFormat: Text.PlainText
              text: Model.stops()[Math.round(waitSlider.dragging ? waitSlider.liveValue : root.minuteIndex)] + " min"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          CursorSurface {
            id: waitRow
            width: parent.width
            height: waitSlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.cursorActive && root.focusSection === "wait"
            foreground: root.bar.foreground
            outline: true

            PanelSlider {
              id: waitSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 0
              maximum: Model.stops().length - 1
              step: 1
              integer: true
              tickCount: Model.stops().length
              value: root.minuteIndex
              onReleased: function(v) { root.setMinutes(Model.stops()[Math.round(v)]) }
            }

            HoverHandler {
              onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "wait"
                root.selectedIndex = -1
              }
            }
          }
        }

        Toggle {
          width: parent.width
          label: "Pause when video is playing"
          description: "Keep the screensaver and the password lock off while a video is playing."
          foreground: root.bar.foreground
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          checked: root.pauseOnVideo
          hasCursor: root.cursorActive && root.focusSection === "video"
          onHovered: function(h) {
            if (!h) return
            root.cursorActive = true
            root.focusSection = "video"
            root.selectedIndex = 0
          }
          onClicked: root.setPauseOnVideo(!root.pauseOnVideo)
        }
      }
    }
  }

  Component {
    id: heroIcon
    Text {
      textFormat: Text.PlainText
      text: root.saverEnabled ? "󱄄" : "󰀝"
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.display
    }
  }
}
