"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\s*\.pragma library\s*/m, "")
const sandbox = { module: { exports: {} }, exports: {} }
sandbox.module.exports = sandbox.exports
vm.runInNewContext(source, sandbox, { filename: "Model.js" })
const Model = sandbox.module.exports

function same(actual, expected) {
  assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected))
}

function testQmlArrayLikeConfig() {
  const arrayLike = { 0: { id: "a", type: "widget" }, 1: { id: "b" }, length: 2 }
  const config = Model.normalizeSettings({ items: arrayLike })
  same(config.items.map(i => i.id), ["a", "b"])
  assert.strictEqual(Model.attentionCount(arrayLike, { a: { active: true } }), 1)
}

function testDefaults() {
  const config = Model.normalizeSettings(null)
  assert.strictEqual(config.label, "Tray")
  assert.strictEqual(config.columns, 4)
  assert.strictEqual(config.showLabels, true)
  same(config.items, [])
}

function testItemTypes() {
  const config = Model.normalizeSettings({
    items: [
      { id: "a", type: "command", exec: "echo hi", interval: 5 },
      { id: "b", type: "action", onClick: "true" },
      { id: "c", type: "qml", source: "~/.config/omarchy/tray/tiles/c.qml" },
      { id: "d", type: "nonsense" }
    ]
  })
  same(config.items.map(i => i.type), ["command", "action", "qml", "action"])
  assert.strictEqual(config.items[0].interval, 5)
  assert.strictEqual(config.items[3].onClick, "")
}

function testItemIdsFallBackToIndex() {
  const config = Model.normalizeSettings({ items: [{ type: "action" }, { type: "action" }] })
  same(config.items.map(i => i.id), ["tile1", "tile2"])
}

function testDuplicateIdsAreUnique() {
  const config = Model.normalizeSettings({ items: [{ id: "a" }, { id: "a" }] })
  assert.notStrictEqual(config.items[0].id, config.items[1].id)
}

function testNumericStringsAndClamping() {
  const config = Model.normalizeSettings({ columns: "3", tileWidth: "10", tileHeight: 9999, showLabels: "no" })
  assert.strictEqual(config.columns, 3)
  assert.strictEqual(config.tileWidth, 48)
  assert.strictEqual(config.tileHeight, 480)
  assert.strictEqual(config.showLabels, false)
}

function testPlainTextOutput() {
  const out = Model.parseCommandOutput(" 42%\n", { tooltip: "Load" })
  assert.strictEqual(out.text, "42%")
  assert.strictEqual(out.tooltip, "Load")
  assert.strictEqual(out.active, false)
}

function testWaybarJsonOutput() {
  const out = Model.parseCommandOutput('{"text":"3","tooltip":"3 down","class":"active"}', {})
  assert.strictEqual(out.text, "3")
  assert.strictEqual(out.tooltip, "3 down")
  assert.strictEqual(out.active, true)
}

function testInactiveClassAndArrayClass() {
  assert.strictEqual(Model.parseCommandOutput('{"text":"0","class":"idle"}', {}).active, false)
  assert.strictEqual(Model.parseCommandOutput('{"text":"0","class":["active"]}', {}).active, true)
}

function testEmptyOutputKeepsTooltip() {
  const out = Model.parseCommandOutput("   ", { tooltip: "VPN" })
  assert.strictEqual(out.text, "")
  assert.strictEqual(out.tooltip, "VPN")
  assert.strictEqual(out.active, false)
}

function testCommandForFallsBackToClick() {
  const tile = { onClick: "left-cmd", onRightClick: "", onMiddleClick: "" }
  assert.strictEqual(Model.commandFor(tile, "left"), "left-cmd")
  assert.strictEqual(Model.commandFor(tile, "right"), "left-cmd")
  assert.strictEqual(Model.commandFor(tile, "middle"), "left-cmd")
  assert.strictEqual(Model.commandFor(null, "left"), "")
}

function testGridGeometry() {
  assert.strictEqual(Model.gridColumns(0, 4), 1)
  assert.strictEqual(Model.gridColumns(2, 6), 2)
  assert.strictEqual(Model.gridRows(7, 4), 2)
}

