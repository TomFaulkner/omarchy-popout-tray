pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "io.github.tomfaulkner.tray"
  ipcTarget: "io.github.tomfaulkner.tray"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var tray: null

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool ready: tray !== null
  readonly property var items: ready ? tray.items : []
  readonly property var config: ready ? tray.config : Model.normalizeSettings(null)
  readonly property var sections: Model.sections(root.items, root.config.groups)
  readonly property var displayTiles: Model.displayTiles(root.items, root.config.groups)
  readonly property int tileCount: displayTiles.length
  readonly property int columns: Model.gridColumns(tileCount, config.columns)
  readonly property int spacing: Style.space(8)
  readonly property int desiredWidth: Math.max(Style.space(200),
    columns * config.tileWidth + (columns - 1) * spacing + Style.space(24))
  readonly property int desiredHeight: Math.max(Style.space(120),
    Style.space(48) + rowsHeight + Style.space(24))
  readonly property int rowsHeight: {
    var height = 0
    for (var i = 0; i < sections.length; i++) {
      var section = sections[i]
      var rows = Math.ceil(section.items.length / Math.max(1, columns))
      height += rows * config.tileHeight + Math.max(0, rows - 1) * spacing
      if (String(section.name || "") !== "") height += Style.space(26)
      if (i > 0) height += Style.space(14)
    }
    return height
  }
  readonly property bool canOpen: bar !== null && anchorItem !== null
  readonly property int attention: ready ? tray.attention : 0

  property int cursor: 0
  property bool cursorActive: true
  property var tileItems: ({})
  property var flickItem: null
  property var flickContentItem: null

  function registerTile(position, tile) {
    var next = ({})
    for (var key in root.tileItems) next[key] = root.tileItems[key]
    next[String(position)] = tile
    root.tileItems = next
  }

  function unregisterTile(position, tile) {
    if (root.tileItems[String(position)] !== tile) return
    var next = ({})
    for (var key in root.tileItems) if (key !== String(position)) next[key] = root.tileItems[key]
    root.tileItems = next
  }

  function open() {
    if (!canOpen) return
    cursor = 0
    cursorActive = true
    controller.show()
  }

  function openAt(tileId) {
    var key = String(tileId || "")
    for (var i = 0; i < displayTiles.length; i++) {
      if (String(displayTiles[i].id) !== key) continue
      cursor = i
      cursorActive = true
      if (!opened) controller.show()
      Qt.callLater(revealCursor)
      return
    }
  }

  // Selecting a tile from the finder has to launch it, not just point the
  // grid at it. The grid is mapped first so an embedded panel can resolve its
  // anchor, then the tile is pressed, then the grid steps aside again unless
  // the tile opened a panel of its own that lives inside it.
  function pick(tileId) {
    var wasOpen = opened
    openAt(tileId)
    Qt.callLater(function() {
      var tileItem = root.tileItems[String(clampedCursor())]
      if (tileItem && typeof tileItem.activate === "function") tileItem.activate(Qt.LeftButton)
      Qt.callLater(function() {
        if (!wasOpen && !tileOwnsOpenPanel(tileItem)) controller.hide()
      })
    })
  }

  function tileOwnsOpenPanel(tileItem) {
    var item = tileItem ? tileItem.widgetItem : null
    return !!item && item.opened === true
  }

  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }

  function clampedCursor() {
    if (tileCount <= 0) return -1
    return Math.max(0, Math.min(cursor, tileCount - 1))
  }

  function selectDelta(dx, dy) {
    cursorActive = true
    cursor = Model.moveCursor(clampedCursor(), dx, dy, columns, tileCount)
    Qt.callLater(revealCursor)
  }

  function activate(which) {
    var index = clampedCursor()
    if (index < 0) return
    var tileItem = root.tileItems[String(index)]
    if (tileItem && typeof tileItem.activate === "function") tileItem.activate(Qt.LeftButton)
    else if (tray) tray.activate(displayTiles[index], which)
  }

  function activateTile(tile, button) {
    var index = -1
    for (var i = 0; i < displayTiles.length; i++) if (displayTiles[i] === tile) index = i
    var tileItem = index >= 0 ? root.tileItems[String(index)] : null
    if (tileItem && typeof tileItem.activate === "function") { tileItem.activate(button); return }
    if (!tray) return
    var which = button === Qt.RightButton ? "right"
      : (button === Qt.MiddleButton ? "middle" : "left")
    tray.activate(tile, which)
  }

  function openFinder(query) {
    finder.open(query === undefined ? "" : String(query || ""))
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function revealCursor() {
    var flick = root.flickItem
    var content = root.flickContentItem
    if (!flick || !content) return
    var tileItem = root.tileItems[String(clampedCursor())]
    if (!tileItem) return
    var point = tileItem.mapToItem(content, 0, 0)
    if (point.y < flick.contentY)
      flick.contentY = Math.max(0, point.y - Style.space(8))
    else if (point.y + tileItem.height > flick.contentY + flick.height)
      flick.contentY = point.y + tileItem.height - flick.height + Style.space(8)
  }

  onTileCountChanged: cursor = Math.max(0, Math.min(cursor, Math.max(0, tileCount - 1)))

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function focus(tileId: string): void { root.openAt(tileId) }
    function pick(tileId: string): void { root.pick(tileId) }
    function find(query: string): void { root.openFinder(query) }
  }

  TrayFinder {
    id: finder

    tray: root.tray
    host: root
  }

  Loader {
    id: panelLoader
    active: root.canOpen
    sourceComponent: panelWindow
  }

  Component {
    id: panelWindow

    KeyboardPanel {
      id: panel

      anchorItem: root.anchorItem
      owner: root.barIdentity
      bar: root.bar
      open: root.opened
      focusTarget: keyCatcher
      contentWidth: panel.fittedContentWidth(root.desiredWidth)
      contentHeight: panel.cappedContentHeight(root.desiredHeight)

      PanelKeyCatcher {
        id: keyCatcher

        anchors.fill: parent

        onMoveRequested: function(dx, dy) { root.selectDelta(dx, dy) }
        onActivateRequested: root.activate("left")
        onCloseRequested: root.close()
        onTabRequested: function(direction) { root.switchPanel(direction) }
        onTextKey: function(t) {
          if (t === "r" || t === "R") { if (root.tray) root.tray.refreshAll() }
        }

        Flickable {
          id: flick

          anchors.fill: parent
          contentWidth: width
          contentHeight: Math.max(flickContent.implicitHeight, height)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick

          Component.onCompleted: {
            root.flickItem = flick
            root.flickContentItem = flickContent
          }
          Component.onDestruction: {
            root.flickItem = null
            root.flickContentItem = null
          }

          Column {
            id: flickContent

            width: flick.width
            spacing: Style.space(14)

            Repeater {
              model: root.sections

              delegate: Column {
                required property var modelData

                width: parent ? parent.width : 0
                spacing: Style.space(6)

                PanelSectionHeader {
                  width: parent.width
                  visible: String(modelData.name || "") !== ""
                  text: String(modelData.name || "")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Grid {
                  anchors.horizontalCenter: parent.horizontalCenter
                  columns: root.columns
                  spacing: root.spacing

                  Repeater {
                    id: sectionRepeater

                    model: modelData.items

                    delegate: Tile {
                      required property var modelData
                      required property int index

                      host: root
                      position: modelData.position
                      tile: modelData.tile
                      state: root.tray ? root.tray.stateFor(String(modelData.tile.id)) : ({ "text": "", "tooltip": "", "active": false })
                      tray: root.tray
                      bar: root.bar
                      showLabels: root.config.showLabels
                      tileWidth: root.config.tileWidth
                      tileHeight: root.config.tileHeight
                      fontFamily: root.fontFamily
                      foreground: root.foreground
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: root.tileCount === 0
              textFormat: Text.PlainText
              text: "No tiles yet — add items to this tray entry in shell.json."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
