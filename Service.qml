pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null

  readonly property string pluginId: "io.github.tomfaulkner.tray"

  property var settings: ({})
  property bool initialized: false

  readonly property var config: Model.normalizeSettings(settings)
  readonly property var items: config.items
  readonly property int columns: config.columns
  readonly property var tileSettings: config.tiles
  readonly property var widgetCatalog: root.barWidgetRegistry ? root.barWidgetRegistry.widgets : ({})

  property var states: ({})

  readonly property int attention: Model.attentionCount(root.items, root.states)

  readonly property var hostShell: QtObject {
    property string pluginId: root.pluginId

    function serviceFor(id) {
      return String(id || "") === root.pluginId ? root : null
    }

    function firstPartyServiceFor(id) { return null }

    function summon(id, payloadJson) { root.ipc("summon", id, payloadJson); return true }
    function hide(id) { root.ipc("hide", id, ""); return true }
    function toggle(id, payloadJson) { root.ipc("toggle", id, payloadJson); return true }
    function isPluginOpen(id) { return false }

    function updateEntryInline(id, settings) { return root.persistTileSettings(id, settings) }
    function mutateShellConfig(mutator) { return false }
  }

  Component.onCompleted: root.initialized = true

  function componentFor(id) {
    var entry = root.widgetCatalog[String(id || "")]
    return entry ? entry.component : null
  }

  function hasWidget(id) {
    return root.widgetCatalog[String(id || "")] !== undefined
  }

  function settingsFor(id) {
    var key = String(id || "")
    var item = null
    for (var i = 0; i < root.items.length; i++) {
      if (root.items[i].id === key) item = root.items[i]
    }
    return Model.mergedSettings(item ? item.settings : ({}), root.tileSettings[key])
  }

  function ipc(verb, id, payloadJson) {
    var target = String(id || "")
    if (target === "") return
    var args = ["omarchy-shell", "shell", String(verb || ""), target]
    var body = payloadJson === undefined || payloadJson === null ? "" : String(payloadJson)
    if (body !== "") args.push(body)
    ipcRunner.createObject(root, { command: args })
  }

  function persistTileSettings(id, settings) {
    var key = String(id || "")
    if (key === "" || !root.shell || typeof root.shell.updateEntryInline !== "function") return false

    var entry = { id: root.pluginId }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]

    var tiles = ({})
    var current = entry.tiles && typeof entry.tiles === "object" ? entry.tiles : ({})
    for (var tileKey in current) tiles[tileKey] = current[tileKey]

    var prior = tiles[key] && typeof tiles[key] === "object" ? tiles[key] : ({})
    var merged = ({})
    for (var priorKey in prior) merged[priorKey] = prior[priorKey]
    var next = settings && typeof settings === "object" ? settings : ({})
    for (var nextKey in next) if (nextKey !== "id") merged[nextKey] = next[nextKey]

    tiles[key] = merged
    entry.tiles = tiles
    return root.shell.updateEntryInline(root.pluginId, entry)
  }

  function stateFor(id) {
    var state = root.states[String(id || "")]
    return state ? state : Model.emptyState()
  }

  function setState(id, next) {
    var key = String(id || "")
    if (!key) return
    var copy = ({})
    for (var existing in root.states) copy[existing] = root.states[existing]
    copy[key] = {
      text: next && next.text !== undefined ? String(next.text) : "",
      tooltip: next && next.tooltip !== undefined ? String(next.tooltip) : "",
      active: !!(next && next.active)
    }
    root.states = copy
  }

  function run(command) {
    var text = String(command || "").trim()
    if (text === "") return
    runner.createObject(root, { command: ["bash", "-lc", text] })
  }

  function activate(tile, which) {
    if (!tile) return
    var command = Model.commandFor(tile, which)
    if (command !== "") {
      root.run(command)
      return
    }
    if (tile.type === "command") root.refreshTile(tile.id)
  }

  function refreshAll() {
    for (var i = 0; i < pollers.count; i++) {
      var poller = pollers.objectAt(i)
      if (poller && poller.poll) poller.poll()
    }
  }

  function refreshTile(id) {
    for (var i = 0; i < pollers.count; i++) {
      var poller = pollers.objectAt(i)
      if (poller && poller.tileId === String(id || "") && poller.poll) poller.poll()
    }
  }

  Instantiator {
    id: pollers

    model: root.items

    delegate: QtObject {
      id: poller

      required property var modelData

      readonly property var tile: modelData
      readonly property string tileId: poller.tile ? String(poller.tile.id) : ""
      readonly property bool polling: !!poller.tile
        && poller.tile.type === "command"
        && String(poller.tile.exec || "") !== ""

      function poll() {
        if (!poller.polling) return
        if (!process.running) process.running = true
      }

      property var process: Process {
        command: ["bash", "-lc", poller.polling ? String(poller.tile.exec) : ""]
        running: false
        stdout: StdioCollector {
          waitForEnd: true
          onStreamFinished: if (poller.polling)
            root.setState(poller.tileId, Model.parseCommandOutput(text, poller.tile))
        }
      }

      property var timer: Timer {
        interval: Math.max(1, poller.tile ? Number(poller.tile.interval) : 30) * 1000
        running: poller.polling
        repeat: true
        triggeredOnStart: true
        onTriggered: poller.poll()
      }
    }
  }

  Component {
    id: runner

    Process {
      id: process

      running: true
      stdout: StdioCollector { waitForEnd: true }
      stderr: StdioCollector { waitForEnd: true }
      onExited: Qt.callLater(function() { process.destroy() })
    }
  }

  Component {
    id: ipcRunner

    Process {
      id: ipcProcess

      running: true
      stdout: StdioCollector { waitForEnd: true }
      stderr: StdioCollector { waitForEnd: true }
      onExited: Qt.callLater(function() { ipcProcess.destroy() })
    }
  }
}
