import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "SearchModel.js" as SearchModel

// omaFind overlay – blazing-fast local file search, Spotlight-style.
// IPC: open / close / toggle / dismiss (same surface as omaSearch).
// Type to search ($HOME by default via plocate); ↑/↓ to pick a result;
// Enter to open it with xdg-open; Ctrl+C to copy the path to the clipboard.
// Ctrl+L toggles live search via fd (finds files not yet in the plocate index).
// The frosted pill + card design is preserved from omaSearch.
Item {
  id: root

  property var shell: null
  property var manifest: null

  // ── Overlay visibility ───────────────────────────────────────────────────
  property bool opened: false

  // ── Search state ─────────────────────────────────────────────────────────
  property string searchQuery: ""
  property string searchBuf:   ""
  property bool   searching:   false
  property string searchError: ""
  property bool   homeOnly:    true   // restrict to $HOME
  property bool   liveSearch:  false  // use fd instead of plocate
  property int    selectedIndex: -1
  property bool   keyboardNavActive: false
  property real   lastMouseX: -1
  property real   lastMouseY: -1

  // ── Position (drag) ──────────────────────────────────────────────────────
  property int dragX: 0
  property int dragY: 0

  // ── Toast ────────────────────────────────────────────────────────────────
  property string toastText:  ""
  property bool   toastShown: false

  // ── Clipboard copy payload ───────────────────────────────────────────────
  property string copyPayload: ""

  // ── Theme / style shortcuts ──────────────────────────────────────────────
  property color background:   Color.menu.background
  readonly property color subtle: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.6)
  readonly property color note:   Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.78)
  property color foreground:   Color.menu.text
  property color border:       Color.menu.border
  property color scrim:        Color.menu.scrim
  readonly property int   cornerRadius:   Style.cornerRadius
  property string fontFamily:  Style.font.menuFamily
  property int    contentMargin: Style.spacing.panelPadding

  // ── Paths ─────────────────────────────────────────────────────────────────
  readonly property string pluginDir: (manifest && manifest.__sourceDir)
    ? String(manifest.__sourceDir)
    : (Quickshell.env("HOME") + "/.config/omarchy/plugins/sanjith.omafind")
  readonly property string searchScript: pluginDir + "/search.py"
  readonly property string searchBin:    pluginDir + "/bin/omafind-search"
  readonly property string positionPath: Quickshell.env("HOME") + "/.local/state/omafind/position.json"

  // ── Computed ──────────────────────────────────────────────────────────────
  readonly property bool hasResults: resultsModel.count > 0
  readonly property bool showCard:   hasResults || searching || searchError !== ""

  // ─────────────────────────────────────────────────────────────────────────
  // Liquid-glass finish: soft sheen + rim on every frosted surface.
  // ─────────────────────────────────────────────────────────────────────────
  component GlassSheen: Item {
    id: glass
    property real  radius:   0
    property real  strength: 1.0
    property color tint:     "white"
    anchors.fill: parent

    Rectangle {
      anchors.fill: parent
      radius: glass.radius
      gradient: Gradient {
        GradientStop { position: 0.0;  color: Qt.rgba(glass.tint.r, glass.tint.g, glass.tint.b, 0.075 * glass.strength) }
        GradientStop { position: 0.42; color: Qt.rgba(glass.tint.r, glass.tint.g, glass.tint.b, 0.0) }
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: glass.radius
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(glass.tint.r, glass.tint.g, glass.tint.b, 0.08 * glass.strength)
    }

    Rectangle {
      anchors.fill: parent
      radius: glass.radius
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(glass.tint.r, glass.tint.g, glass.tint.b, Math.min(0.9, 0.4 * glass.strength))
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled:       true
        maskSource:        rimMask
        maskThresholdMin:  0.5
        maskSpreadAtMin:   1.0
      }
    }

    Item {
      id: rimMask
      anchors.fill: parent
      visible: false
      layer.enabled: true
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0;  color: "white" }
          GradientStop { position: 0.45; color: "transparent" }
          GradientStop { position: 0.8;  color: "transparent" }
          GradientStop { position: 1.0;  color: Qt.rgba(1, 1, 1, 0.35) }
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core functions
  // ─────────────────────────────────────────────────────────────────────────

  function open(payloadJson) {
    root.opened = true
    root.keyboardNavActive = true
    root.lastMouseX = -1
    root.lastMouseY = -1
    Qt.callLater(function() {
      promptField.forceActiveFocus()
      promptField.selectAll()
    })
  }

  function close() {
    root.opened = false
    root.keyboardNavActive = false
    root.lastMouseX = -1
    root.lastMouseY = -1
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "sanjith.omafind")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function toast(text) {
    root.toastText  = String(text)
    root.toastShown = true
    toastTimer.restart()
  }

  function runSearch() {
    var q = root.searchQuery.replace(/^\s+|\s+$/g, "")
    if (!q) {
      resultsModel.clear()
      root.selectedIndex = -1
      root.searching     = false
      root.searchError   = ""
      return
    }
    root.searching   = true
    root.searchError = ""
    root.searchBuf   = ""
    if (searchProc.running) searchProc.signal(15)
    searchProc.running = true
  }

  function openSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= resultsModel.count) return
    var item = resultsModel.get(root.selectedIndex)
    var path = item.rPath
    var kind = item.rKind
    if (kind === "app") {
      // Launch via gtk-launch using the desktop file basename (without .desktop).
      var appName = path.replace(/^.*\//, "").replace(/\.desktop$/, "")
      Quickshell.execDetached(["gtk-launch", appName])
    } else {
      Quickshell.execDetached(["xdg-open", path])
    }
    root.dismiss()
  }

  function searchBrowser() {
    var query = SearchModel.clip(String(promptField.text || root.searchQuery || "").replace(/\s+/g, " "), 500).trim()
    if (!query) return
    var url = "https://www.google.com/search?q=" + encodeURIComponent(query)
    Quickshell.execDetached(["omarchy", "launch", "browser", url])
    root.dismiss()
  }

  function copySelectedPath() {
    if (root.selectedIndex < 0 || root.selectedIndex >= resultsModel.count) return
    var path = resultsModel.get(root.selectedIndex).rPath
    root.copyPayload = path
    if (copyProc.running) copyProc.signal(15)
    copyProc.stdinEnabled = true
    copyProc.running = true
    root.toast("\u2713 Path copied")
  }

  function moveSelection(step) {
    var n = resultsModel.count
    if (!n) return
    root.keyboardNavActive = true
    root.selectedIndex = Math.max(0, Math.min(n - 1, root.selectedIndex + step))
  }

  function resolveAppIcon(icon) {
    if (root.shell && root.shell.appLibrary && typeof root.shell.appLibrary.iconSource === "function") {
      return root.shell.appLibrary.iconSource(icon)
    }
    var value = String(icon || "")
    if (!value) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function savePosition() {
    root.savePosPayload = JSON.stringify({ dragX: root.dragX, dragY: root.dragY }) + "\n"
    if (!savePosProc.running) savePosProc.running = true
  }

  property string savePosPayload: ""

  // ─────────────────────────────────────────────────────────────────────────
  // Data model
  // ─────────────────────────────────────────────────────────────────────────
  ListModel { id: resultsModel }

  // ─────────────────────────────────────────────────────────────────────────
  // Processes
  // ─────────────────────────────────────────────────────────────────────────

  // Search worker: plocate (default) or fd (--live).
  Process {
    id: searchProc
    command: [root.searchBin,
              "--query", root.searchQuery,
              "--limit", "50"]
              .concat(root.homeOnly   ? ["--home-only"] : ["--all"])
              .concat(root.liveSearch ? ["--live"]      : [])
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (root.searchBuf.length + String(chunk).length <= 131072)
          root.searchBuf += chunk
      }
    }
    onExited: function() {
      root.searching = false
      var data = SearchModel.parseSearchOutput(root.searchBuf)
      root.searchBuf = ""
      if (data.ok) {
        root.searchError = ""
        resultsModel.clear()
        for (var i = 0; i < data.results.length; i++) {
          var r = data.results[i]
          resultsModel.append({ rPath: r.path, rName: r.name, rDir: r.dir, rKind: r.kind, rIcon: r.icon || "" })
        }
        root.keyboardNavActive = true
        root.selectedIndex = resultsModel.count > 0 ? 0 : -1
      } else {
        root.searchError   = data.error || "Search failed."
        root.selectedIndex = -1
        resultsModel.clear()
      }
    }
  }

  // Debounce: wait 120ms after the last keystroke before firing the search.
  Timer {
    id: searchDebounce
    interval: 120
    repeat:   false
    onTriggered: root.runSearch()
  }

  // wl-copy: copy path to clipboard (text never touches argv).
  Process {
    id: copyProc
    command:      ["/usr/bin/wl-copy", "--"]
    stdinEnabled: true
    onStarted: {
      copyProc.write(root.copyPayload)
      copyProc.stdinEnabled = false
    }
  }

  // Position persistence.
  Process {
    id: savePosProc
    command: ["/usr/bin/python3", "-I", "-S", "-c",
      "import os,sys,json,secrets\n" +
      "d=os.path.expanduser('~/.local/state/omafind')\n" +
      "os.makedirs(d,exist_ok=True)\n" +
      "p=os.path.join(d,'position.json')\n" +
      "t=os.path.join(d,'.pos.'+secrets.token_hex(4)+'.tmp')\n" +
      "open(t,'w').write(sys.stdin.read())\n" +
      "os.replace(t,p)\n"]
    stdinEnabled: true
    onStarted: {
      savePosProc.write(root.savePosPayload)
      savePosProc.stdinEnabled = false
    }
  }

  // Load saved position on startup.
  FileView {
    id: positionFile
    path: root.positionPath
    atomicWrites: true
    printErrors:  false
    onLoaded: {
      try {
        var pos = JSON.parse(text())
        root.dragX = Number(pos.dragX) || 0
        root.dragY = Number(pos.dragY) || 0
      } catch (e) {}
    }
  }

  // Toast auto-dismiss.
  Timer {
    id: toastTimer
    interval: 1300
    onTriggered: root.toastShown = false
  }

  Component.onDestruction: {
    if (searchProc.running) searchProc.signal(15)
    if (copyProc.running)   copyProc.signal(15)
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────────
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace:      "omafind"
    WlrLayershell.layer:          WlrLayer.Overlay
    WlrLayershell.keyboardFocus:  root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode:                ExclusionMode.Ignore

    readonly property int gap:          Style.space(12)
    readonly property int surfaceWidth: Math.min(Style.space(640), panel.width - Style.space(32))

    readonly property int cardMax: Math.max(
      Style.space(80),
      Math.min(Math.round(panel.height * 0.6),
               panel.height - pill.height - panel.below - panel.gap - Style.space(48)))
    readonly property int cardTarget: root.showCard
      ? Math.min(
          card.contentTopInset + card.contentBottomInset
            + cardHeader.height + Style.space(8)
            + resultsList.contentHeight,
          panel.cardMax)
      : 0

    readonly property int above:    root.showCard ? panel.cardTarget + panel.gap : 0
    readonly property int below:    hints.height + Style.space(8)
    readonly property int pillTop:  Math.round((panel.height - panel.above - pill.height - panel.below) / 2) + panel.above
    readonly property int pillY:    panel.pillTop + panel.clampY(root.dragY)
    readonly property int surfaceX: Math.round((panel.width - panel.surfaceWidth) / 2) + panel.clampX(root.dragX)

    function clampX(value) {
      var slack = Math.round((panel.width - panel.surfaceWidth) / 2) - Style.space(8)
      return Math.max(-slack, Math.min(slack, value))
    }
    function clampY(value) {
      return Math.max(Style.space(8) + panel.above - panel.pillTop,
                      Math.min(panel.height - Style.space(8) - panel.pillTop - pill.height - panel.below, value))
    }

    // ── Backdrop scrim ────────────────────────────────────────────────────
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.scrim.r, root.scrim.g, root.scrim.b, 1)
      Behavior on color { ColorAnimation { duration: 260 } }
      opacity: root.opened ? 0.4 : 0
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    HoverHandler {
      id: panelHover
      onPointChanged: {
        var sp = point.scenePosition
        if (root.lastMouseX < 0) {
          root.lastMouseX = sp.x
          root.lastMouseY = sp.y
          return
        }
        if (Math.abs(sp.x - root.lastMouseX) > 2 || Math.abs(sp.y - root.lastMouseY) > 2) {
          root.lastMouseX = sp.x
          root.lastMouseY = sp.y
          root.keyboardNavActive = false
        }
      }
    }

    // ── Results card (above the pill) ────────────────────────────────────
    BorderSurface {
      id: card

      visible: root.showCard
      width:   panel.surfaceWidth
      x:       panel.surfaceX
      y:       pill.y - panel.gap - card.height
      height:  panel.cardTarget
      radius:  Style.space(20)
      color:   Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)

      Behavior on color  { ColorAnimation  { duration: 260 } }
      Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      borderSpec: Border.none()
      padding: Style.space(14)
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 100 } }

      GlassSheen { radius: card.radius }

      MouseArea {
        anchors.fill: parent
        onClicked: promptField.forceActiveFocus()
      }

      Item {
        anchors.fill:    parent
        anchors.margins: card.contentTopInset

        // Card header: result count / searching state / error
        Item {
          id: cardHeader
          width:  parent.width
          height: Style.space(20)

          Text {
            anchors.left:           parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.searching
              ? "Searching\u2026"
              : root.searchError !== ""
                ? "No results"
                : resultsModel.count > 0
                  ? resultsModel.count + (resultsModel.count === 50 ? "+ files" : " files")
                  : ""
            color: root.searchError !== "" ? Color.urgent : root.subtle
            font.family:    root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // Searching: three animated dots
          Row {
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            visible: root.searching

            Repeater {
              model: 3
              delegate: Rectangle {
                width:   Style.space(4)
                height:  width
                radius:  width / 2
                color:   Color.menu.text
                opacity: 0.25
                SequentialAnimation on opacity {
                  running:  root.searching
                  loops:    Animation.Infinite
                  PauseAnimation  { duration: index * 140 }
                  NumberAnimation { to: 0.85; duration: 260; easing.type: Easing.OutCubic }
                  NumberAnimation { to: 0.25; duration: 260; easing.type: Easing.InCubic }
                  PauseAnimation  { duration: 420 - index * 140 }
                }
              }
            }
          }

          Text {
            visible: root.searchError !== "" && !root.searching
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            text:           SearchModel.clip(root.searchError, 60)
            color:          Color.urgent
            font.family:    root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ── Results list ─────────────────────────────────────────────────
        Flickable {
          id: resultsList

          anchors.top:        cardHeader.bottom
          anchors.topMargin:  Style.space(8)
          anchors.bottom:     parent.bottom
          width:              parent.width
          clip:               true
          contentWidth:       width
          contentHeight:      resultsColumn.height
          boundsBehavior:     Flickable.StopAtBounds
          acceptedButtons:    Qt.NoButton

          function ensureVisible(index) {
            var rowH = Style.space(52)
            var top  = index * rowH
            if (top < contentY) contentY = top
            else if (top + rowH > contentY + height) contentY = top + rowH - height
          }

          Column {
            id: resultsColumn
            width: resultsList.width - Style.space(10)

            Repeater {
              model: resultsModel

              delegate: Item {
                id: resultRow

                required property string rPath
                required property string rName
                required property string rDir
                required property string rKind
                required property string rIcon
                required property int    index

                readonly property bool isSelected: resultRow.index === root.selectedIndex
                readonly property bool isApp:      resultRow.rKind === "app"

                width:  resultsColumn.width
                height: Style.space(52)

                // Selection highlight
                Rectangle {
                  anchors.fill:    parent
                  anchors.margins: Style.space(2)
                  radius: Style.cornerRadius
                  color: resultRow.isSelected ? Color.menu.selectedBackground : "transparent"
                  Behavior on color { ColorAnimation { duration: 80 } }
                }

                // Icon container (App logo or Nerd Font glyph)
                Item {
                  id: iconBox
                  anchors.left:           parent.left
                  anchors.leftMargin:     Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width:                  Style.space(28)
                  height:                 Style.space(28)

                  Image {
                    id: appIcon
                    visible:          resultRow.isApp && status === Image.Ready
                    anchors.centerIn: parent
                    width:            Style.space(26)
                    height:           Style.space(26)
                    fillMode:         Image.PreserveAspectFit
                    sourceSize.width:  Math.round(width * Screen.devicePixelRatio)
                    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                    source:           resultRow.isApp ? root.resolveAppIcon(resultRow.rIcon) : ""
                    asynchronous:     true
                  }

                  Text {
                    id: kindIcon
                    visible:             !resultRow.isApp || appIcon.status !== Image.Ready
                    anchors.centerIn:    parent
                    text:                SearchModel.iconFor(resultRow.rKind)
                    color:               resultRow.rKind === "dir" ? Color.accent : root.note
                    font.family:         Style.font.family
                    font.pixelSize:      Style.font.title
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
                  }
                }

                // File name (primary)
                Text {
                  id: nameLabel
                  anchors.left:        iconBox.right
                  anchors.leftMargin:  Style.space(10)
                  anchors.right:       parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.top:         parent.top
                  anchors.topMargin:   Style.space(9)
                  text:           SearchModel.clip(resultRow.rName, 100)
                  color:          Color.menu.text
                  font.family:    root.fontFamily
                  font.pixelSize: Style.font.body
                  elide:          Text.ElideRight
                }

                // Directory path (secondary, elide from left so the end of the path is visible)
                Text {
                  anchors.left:         nameLabel.left
                  anchors.right:        parent.right
                  anchors.rightMargin:  Style.space(12)
                  anchors.bottom:       parent.bottom
                  anchors.bottomMargin: Style.space(9)
                  text:           SearchModel.clip(resultRow.rDir, 120)
                  color:          root.subtle
                  font.family:    root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide:          Text.ElideLeft
                }

                HoverHandler {
                  id: rowHover
                  cursorShape: Qt.PointingHandCursor
                  onPointChanged: {
                    var sp = point.scenePosition
                    if (root.lastMouseX < 0) {
                      root.lastMouseX = sp.x
                      root.lastMouseY = sp.y
                      return
                    }
                    if (Math.abs(sp.x - root.lastMouseX) > 2 || Math.abs(sp.y - root.lastMouseY) > 2) {
                      root.lastMouseX = sp.x
                      root.lastMouseY = sp.y
                      root.keyboardNavActive = false
                    }
                    if (hovered && !root.keyboardNavActive && root.selectedIndex !== resultRow.index) {
                      root.selectedIndex = resultRow.index
                    }
                  }
                  onHoveredChanged: {
                    if (hovered && !root.keyboardNavActive && root.selectedIndex !== resultRow.index) {
                      root.selectedIndex = resultRow.index
                    }
                  }
                }

                TapHandler {
                  onTapped: {
                    root.selectedIndex = resultRow.index
                    root.openSelected()
                  }
                }
              }
            }
          }

          // Scroll bar
          Item {
            id: scrollBar

            readonly property real scrollable: resultsList.contentHeight - resultsList.height
            readonly property bool hot: scrollArea.containsMouse || scrollArea.pressed

            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width:   Style.space(10)
            visible: scrollBar.scrollable > 1

            Rectangle {
              id: scrollThumb
              anchors.right: parent.right
              width:  scrollBar.hot ? Math.max(3, Style.space(5)) : Math.max(2, Style.space(2))
              radius: width / 2
              height: Math.max(Style.space(18), resultsList.height * (resultsList.height / resultsList.contentHeight))
              y: (resultsList.height - scrollThumb.height)
                 * Math.min(1, Math.max(0, resultsList.contentY / Math.max(1, scrollBar.scrollable)))
              color:   Color.menu.text
              opacity: scrollArea.pressed ? 0.5 : scrollBar.hot ? 0.35 : resultsList.moving ? 0.4 : 0.16
              Behavior on width   { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
              Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            MouseArea {
              id: scrollArea
              property real grab: 0
              function scrollTo(mouseY) {
                var track = resultsList.height - scrollThumb.height
                if (track <= 0) return
                resultsList.contentY = Math.max(0, Math.min(track, mouseY - scrollArea.grab))
                                       / track * scrollBar.scrollable
              }
              anchors.fill:    parent
              hoverEnabled:    true
              preventStealing: true
              onPressed: function(mouse) {
                var onThumb = mouse.y >= scrollThumb.y && mouse.y <= scrollThumb.y + scrollThumb.height
                scrollArea.grab = onThumb ? mouse.y - scrollThumb.y : scrollThumb.height / 2
                scrollArea.scrollTo(mouse.y)
              }
              onPositionChanged: function(mouse) {
                if (scrollArea.pressed) scrollArea.scrollTo(mouse.y)
              }
            }
          }

          // Top/bottom edge fades
          Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: Style.space(12)
            opacity: resultsList.contentY > 1 ? 1 : 0
            gradient: Gradient {
              GradientStop { position: 0; color: card.color }
              GradientStop { position: 1; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0) }
            }
            Behavior on opacity { NumberAnimation { duration: 120 } }
          }

          Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Style.space(12)
            opacity: resultsList.atYEnd ? 0 : 1
            gradient: Gradient {
              GradientStop { position: 0; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0) }
              GradientStop { position: 1; color: card.color }
            }
            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
        }

        Connections {
          target: root
          function onSelectedIndexChanged() {
            if (root.selectedIndex >= 0)
              resultsList.ensureVisible(root.selectedIndex)
          }
        }
      }
    }

    // ── Input pill ────────────────────────────────────────────────────────
    BorderSurface {
      id: pill

      width:  panel.surfaceWidth
      height: Style.space(76)
      x:      panel.surfaceX
      y:      panel.pillY
      radius: height / 2
      color:  Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)

      Behavior on color { ColorAnimation { duration: 260 } }

      borderSpec: Border.none()
      padding:    Style.space(4)
      scale:      root.opened ? 1 : 0.96

      Behavior on y       { enabled: !mover.active; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      Behavior on scale   { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: 100 } }

      GlassSheen {
        radius:   pill.radius
        strength: promptField.activeFocus ? 1.35 : 1.0
        Behavior on strength { NumberAnimation { duration: 160 } }
      }

      opacity: root.opened ? 1 : 0

      MouseArea {
        anchors.fill: parent
        onClicked: promptField.forceActiveFocus()
      }

      // Drag pill – remembers position across opens
      DragHandler {
        id: mover
        target: null
        cursorShape: Qt.SizeAllCursor
        property int fromX: 0
        property int fromY: 0
        onActiveChanged: {
          if (mover.active) {
            mover.fromX = root.dragX
            mover.fromY = root.dragY
          } else {
            root.savePosition()
          }
        }
        onActiveTranslationChanged: {
          if (!mover.active) return
          root.dragX = panel.clampX(mover.fromX + Math.round(mover.activeTranslation.x))
          root.dragY = panel.clampY(mover.fromY + Math.round(mover.activeTranslation.y))
        }
      }

      Row {
        id: pillRow
        anchors.fill:        parent
        anchors.leftMargin:  Style.space(22)
        anchors.rightMargin: Style.space(22)
        spacing:             Style.space(14)

        // Magnifier icon
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text:           "\uf002"
          color:          root.searching ? Color.accent : root.note
          font.family:    Style.font.family
          font.pixelSize: Style.font.title
          Behavior on color { ColorAnimation { duration: 200 } }
        }

        // Search text input
        Item {
          width:  parent.width - Style.space(22 + 14 * 2 + 20)
          height: parent.height

          TextEdit {
            id: promptField
            width:             parent.width
            height:            parent.height
            color:             Color.menu.text
            selectionColor:    Color.menu.selectedBackground
            selectedTextColor: Color.menu.selectedText
            font.family:       root.fontFamily
            font.pixelSize:    Style.font.heading
            verticalAlignment: TextEdit.AlignVCenter
            textFormat:        TextEdit.PlainText
            wrapMode:          TextEdit.NoWrap
            selectByMouse:     true

            cursorDelegate: Rectangle {
              width: Math.max(1, Style.space(1))
              color: Color.accent
            }

            onTextChanged: {
              root.keyboardNavActive = true
              if (text.length > 200) {
                var pos = cursorPosition
                text = text.slice(0, 200)
                cursorPosition = Math.min(pos, text.length)
                return
              }
              root.searchQuery = text
              searchDebounce.restart()
            }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              var isEnter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
              if (event.key === Qt.Key_Escape) {
                root.dismiss()
                event.accepted = true

              } else if (isEnter && (event.modifiers & Qt.ControlModifier)) {
                root.searchBrowser()
                event.accepted = true

              } else if (isEnter) {
                root.openSelected()
                event.accepted = true

              } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true

              } else if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true

              } else if (event.key === Qt.Key_PageUp) {
                root.moveSelection(-10)
                event.accepted = true

              } else if (event.key === Qt.Key_PageDown) {
                root.moveSelection(10)
                event.accepted = true

              } else if (event.modifiers & Qt.ControlModifier) {
                if (isEnter) {
                  root.searchBrowser()
                  event.accepted = true
                } else if (event.key === Qt.Key_C) {
                  root.copySelectedPath()
                  event.accepted = true
                } else if (event.key === Qt.Key_H) {
                  root.homeOnly = !root.homeOnly
                  root.toast(root.homeOnly ? "Home only" : "Whole system")
                  searchDebounce.restart()
                  event.accepted = true
                } else if (event.key === Qt.Key_L) {
                  root.liveSearch = !root.liveSearch
                  root.toast(root.liveSearch ? "Live search (fd)" : "Index search (plocate)")
                  searchDebounce.restart()
                  event.accepted = true
                }
              }
            }
          }

          // Placeholder text
          Text {
            anchors.fill: parent
            visible:      promptField.text.length === 0
            text:         root.homeOnly ? "Search files in ~\u2026" : "Search all files\u2026"
            color:        Color.menu.text
            opacity:      0.44
            font.family:  root.fontFamily
            font.pixelSize: Style.font.heading
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
        }

        // Scope badge: ~ or /
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text:    root.homeOnly ? "~" : "/"
          color:   root.note
          opacity: 0.6
          font.family:    root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ── Hint bar (under the pill) ─────────────────────────────────────────
    Item {
      id: hints

      x:      pill.x + Style.space(12)
      y:      pill.y + pill.height + Style.space(8)
      width:  pill.width - Style.space(24)
      height: Style.space(24)
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 100 } }

      MouseArea {
        anchors.fill: parent
        onClicked: promptField.forceActiveFocus()
      }

      Row {
        anchors.centerIn: parent
        spacing: Style.space(2)

        Button {
          text: root.selectedIndex >= 0
            ? ((resultsModel.count > root.selectedIndex &&
                resultsModel.get(root.selectedIndex).rKind === "dir")
               ? "Open folder \u21b5"
               : "Open file \u21b5")
            : "Open \u21b5"
          tooltipText: "Enter \u2014 open selected file or folder"
          fontSize:    Style.font.caption
          foreground:  root.note
          horizontalPadding: Style.space(7)
          verticalPadding:   Style.space(3)
          onClicked: root.openSelected()
        }

        Button {
          text: "Copy path ^C"
          tooltipText: "Ctrl+C \u2014 copy the full path to clipboard"
          visible: root.selectedIndex >= 0
          fontSize:   Style.font.caption
          foreground: root.note
          horizontalPadding: Style.space(7)
          verticalPadding:   Style.space(3)
          onClicked: root.copySelectedPath()
        }

        Button {
          text: "Search in browser ^\u21b5"
          tooltipText: "Ctrl+Enter \u2014 search query in default browser"
          fontSize:    Style.font.caption
          foreground:  root.note
          horizontalPadding: Style.space(7)
          verticalPadding:   Style.space(3)
          onClicked: root.searchBrowser()
        }

        Button {
          text: root.homeOnly ? "Home only ^H" : "All files ^H"
          tooltipText: "Ctrl+H \u2014 toggle $HOME-only vs whole-system search"
          selected:   root.homeOnly
          fontSize:   Style.font.caption
          foreground: root.note
          horizontalPadding: Style.space(7)
          verticalPadding:   Style.space(3)
          onClicked: {
            root.homeOnly = !root.homeOnly
            root.toast(root.homeOnly ? "Home only" : "Whole system")
            searchDebounce.restart()
          }
        }

        Button {
          text: root.liveSearch ? "Live ^L" : "Index ^L"
          tooltipText: root.liveSearch
            ? "Ctrl+L \u2014 fd (live, finds new files not yet indexed)"
            : "Ctrl+L \u2014 plocate (instant indexed search)"
          selected:   root.liveSearch
          fontSize:   Style.font.caption
          foreground: root.note
          horizontalPadding: Style.space(7)
          verticalPadding:   Style.space(3)
          onClicked: {
            root.liveSearch = !root.liveSearch
            root.toast(root.liveSearch ? "Live search (fd)" : "Index search (plocate)")
            searchDebounce.restart()
          }
        }
      }
    }

    // ── Toast pill ────────────────────────────────────────────────────────
    Rectangle {
      id: toastPill

      readonly property bool shown: root.toastShown && root.opened
      readonly property int aboveY: pill.y - height - Style.space(10)

      width:  toastLabel.implicitWidth + Style.space(32)
      height: toastLabel.implicitHeight + Style.space(14)
      x:      pill.x + Math.round((pill.width - width) / 2)
      y:      toastPill.aboveY >= Style.space(8) ? toastPill.aboveY
              : (hints.y + hints.height + Style.space(8))
      radius: height / 2
      color:  Qt.rgba(root.background.r, root.background.g, root.background.b, 0.82)

      Behavior on color { ColorAnimation { duration: 260 } }

      opacity: toastPill.shown ? 1 : 0
      scale:   toastPill.shown ? 1 : 0.9
      visible: opacity > 0

      Behavior on opacity { NumberAnimation { duration: toastPill.shown ? 110 : 260 } }
      Behavior on scale   { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

      GlassSheen {
        radius:   toastPill.radius
        strength: 1.3
      }

      Text {
        id: toastLabel
        anchors.centerIn: parent
        text:           root.toastText
        textFormat:     Text.StyledText
        color:          Color.menu.text
        font.family:    root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
