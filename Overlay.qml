import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

// The pre-Quattro theme switcher: a filterable textual list on the left, the
// selected theme's preview on the right. Summon it with
//   omarchy-shell shell summon io.github.bruce-forte.old-theme-switcher '{}'
// Enter applies the theme through `omarchy theme set`; nothing is written back
// to the caller, so the summon returns immediately.
Item {
  id: root

  property var themes: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool opened: false
  property bool loaded: false

  property color scrim: Color.menu.scrim
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  readonly property var filtered: {
    var needle = filterText.toLowerCase()
    if (!needle) return themes

    var out = []
    for (var i = 0; i < themes.length; i++) {
      if (String(themes[i].name).toLowerCase().indexOf(needle) !== -1)
        out.push(themes[i])
    }
    return out
  }

  readonly property var currentItem: (selectedIndex >= 0 && selectedIndex < filtered.length) ? filtered[selectedIndex] : null
  readonly property string currentName: currentItem ? String(currentItem.name) : ""
  readonly property string currentPreview: currentItem ? String(currentItem.preview || "") : ""

  onFilteredChanged: if (selectedIndex >= filtered.length) selectedIndex = Math.max(0, filtered.length - 1)

  function selectAdjacent(step) {
    if (filtered.length === 0) return

    var next = selectedIndex + step
    if (next < 0) next = filtered.length - 1
    else if (next >= filtered.length) next = 0

    selectedIndex = next
    list.positionViewAtIndex(next, ListView.Contain)
  }

  function indexForName(name) {
    for (var i = 0; i < filtered.length; i++) {
      if (String(filtered[i].name) === name) return i
    }
    return 0
  }

  function applySelected() {
    if (!currentName) {
      close()
      return
    }

    Quickshell.execDetached(["omarchy-theme-set", currentName])
    opened = false
  }

  // Lifecycle hooks invoked by omarchy-shell summon/hide.
  function open(payload) {
    filterText = ""
    opened = true
    listProc.running = true
  }

  function close() {
    opened = false
  }

  function toggle() {
    if (opened) close()
    else open("")
  }

  // Theme names, their previews, and which one is live. Re-read on every
  // summon so an installed or removed theme shows up without a shell restart.
  Process {
    id: listProc

    command: [root.pluginDir + "/themes.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = {}
        try {
          payload = JSON.parse(String(text || "{}")) || {}
        } catch (e) {
          payload = {}
        }

        root.themes = Array.isArray(payload.rows) ? payload.rows : []
        root.loaded = true
        root.selectedIndex = root.indexForName(String(payload.current || ""))

        Qt.callLater(function() {
          list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
          list.forceActiveFocus()
        })
      }
    }
  }

  PanelWindow {
    id: panel

    visible: root.opened && root.loaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-old-theme-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: panel.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      id: card

      anchors.centerIn: parent

      readonly property int contentMargin: Style.space(14)
      readonly property int columnGap: Style.space(14)
      // Previews are screenshots of a desktop, so the pane is shaped like one:
      // sized 16:9 the image fills it edge to edge instead of letterboxing.
      readonly property real previewAspect: 16 / 9
      readonly property int previewWidth: Math.round((width - contentMargin * 2 - columnGap) * 0.66)

      width: Math.min(parent.width - Style.space(80), Style.space(1100))
      height: Math.min(parent.height - Style.space(120),
                       Math.round(previewWidth / previewAspect) + contentMargin * 2)
      color: root.background
      radius: Style.space(8)
      border.width: Style.spacing.hairline
      border.color: root.border

      // Swallow clicks so only the scrim dismisses.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        anchors.fill: parent
        anchors.margins: card.contentMargin

        Item {
          id: listColumn

          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          width: parent.width - card.columnGap - card.previewWidth

          Item {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.font.title + Style.space(16)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              elide: Text.ElideRight
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
              text: root.filterText ? "Theme: " + root.filterText : "Theme"
            }
          }

          Rectangle {
            id: headerRule

            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.spacing.hairline
            color: root.border
            opacity: 0.5
          }

          ListView {
            id: list

            anchors.top: headerRule.bottom
            anchors.topMargin: Style.space(6)
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            clip: true
            focus: true
            model: root.filtered
            currentIndex: root.selectedIndex
            highlightMoveDuration: 0

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.filterText) root.filterText = ""
                else root.close()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.applySelected()
                event.accepted = true
              } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab
                         || (event.key === Qt.Key_P && event.modifiers === Qt.ControlModifier)) {
                root.selectAdjacent(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab
                         || (event.key === Qt.Key_N && event.modifiers === Qt.ControlModifier)) {
                root.selectAdjacent(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Home) {
                root.selectedIndex = 0
                list.positionViewAtIndex(0, ListView.Contain)
                event.accepted = true
              } else if (event.key === Qt.Key_End) {
                root.selectedIndex = Math.max(0, root.filtered.length - 1)
                list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
                event.accepted = true
              } else if (Util.editsFilter(event, root.filterText)) {
                root.filterText = Util.editedFilter(event, root.filterText)
                event.accepted = true
              } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                         && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                root.filterText += event.text
                event.accepted = true
              }
            }

            delegate: Rectangle {
              id: row

              required property int index
              required property var modelData

              width: ListView.view.width
              height: Style.font.body + Style.space(14)
              radius: Style.space(4)
              color: index === root.selectedIndex ? root.selectedBackground : "transparent"

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                elide: Text.ElideRight
                color: index === root.selectedIndex ? root.selectedText : root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                text: String(row.modelData.name)
              }

              MouseArea {
                anchors.fill: parent
                onClicked: root.selectedIndex = row.index
                onDoubleClicked: {
                  root.selectedIndex = row.index
                  root.applySelected()
                }
              }
            }
          }
        }

        Rectangle {
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: listColumn.right
          anchors.leftMargin: card.columnGap
          anchors.right: parent.right
          color: Util.alpha(root.foreground, 0.06)
          radius: Style.space(6)
          clip: true

          // Fit rather than crop, and decode at the pane's true device
          // resolution: cropping a preview decoded to the pane's width had to
          // scale it back up to cover the pane's height, which is what made it
          // blurry. Mipmapping keeps the (always downward) scale clean.
          Image {
            id: preview

            anchors.fill: parent
            source: Util.fileUrl(root.currentPreview)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
            sourceSize.width: Math.round(width * Screen.devicePixelRatio)
            sourceSize.height: Math.round(height * Screen.devicePixelRatio)
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: !preview.visible
            color: root.foreground
            opacity: 0.6
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            text: root.currentName ? "No preview" : "No matches"
          }
        }
      }
    }
  }
}
