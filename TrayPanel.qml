pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "io.github.tomfaulkner.tray"
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
  readonly property int tileCount: items.length
  readonly property int columns: Model.gridColumns(tileCount, config.columns)
  readonly property int rows: Model.gridRows(tileCount, columns)
  readonly property int spacing: Style.space(8)
  readonly property int desiredWidth: Math.max(Style.space(200),
    columns * config.tileWidth + (columns - 1) * spacing + Style.space(24))
  readonly property int desiredHeight: Math.max(Style.space(120),
    Style.space(56) + rows * config.tileHeight + (rows - 1) * spacing + Style.space(20))
  readonly property bool canOpen: bar !== null && anchorItem !== null
  readonly property int attention: ready ? tray.attention : 0

  property int cursor: 0
  property bool cursorActive: true

  function open() {
    if (!canOpen) return
    cursor = 0
    cursorActive = true
    controller.show()
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
  }

  function activate(which) {
    var index = clampedCursor()
    if (index < 0) return
    var tileItem = gridRepeater.itemAt(index)
    if (tileItem && typeof tileItem.activate === "function") tileItem.activate(Qt.LeftButton)
    else if (tray) tray.activate(items[index], which)
  }

  function activateTile(tile, button) {
    var index = -1
    for (var i = 0; i < items.length; i++) if (items[i] === tile) index = i
    var tileItem = index >= 0 ? gridRepeater.itemAt(index) : null
    if (tileItem && typeof tileItem.activate === "function") { tileItem.activate(button); return }
    if (!tray) return
    var which = button === Qt.RightButton ? "right"
      : (button === Qt.MiddleButton ? "middle" : "left")
    tray.activate(tile, which)
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  onTileCountChanged: cursor = Math.max(0, Math.min(cursor, Math.max(0, tileCount - 1)))

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
          else if (t === " ") root.activate("left")
        }

        Column {
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.config.label
            meta: root.tileCount === 1 ? "1 tile" : root.tileCount + " tiles"
            detail: root.attention > 0 ? root.attention + " need attention" : "Left: activate · R: refresh"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: root.columns
            spacing: root.spacing

            Repeater {
              id: gridRepeater

              model: root.items

              delegate: Tile {
                required property var modelData
                required property int index

                tile: modelData
                state: root.tray ? root.tray.stateFor(String(modelData.id)) : ({ "text": "", "tooltip": "", "active": false })
                tray: root.tray
                bar: root.bar
                selected: root.cursorActive && root.clampedCursor() === index
                showLabels: root.config.showLabels
                tileWidth: root.config.tileWidth
                tileHeight: root.config.tileHeight
                fontFamily: root.fontFamily
                foreground: root.foreground

                onActivated: function(button) { root.activateTile(modelData, button) }
                onHoveredChanged: if (hovered) root.cursor = index
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
