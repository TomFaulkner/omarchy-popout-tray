pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var tile: null
  property var state: ({ "text": "", "tooltip": "", "active": false })
  property var tray: null
  property var bar: null
  property var host: null
  property int position: -1
  property bool selected: false
  property bool showLabels: true
  property int tileWidth: 96
  property int tileHeight: 76
  property string fontFamily: Style.font.family
  property color foreground: Color.popups.text

  signal activated(int button)

  readonly property string tileId: root.tile ? String(root.tile.id) : ""
  readonly property string tileType: root.tile ? String(root.tile.type) : "action"
  readonly property string label: root.tile ? String(root.tile.label || root.tileId) : ""
  readonly property string glyph: root.tile ? String(root.tile.glyph || "") : ""
  readonly property string text: root.state && root.state.text !== undefined ? String(root.state.text) : ""
  readonly property string tooltip: {
    var stateTooltip = root.state ? String(root.state.tooltip || "") : ""
    if (stateTooltip !== "") return stateTooltip
    return root.tile ? String(root.tile.tooltip || root.label) : ""
  }
  readonly property bool active: !!(root.state && root.state.active)
  readonly property color accent: root.bar ? root.bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(root.foreground, 1.5)
  readonly property bool hovered: mouseArea.containsMouse || tileHover.hovered
  readonly property int hPad: Style.space(8)
  readonly property int vPad: Style.space(4)

  readonly property bool isWidget: root.tileType === "widget"
  readonly property var catalog: root.tray ? root.tray.widgetCatalog : ({})
  readonly property var widgetEntry: root.catalog[root.tileId] !== undefined ? root.catalog[root.tileId] : null
  readonly property var widgetComponent: root.isWidget && root.widgetEntry ? root.widgetEntry.component : null
  readonly property var persisted: root.tray ? root.tray.tileSettings : ({})
  readonly property var widgetSettings: {
    var out = ({})
    var base = root.tile && root.tile.settings ? root.tile.settings : ({})
    for (var key in base) out[key] = base[key]
    var saved = root.persisted[root.tileId]
    if (saved && typeof saved === "object") {
      for (var savedKey in saved) out[savedKey] = saved[savedKey]
    }
    return out
  }

  readonly property bool selectedNow: root.host
    ? (root.host.cursorActive && root.host.cursor === root.position)
    : root.selected
  readonly property bool autoSize: root.isWidget
    && root.widgetItem !== null
    && (!root.tile || root.tile.autoSize !== false)
  readonly property bool missing: root.isWidget && root.widgetComponent === null
  readonly property bool failed: root.isWidget && root.widgetStatus === Loader.Error
  property alias customItem: customLoader.item

  property var hostApi: null
  property var widgetItem: null
  property int widgetStatus: Loader.Null
  property var linkedPanels: []

  readonly property var hostAnchor: root.host && root.host.anchorItem
    ? root.host.anchorItem : null

  implicitWidth: root.width
  implicitHeight: root.height
  width: root.autoSize
    ? Math.max(Style.space(32), (root.widgetItem ? root.widgetItem.implicitWidth : 0) + root.hPad * 2)
    : root.tileWidth
  height: root.autoSize
    ? Math.max(Style.space(26), (root.widgetItem ? root.widgetItem.implicitHeight : 0) + root.vPad * 2)
    : root.tileHeight

  Component.onCompleted: {
    if (root.host && root.position >= 0) root.host.registerTile(root.position, root)
    root.ensureHostApi()
  }
  Component.onDestruction: if (root.host && root.position >= 0) root.host.unregisterTile(root.position, root)
  onBarChanged: root.ensureHostApi()
  onHoveredChanged: if (root.hovered && root.host && root.position >= 0) root.host.cursor = root.position
  onWidgetSettingsChanged: Qt.callLater(root.injectWidget)
  onHostApiChanged: Qt.callLater(root.injectWidget)
  onWidgetItemChanged: {
    anchorScan.shots = 0
    anchorScan.restart()
  }

  function ensureHostApi() {
    if (root.hostApi !== null || root.bar === null) return
    root.hostApi = hostApiComponent.createObject(root, {
      pluginId: root.tray ? root.tray.pluginId : "io.github.tomfaulkner.tray",
      moduleName: root.tileId,
      source: root.bar,
      shell: root.tray ? root.tray.hostShell : null
    })
  }

  function injectWidget() {
    var item = root.widgetItem
    if (!item) return
    if ("bar" in item && root.hostApi) item.bar = root.hostApi
    if ("moduleName" in item) item.moduleName = root.tileId
    if ("settings" in item) item.settings = root.widgetSettings
    root.syncHostPanels()
  }

  function activate(button) {
    var item = root.widgetItem
    anchorScan.shots = 0
    anchorScan.restart()
    if (item) {
      if (typeof item.toggle === "function") { item.toggle(); return }
      if (typeof item.open === "function") { item.open(); return }
      if (typeof item.play === "function") { item.play(); return }
      // Most bar widgets are a button that runs something on press and expose
      // no open/close at all. Pressing that button is what a click would do —
      // the bar does exactly this when it handles a click itself.
      var pressable = root.pressableTarget(item, 0)
      if (pressable) {
        pressable.triggerPress(button === undefined ? Qt.LeftButton : button)
        return
      }
      return
    }
    root.activated(button)
  }

  function collectPanels(object, out, depth) {
    if (!object || depth > 8) return
    var kids = []
    try {
      kids = object.data && object.data.length ? object.data : (object.children || [])
    } catch (e) { return }
    for (var i = 0; i < kids.length; i++) {
      var child = kids[i]
      if (!child) continue
      var isPanel = false
      try { isPanel = child.cardOrigin !== undefined } catch (e) { isPanel = false }
      if (isPanel) out.push(child)
      collectPanels(child, out, depth + 1)
    }
  }

  function syncHostPanels() {
    if (!root.hostAnchor) return
    var panels = []
    collectPanels(root.widgetItem, panels, 0)
    for (var i = 0; i < panels.length; i++) root.hostPanel(panels[i])
  }

  function hostPanel(panel) {
    if (!panel || root.linkedPanels.indexOf(panel) !== -1) return
    var next = root.linkedPanels.slice()
    next.push(panel)
    root.linkedPanels = next
    anchorGuard.createObject(root, { target: panel })
    if (panel.anchorItem !== root.hostAnchor) panel.anchorItem = root.hostAnchor
  }

  function pressableTarget(item, depth) {
    if (!item || depth > 6) return null
    if (typeof item.triggerPress === "function"
      && item.visible !== false && item.pressable !== false && item.concealed !== true)
      return item
    var children = item.children || []
    for (var i = children.length - 1; i >= 0; i--) {
      var found = root.pressableTarget(children[i], depth + 1)
      if (found) return found
    }
    return null
  }

  BorderSurface {
    id: surface

    anchors.fill: parent
    color: root.selectedNow
      ? Style.normalFillFor(root.foreground, Color.accent)
      : (root.hovered && !root.isWidget ? Style.normalFillFor(root.foreground, root.foreground) : "transparent")
    borderSpec: Border.flat(root.selectedNow ? Color.accent : root.dim, 1)
    radius: Style.cornerRadius
    opacity: 0.9
  }

  Loader {
    id: widgetLoader

    anchors.centerIn: parent
    z: 1
    active: root.widgetComponent !== null
    sourceComponent: root.widgetComponent

    onStatusChanged: root.widgetStatus = status
    onItemChanged: root.widgetItem = item
    onLoaded: {
      root.widgetItem = item
      root.injectWidget()
      Qt.callLater(root.injectWidget)
    }
  }

  Loader {
    id: customLoader

    anchors.fill: parent
    z: 1
    anchors.margins: Style.space(6)
    active: root.tileType === "qml" && !root.missing
    source: root.tile && root.tile.source ? root.tile.source : ""

    onLoaded: {
      if ("tile" in item) item.tile = root.tile
      if ("tray" in item) item.tray = root.tray
      if ("bar" in item) item.bar = root.bar
      if ("tileState" in item) item.tileState = Qt.binding(function() { return root.state })
    }
  }

  Column {
    anchors.centerIn: parent
    anchors.margins: Style.space(6)
    spacing: Style.space(2)
    visible: !customLoader.active
      && (root.tileType !== "widget" || root.widgetItem === null)
    width: parent.width - Style.space(12)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      visible: text !== ""
      text: root.glyph !== "" ? root.glyph : (root.text !== "" ? root.text : "?")
      color: root.active ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      renderType: Text.NativeRendering
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      width: parent.width
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      visible: root.showLabels && text !== ""
      text: root.text !== "" && root.glyph !== "" ? root.text : root.label
      color: root.active ? root.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      width: parent.width
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      visible: root.missing || root.failed || (root.isWidget && root.widgetItem === null)
      text: root.failed ? "failed to load" : (root.missing ? "not installed" : "loading")
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }
  }

  HoverHandler {
    id: tileHover

    enabled: root.isWidget || root.tileType === "qml"
  }

  MouseArea {
    id: mouseArea

    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) { root.activate(mouse.button) }
  }

  PanelToolTip {
    visible: root.hovered && root.tooltip !== "" && !root.isWidget
    text: root.tooltip
    fontFamily: root.fontFamily
  }

  Component {
    id: hostApiComponent

    HostBarApi { }
  }

  Component {
    id: anchorGuard

    Connections {
      ignoreUnknownSignals: true

      function onAnchorItemChanged() {
        if (!target || !root.hostAnchor) return
        if (target.anchorItem !== root.hostAnchor) target.anchorItem = root.hostAnchor
      }
    }
  }

  Timer {
    id: anchorScan

    interval: 120
    repeat: true
    running: false
    property int shots: 0

    onTriggered: {
      root.syncHostPanels()
      anchorScan.shots += 1
      if (anchorScan.shots >= 5) anchorScan.stop()
    }
  }
}
