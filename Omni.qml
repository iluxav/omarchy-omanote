import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// The omanote popup, in two modes.
//
//   find (default)   Type to search every vault. Enter opens the highlighted
//                    note. With nothing typed, or nothing matching, Enter
//                    starts a new note. "+ New note" is always in the list
//                    too, for when a match exists but a new note is wanted.
//   capture          One line, Enter, and it is in the inbox note.
//                    Ctrl+Enter does the same from find mode.
//
//   omarchy-shell shell toggle iluxav.omanote
//   omarchy-shell shell summon iluxav.omanote '{"mode":"capture"}'
//
// The search itself is `omanote --find`, so the order here is the order of
// Ctrl+P inside the editor.
Item {
  id: root

  // How the editor's window opens: "TUI.tile" or "TUI.float".
  readonly property string appId: "TUI.tile"
  readonly property int maxRows: 9

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string mode: "find"
  property string text: ""
  property int selectedIndex: 0
  property int searchSeq: 0
  property string fontFamily: Style.font.menuFamily

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Math.max(Style.space(44), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int rowSpacing: Style.spacing.xs
  readonly property int shownRows: root.mode === "find" ? Math.min(rows.count, root.maxRows) : 0
  property int listHeight: shownRows > 0 ? shownRows * rowHeight + (shownRows - 1) * rowSpacing + Style.spacing.md : 0
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(contentMargin * 2 + headerHeight + listHeight, panel.height - Style.gapsOut * 2)

  // kind: "note" | "new". For a note: name, place, age, path.
  ListModel { id: rows }

  function notify(title, body) {
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send", title, body])
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = payload.fontFamily
    root.mode = payload.mode === "capture" ? "capture" : "find"
    root.text = payload.text || ""
    root.selectedIndex = 0
    root.opened = true
    root.search()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "iluxav.omanote")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setText(next) {
    root.text = next
    if (root.mode === "find") debounce.restart()
  }

  // ---- find ---------------------------------------------------------------

  function search() {
    if (root.mode !== "find") { rows.clear(); return }
    root.searchSeq += 1
    findProc.seq = root.searchSeq
    findProc.command = ["bash", "-lc", "omanote --find \"$1\"", "omanote-find", root.text.trim()]
    findProc.running = true
  }

  // With nothing typed the new note comes first, so a bare Enter starts one.
  // With a query the matches come first, so Enter opens the best one.
  function show(notes) {
    var query = root.text.trim()
    var fresh = { kind: "new", name: query ? "New note “" + query + "”" : "New note", place: "", age: "", path: "" }
    rows.clear()
    if (!query) rows.append(fresh)
    for (var i = 0; i < notes.length; i++) {
      var n = notes[i]
      rows.append({ kind: "note", name: n.name || "", place: n.where || "", age: n.age || "", path: n.path || "" })
    }
    if (query) rows.append(fresh)
    root.selectedIndex = 0
    resultList.positionViewAtIndex(0, ListView.Beginning)
  }

  function move(delta) {
    if (rows.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + rows.count) % rows.count
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function launch(args) {
    Quickshell.execDetached(["omarchy-launch-tui", "--app-id=" + root.appId, "omanote"].concat(args))
  }

  function activate(index) {
    var row = index >= 0 && index < rows.count ? rows.get(index) : null
    var query = root.text.trim()
    root.dismiss()
    if (row && row.kind === "note") root.launch([row.path])
    else root.launch(query ? ["--new", query] : ["--new"])
  }

  Process {
    id: findProc
    property int seq: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A slower, older search must not overwrite a newer one.
        if (findProc.seq !== root.searchSeq) return
        var notes = []
        try { notes = JSON.parse(text || "[]") } catch (e) { notes = [] }
        root.show(notes)
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0 || findProc.seq !== root.searchSeq) return
      root.dismiss()
      if (exitCode === 127) root.notify("omanote is not installed", "Click the notes icon in the bar to install it.")
      // An omanote from before `--find` existed answers "unknown option".
      else root.notify("omanote needs updating", "This popup needs a newer omanote. Update it the way you installed it.")
    }
  }

  Timer {
    id: debounce
    interval: 35
    onTriggered: root.search()
  }

  // ---- capture ------------------------------------------------------------

  function capture() {
    var line = root.text.trim()
    root.dismiss()
    if (!line) return
    captureProc.line = line
    captureProc.command = ["bash", "-lc", "omanote --capture \"$1\"", "omanote-capture", line]
    captureProc.running = true
  }

  // Run it rather than fire and forget: a missing `omanote` should say so
  // instead of swallowing the note.
  Process {
    id: captureProc
    property string line: ""
    onExited: function(exitCode) {
      if (exitCode === 0) root.notify("Noted", captureProc.line)
      else if (exitCode === 127) root.notify("omanote is not installed", "Click the notes icon in the bar to install it. Your note was: " + captureProc.line)
      else root.notify("Could not save the note", captureProc.line)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-omanote"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      // A little above the middle, where the Omarchy menu sits, and steady
      // while the list grows and shrinks underneath the input.
      y: Math.max(Style.gapsOut, Math.round(parent.height * 0.26))
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var finding = root.mode === "find"
          if (event.key === Qt.Key_Escape) {
            if (root.text) root.setText("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!finding || (event.modifiers & Qt.ControlModifier)) root.capture()
            else root.activate(root.selectedIndex)
            event.accepted = true
          } else if (finding && (event.key === Qt.Key_Down || event.key === Qt.Key_Tab)) {
            root.move(1)
            event.accepted = true
          } else if (finding && (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)) {
            root.move(-1)
            event.accepted = true
          } else if (finding && event.key === Qt.Key_PageDown) {
            root.move(root.maxRows - 1)
            event.accepted = true
          } else if (finding && event.key === Qt.Key_PageUp) {
            root.move(-(root.maxRows - 1))
            event.accepted = true
          } else if (Util.editsFilter(event, root.text)) {
            root.setText(Util.editedFilter(event, root.text))
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setText(root.text + event.text)
            event.accepted = true
          }
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // What is being typed.
        Text {
          id: input
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.headerHeight
          verticalAlignment: Text.AlignVCenter
          text: root.text || (root.mode === "capture" ? "Quick note..." : "Find a note, or start one...")
          color: root.foreground
          opacity: root.text ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideLeft
        }

        Rectangle {
          id: rule
          visible: root.shownRows > 0
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: input.bottom
          height: Style.spacing.hairline
          color: root.foreground
          opacity: 0.12
        }

        ListView {
          id: resultList
          visible: root.shownRows > 0
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: rule.bottom
          anchors.topMargin: Style.spacing.md
          anchors.bottom: parent.bottom
          clip: true
          spacing: root.rowSpacing
          interactive: true
          boundsBehavior: Flickable.StopAtBounds
          model: rows

          delegate: Rectangle {
            id: row
            required property int index
            required property string kind
            required property string name
            required property string place
            required property string age
            readonly property bool current: index === root.selectedIndex

            width: resultList.width
            height: root.rowHeight
            radius: Math.max(0, root.cornerRadius - 2)
            color: current ? root.selectedBackground : "transparent"

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.selectedIndex = row.index
              onClicked: root.activate(row.index)
            }

            // The note's name...
            Text {
              id: title
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.62)
              text: (row.kind === "new" ? "+  " : "") + row.name
              color: row.current ? root.selectedText : root.foreground
              opacity: row.kind === "new" && !row.current ? 0.7 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            // ...then, quieter, the vault it lives in and how old it is.
            Text {
              textFormat: Text.PlainText
              anchors.left: title.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: when.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: row.place
              color: root.foreground
              opacity: 0.42
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideLeft
            }

            Text {
              id: when
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              text: row.age
              color: root.foreground
              opacity: 0.42
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
