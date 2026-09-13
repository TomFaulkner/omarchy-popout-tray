pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "io.github.tomfaulkner.tray"
  ipcTarget: "io.github.tomfaulkner.tray"
  manageIpc: true

  readonly property bool vertical: bar ? bar.vertical === true : false
  property int trayAttempt: 0
  readonly property var tray: {
    var attempt = root.trayAttempt
    return bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  }
  readonly property bool ready: tray !== null
  readonly property color led: bar ? bar.barForeground : Color.foreground
  readonly property string glyph: ready ? String(tray.config.glyph) : "⋯"
  readonly property int attention: ready ? tray.attention : 0
  readonly property int tileCount: ready ? tray.items.length : 0

  function open() { trayPanel.open() }
  function close() { trayPanel.close() }
  function toggle() { trayPanel.toggle() }
  function togglePanel() { trayPanel.toggle() }
  function closeForPopoutSwitch() { trayPanel.closeForPopoutSwitch() }

  onSettingsChanged: if (root.ready) root.tray.settings = settings
  onTrayChanged: if (root.ready) root.tray.settings = settings

  Component.onCompleted: if (root.ready) root.tray.settings = settings

  Timer {
    interval: 400
    repeat: true
    running: !root.ready && root.trayAttempt < 40
    onTriggered: root.trayAttempt = root.trayAttempt + 1
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property real openPanelIndicatorWidth: content.implicitWidth
  readonly property real openPanelIndicatorHeight: content.implicitHeight

  WidgetButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical
      ? -1
      : Math.round(content.implicitWidth + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical
      ? Math.round(content.implicitHeight + button.scaledVerticalPadding * 2)
      : -1
    tooltipText: root.ready
      ? (root.tray.config.label
        + "\n" + root.tileCount + (root.tileCount === 1 ? " tile" : " tiles")
        + (root.attention > 0 ? "\n" + root.attention + " need attention" : "")
        + "\nLeft: open · Right: refresh")
      : "Tray"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
      else if (buttonCode === Qt.RightButton && root.ready) root.tray.refreshAll()
    }

    Row {
      id: content

      anchors.centerIn: parent
      z: 1
      spacing: Style.space(3)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.glyph
        color: root.led
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.attention > 0
        width: Style.space(5)
        height: Style.space(5)
        radius: width / 2
        color: root.bar ? root.bar.urgent : Color.urgent
      }
    }
  }

  TrayPanel {
    id: trayPanel

    bar: root.bar
    settings: root.settings
    anchorItem: button
    hostWidget: root
    tray: root.tray
  }
}
