import QtQuick
import qs.Commons

Item {
  id: root

  property var tile: null
  property var tray: null
  property var bar: null
  property var tileState: ({})

  readonly property color foreground: Color.popups.text

  Column {
    anchors.centerIn: parent
    spacing: Style.space(2)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: "GPU"
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: "yours to fill"
      color: Qt.darker(root.foreground, 1.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }
  }
}