function testCursorMovement() {
  assert.strictEqual(Model.moveCursor(0, -1, 0, 4, 6), 5)
  assert.strictEqual(Model.moveCursor(5, 1, 0, 4, 6), 0)
  assert.strictEqual(Model.moveCursor(0, 0, 1, 4, 6), 4)
  assert.strictEqual(Model.moveCursor(5, 0, 1, 4, 6), 1)
  assert.strictEqual(Model.moveCursor(1, 1, 0, 4, 6), 2)
  assert.strictEqual(Model.moveCursor(-1, 0, 0, 4, 0), -1)
}

function testAttentionCount() {
  const items = [{ id: "a" }, { id: "b" }, { id: "c" }]
  const states = { a: { active: true }, b: { active: false } }
  assert.strictEqual(Model.attentionCount(items, states), 1)
  assert.strictEqual(Model.attentionCount(items, null), 0)
}

function testStringList() {
  same(Model.stringList([" Games ", "Apps", "Games", "", null]), ["Games", "Apps"])
  same(Model.stringList(null), [])
}

function testGroupOrdering() {
  const items = [
    { id: "a", group: "Games" },
    { id: "b", group: "" },
    { id: "c", group: "Servers" },
    { id: "d", group: "Games" }
  ]
  same(Model.displayTiles(items, ["Servers", "Games"]).map(t => t.id), ["b", "c", "a", "d"])
  const sections = Model.sections(items, ["Servers", "Games"])
  same(sections.map(s => s.name), ["", "Servers", "Games"])
  same(sections.map(s => s.items.map(r => r.tile.id)), [["b"], ["c"], ["a", "d"]])
  // Positions follow the display order, not the written order.
  same(sections.flatMap(s => s.items.map(r => r.position)), [0, 1, 2, 3])
}

function testFuzzy() {
  assert.ok(Model.fuzzyScore("Crossy Hop", "crh") > 0)
  assert.strictEqual(Model.fuzzyScore("Crossy Hop", "zzz"), 0)
  assert.strictEqual(Model.fuzzyScore("Crossy Hop", ""), 1)
  assert.ok(Model.fuzzyScore("Crossy Hop", "crossy") > Model.fuzzyScore("Crossy Hop", "crh"))
}

function testFilterTiles() {
  const items = [
    { id: "crossy", label: "Crossy Hop", group: "Games" },
    { id: "unifi", label: "UniFi", group: "Servers" },
    { id: "pinball", label: "Neon Cadet", group: "Games" }
  ]
  same(Model.filterTiles(items, "").map(r => r.tile.id), ["crossy", "unifi", "pinball"])
  same(Model.filterTiles(items, "games").map(r => r.tile.id), ["crossy", "pinball"])
  same(Model.filterTiles(items, "unifi").map(r => r.tile.id), ["unifi"])
  same(Model.filterTiles(items, "nope"), [])
}

function testNames() {
  assert.strictEqual(Model.shortName({ id: "io.github.tomfaulkner.crossy-hop" }), "crossy-hop")
  assert.strictEqual(Model.shortName({ id: "terminal.minesweeper" }), "minesweeper")
  assert.strictEqual(Model.shortName({ id: "hass" }), "hass")
  // A label wins: it is the name the user chose.
  assert.strictEqual(Model.shortName({ id: "terminal.minesweeper", label: "Mines" }), "Mines")
  assert.strictEqual(Model.fullName({ id: "terminal.minesweeper" }), "terminal.minesweeper")
  assert.strictEqual(Model.fullName({ id: "hass" }), "")
  assert.strictEqual(Model.detailFor({ group: "Games", type: "widget" }), "Games · widget")
  assert.strictEqual(Model.detailFor({ type: "action" }), "action")
}

const tests = [
  testNames,
  testStringList,
  testGroupOrdering,
  testFuzzy,
  testFilterTiles,
  testQmlArrayLikeConfig,
  testDefaults,
  testItemTypes,
  testItemIdsFallBackToIndex,
  testDuplicateIdsAreUnique,
  testNumericStringsAndClamping,
  testPlainTextOutput,
  testWaybarJsonOutput,
  testInactiveClassAndArrayClass,
  testEmptyOutputKeepsTooltip,
  testCommandForFallsBackToClick,
  testGridGeometry,
  testCursorMovement,
  testAttentionCount
]

let failed = 0
for (const test of tests) {
  try {
    test()
    console.log("ok   " + test.name)
  } catch (error) {
    failed++
    console.error("FAIL " + test.name + "\n     " + error.message)
  }
}
process.exit(failed === 0 ? 0 : 1)
