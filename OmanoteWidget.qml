import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A notes icon in the bar.
//   left click    the search popup: find a note, or start a new one
//   right click   quick capture: a line into the inbox note
//   middle click  sync the GitHub vaults now
//
// The plugin is only the desktop side. The editor itself is the `omanote`
// program, which a plugin cannot install: a plugin is a git checkout of QML,
// with no install step. So the icon checks whether `omanote` is there, and
// when it is not, a click opens a terminal that offers to install it.
BarWidget {
  id: root
  moduleName: "iluxav.omanote"

  property bool installed: false
  property bool checked: false
  // Where this plugin lives, for the installer script that ships with it.
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

  // The icon is drawn as a vector shape and filled with the bar's foreground
  // colour, so it has the weight and colour of the font glyphs beside it and
  // follows the theme. (The pixel-art logo is for places with room for it; at
  // 12px among smooth icons it only looks rough, and a bare "#" says nothing.)
  //
  //   note     a sticky note with a curled corner and a "#" cut out of it
  //   page     a document with a "#" cut out of it
  //   outline  a "#" heading followed by lines of text, as in the logo
  //
  // Pick one in shell.json with the widget setting "icon".
  readonly property var shapes: ({
    "note": "<path d='M4.6 2h14.8A2.6 2.6 0 0 1 22 4.6v9.9L14.5 22H4.6A2.6 2.6 0 0 1 2 19.4V4.6A2.6 2.6 0 0 1 4.6 2zM8.34 5.40h1.94v11.40h-1.94zM12.33 5.40h1.94v11.40h-1.94zM5.60 8.14h2.74v1.94h-2.74zM10.27 8.14h2.05v1.94h-2.05zM14.26 8.14h2.74v1.94h-2.74zM5.60 12.13h2.74v1.94h-2.74zM10.27 12.13h2.05v1.94h-2.05zM14.26 12.13h2.74v1.94h-2.74z'/><path d='M15.6 22v-4.2a2.2 2.2 0 0 1 2.2-2.2H22z' opacity='0.55'/>",
    "page": "<path d='M6.2 1.5h8.3l5.5 5.5v13.3a2.2 2.2 0 0 1-2.2 2.2H6.2A2.2 2.2 0 0 1 4 20.3V3.7A2.2 2.2 0 0 1 6.2 1.5zM9.19 9.20h1.84v10.80h-1.84zM12.97 9.20h1.84v10.80h-1.84zM6.60 11.79h2.59v1.84h-2.59zM11.03 11.79h1.94v1.84h-1.94zM14.81 11.79h2.59v1.84h-2.59zM6.60 15.57h2.59v1.84h-2.59zM11.03 15.57h1.94v1.84h-1.94zM14.81 15.57h2.59v1.84h-2.59z'/>",
    "outline": "<path d='M4.52 2.00h1.79v10.50h-1.79zM8.20 2.00h1.79v10.50h-1.79zM2.00 4.52h2.52v1.79h-2.52zM6.30 4.52h1.89v1.79h-1.89zM9.98 4.52h2.52v1.79h-2.52zM2.00 8.20h2.52v1.79h-2.52zM6.30 8.20h1.89v1.79h-1.89zM9.98 8.20h2.52v1.79h-2.52zM14.6 6h7.4v2.6h-7.4zM2 15h20v2.6H2zM2 19.6h13v2.6H2z'/>"
  })
  readonly property string shape: shapes[String(setting("icon", "note"))] || shapes["note"]

  function iconSource(color) {
    // rgb(), not the colour's own string: that becomes #aarrggbb when it has
    // alpha, which SVG does not understand.
    var fill = "rgb(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255) + "," + Math.round(color.b * 255) + ")"
    var svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><g fill='" + fill + "' fill-rule='evenodd'>" + root.shape + "</g></svg>"
    return "data:image/svg+xml;utf8," + encodeURIComponent(svg)
  }

  function probe() {
    if (!probeProc.running) probeProc.running = true
  }

  function summon(payload) {
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "iluxav.omanote", payload])
  }

  function launch() {
    if (root.installed) root.summon("{}")
    else root.offerInstall()
  }

  function capture() {
    if (root.installed) root.summon("{\"mode\":\"capture\"}")
    else root.offerInstall()
  }

  function sync() {
    if (!root.bar) return
    if (root.installed) root.bar.run("omarchy-launch-floating-terminal-with-presentation omanote --sync")
    else root.offerInstall()
  }

  function offerInstall() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation bash '" + root.pluginDir + "/install-omanote.sh'")
    // Look again soon: the terminal may well have installed it.
    recheck.restart()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // `command -v` in a login-ish shell, so ~/.local/bin counts.
  Process {
    id: probeProc
    command: ["bash", "-lc", "command -v omanote"]
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      root.checked = true
    }
  }

  Timer {
    id: recheck
    interval: 5000
    repeat: true
    running: root.checked && !root.installed
    onTriggered: root.probe()
  }

  Component.onCompleted: root.probe()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Image {
          anchors.centerIn: parent
          // A touch smaller than the canvas: the shapes fill their box more
          // than a font glyph does.
          width: Math.round(parent.width * 0.9)
          height: width
          source: root.iconSource(button.foreground)
          // Rendered large and scaled down, so it is smooth at any display scale.
          sourceSize: Qt.size(96, 96)
          smooth: true
          mipmap: true
        }
      }
    }
    opacity: root.installed || !root.checked ? 1 : 0.45
    tooltipText: root.installed
      ? "Notes  ·  click: find or new  ·  right-click: quick note  ·  middle-click: sync"
      : "omanote is not installed — click to install it"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.capture()
      else if (b === Qt.MiddleButton) root.sync()
      else root.launch()
    }
  }
}
