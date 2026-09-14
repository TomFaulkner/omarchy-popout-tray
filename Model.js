.pragma library

var TILE_TYPES = ["command", "action", "qml", "widget"]

var TILE_RESERVED = [
  "id", "name", "type", "label", "tooltip", "glyph", "icon", "text",
  "exec", "interval", "onClick", "onRightClick", "onMiddleClick", "source",
  "tileWidth", "tileHeight", "autoSize", "settings"
]

var DEFAULTS = {
  label: "Tray",
  glyph: "⋯",
  columns: 4,
  tileWidth: 96,
  tileHeight: 76,
  showLabels: true
}

function defaults() {
  return {
    label: DEFAULTS.label,
    glyph: DEFAULTS.glyph,
    columns: DEFAULTS.columns,
    tileWidth: DEFAULTS.tileWidth,
    tileHeight: DEFAULTS.tileHeight,
    showLabels: DEFAULTS.showLabels,
    items: []
  }
}

function isList(value) {
  return !!value && typeof value === "object" && typeof value.length === "number"
}

function str(value, fallback) {
  if (value === undefined || value === null) return fallback
  var text = String(value)
  return text === "" ? fallback : text
}

function bool(value, fallback) {
  if (value === undefined || value === null) return fallback
  if (typeof value === "boolean") return value
  if (typeof value === "number") return value !== 0
  var text = String(value).trim().toLowerCase()
  if (text === "true" || text === "yes" || text === "on" || text === "1") return true
  if (text === "false" || text === "no" || text === "off" || text === "0") return false
  return fallback
}

function int(value, fallback, min, max) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  number = Math.round(number)
  if (min !== undefined && number < min) number = min
  if (max !== undefined && number > max) number = max
  return number
}

function tileType(value) {
  var type = String(value || "").trim().toLowerCase()
  return TILE_TYPES.indexOf(type) !== -1 ? type : "action"
}

function normalizeItem(raw, index) {
  if (!raw || typeof raw !== "object") return null
  var id = str(raw.id, str(raw.name, "tile" + (index + 1)))
  return {
    id: id,
    type: tileType(raw.type),
    label: str(raw.label, str(raw.name, id)),
    tooltip: str(raw.tooltip, ""),
    glyph: str(raw.glyph, str(raw.icon, str(raw.text, ""))),
    exec: str(raw.exec, ""),
    interval: int(raw.interval, 30, 1, 86400),
    onClick: str(raw.onClick, ""),
    onRightClick: str(raw.onRightClick, ""),
    onMiddleClick: str(raw.onMiddleClick, ""),
    source: str(raw.source, ""),
    group: str(raw.group, ""),
    autoSize: bool(raw.autoSize, true),
    settings: tileSettings(raw)
  }
}

function normalizeItems(raw) {
  var items = []
  if (!isList(raw)) return items
  var seen = {}
  for (var i = 0; i < raw.length; i++) {
    var item = normalizeItem(raw[i], i)
    if (!item) continue
    if (seen[item.id]) item.id = item.id + "-" + i
    seen[item.id] = true
    items.push(item)
  }
  return items
}

function stringList(value) {
  var out = []
  if (!isList(value)) return out
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    var name = str(value[i], "").trim()
    if (name === "" || seen[name]) continue
    seen[name] = true
    out.push(name)
  }
  return out
}

function groupNames(items, groupOrder) {
  var present = []
  var seen = {}
  for (var i = 0; i < items.length; i++) {
    var name = str(items[i].group, "")
    if (seen[name]) continue
    seen[name] = true
    present.push(name)
  }
  var ordered = []
  var taken = {}
  // Ungrouped tiles lead, so a tray that names no groups reads top to bottom
  // in the order its items were written.
  if (present.indexOf("") !== -1) {
    ordered.push("")
    taken[""] = true
  }
  var order = stringList(groupOrder)
  for (var o = 0; o < order.length; o++) {
    if (present.indexOf(order[o]) === -1) continue
    ordered.push(order[o])
    taken[order[o]] = true
  }
  for (var p = 0; p < present.length; p++) {
    if (taken[present[p]]) continue
    ordered.push(present[p])
  }
  return ordered
}

function displayTiles(items, groupOrder) {
  var out = []
  if (!isList(items)) return out
  var names = groupNames(items, groupOrder)
  for (var n = 0; n < names.length; n++) {
    for (var i = 0; i < items.length; i++) {
      if (str(items[i].group, "") === names[n]) out.push(items[i])
    }
  }
  return out
}

function sections(items, groupOrder) {
  var out = []
  if (!isList(items)) return out
  var names = groupNames(items, groupOrder)
  var position = 0
  for (var n = 0; n < names.length; n++) {
    var rows = []
    for (var i = 0; i < items.length; i++) {
      if (str(items[i].group, "") !== names[n]) continue
      rows.push({ tile: items[i], position: position })
      position += 1
    }
    out.push({ name: names[n], items: rows })
  }
  return out
}

// io.github.tomfaulkner.crossy-hop -> crossy-hop and terminal.minesweeper ->
// minesweeper: the owner prefix is what makes a list of plugin ids unreadable,
// and a label, when there is one, already says the useful part.
function shortName(tile) {
  var label = str(tile && tile.label, "")
  if (label !== "") return label
  var id = str(tile && tile.id, "")
  var parts = id.split(".")
  return parts.length > 1 ? parts[parts.length - 1] : id
}

function fullName(tile) {
  var id = str(tile && tile.id, "")
  var short = shortName(tile)
  return id !== "" && id !== short ? id : ""
}

function detailFor(tile) {
  var bits = []
  var group = str(tile && tile.group, "")
  if (group !== "") bits.push(group)
  bits.push(str(tile && tile.type, "action"))
  var tooltip = str(tile && tile.tooltip, "")
  if (tooltip !== "") bits.push(tooltip)
  return bits.join(" · ")
}

function fuzzyScore(text, needle) {
  var haystack = String(text || "").toLowerCase()
  var query = String(needle || "").toLowerCase().trim()
  if (query === "") return 1
  var score = 0
  var at = 0
  var streak = 0
  for (var q = 0; q < query.length; q++) {
    var ch = query.charAt(q)
    if (ch === " ") { streak = 0; continue }
    var found = haystack.indexOf(ch, at)
    if (found === -1) return 0
    streak = found === at ? streak + 1 : 0
    score += 10 + streak * 4 + (found === 0 || haystack.charAt(found - 1) === " " ? 6 : 0)
    at = found + 1
  }
  return score
}

function filterTiles(tiles, query) {
  var out = []
  if (!isList(tiles)) return out
  for (var i = 0; i < tiles.length; i++) {
    var tile = tiles[i]
    var label = str(tile.label, str(tile.id, ""))
    var haystack = label + " " + str(tile.group, "") + " " + str(tile.id, "")
    var score = fuzzyScore(haystack, query)
    if (score <= 0) continue
    out.push({ tile: tile, position: i, score: score })
  }
  out.sort(function(a, b) { return b.score - a.score || a.position - b.position })
  return out
}

function tileSettings(raw) {
  var out = ({})
  if (!raw || typeof raw !== "object") return out
  for (var key in raw) {
    if (TILE_RESERVED.indexOf(key) !== -1) continue
    out[key] = raw[key]
  }
  var nested = raw.settings
  if (nested && typeof nested === "object" && !Array.isArray(nested)) {
    for (var nestedKey in nested) out[nestedKey] = nested[nestedKey]
  }
  return out
}

function mergedSettings(inlineSettings, persisted) {
  var out = ({})
  var base = inlineSettings && typeof inlineSettings === "object" ? inlineSettings : ({})
  for (var key in base) out[key] = base[key]
  var overlay = persisted && typeof persisted === "object" ? persisted : ({})
  for (var overlayKey in overlay) out[overlayKey] = overlay[overlayKey]
  return out
}

function normalizeSettings(settings) {
  var raw = settings && typeof settings === "object" ? settings : {}
  var base = defaults()
  return {
    label: str(raw.label, base.label),
    glyph: str(raw.glyph, base.glyph),
    columns: int(raw.columns, base.columns, 1, 12),
    tileWidth: int(raw.tileWidth, base.tileWidth, 48, 480),
    tileHeight: int(raw.tileHeight, base.tileHeight, 40, 480),
    showLabels: bool(raw.showLabels, base.showLabels),
    tiles: raw.tiles && typeof raw.tiles === "object" && !Array.isArray(raw.tiles) ? raw.tiles : ({}),
    groups: stringList(raw.groups),
    items: normalizeItems(raw.items)
  }
}

function emptyState() {
  return { text: "", tooltip: "", active: false }
}

function parseCommandOutput(raw, tile) {
  var fallbackTooltip = tile ? String(tile.tooltip || "") : ""
  var text = String(raw || "").trim()
  if (text === "") return { text: "", tooltip: fallbackTooltip, active: false }

  var lines = text.split("\n")
  var data = null
  try {
    data = JSON.parse(lines[lines.length - 1])
  } catch (e) {
    data = null
  }
  if (!data || typeof data !== "object" || Array.isArray(data))
    return { text: text, tooltip: fallbackTooltip, active: false }

  var klass = data.class !== undefined && data.class !== null ? data.class : data.alt
  var active = false
  if (typeof klass === "string") active = klass === "active"
  else if (isList(klass) && klass.indexOf("active") !== -1) active = true

  return {
    text: data.text !== undefined && data.text !== null ? String(data.text) : "",
    tooltip: data.tooltip !== undefined && data.tooltip !== null
      ? String(data.tooltip) : fallbackTooltip,
    active: active
  }
}

function commandFor(tile, which) {
  if (!tile) return ""
  if (which === "right") return String(tile.onRightClick || tile.onClick || "")
  if (which === "middle") return String(tile.onMiddleClick || tile.onClick || "")
  return String(tile.onClick || "")
}

function gridColumns(count, configured) {
  if (count <= 0) return 1
  return Math.max(1, Math.min(int(configured, DEFAULTS.columns, 1, 12), count))
}

function gridRows(count, columns) {
  if (count <= 0) return 1
  return Math.max(1, Math.ceil(count / gridColumns(count, columns)))
}

function moveCursor(index, dx, dy, columns, count) {
  if (count <= 0) return -1
  var cols = gridColumns(count, columns)
  var rows = gridRows(count, cols)
  var current = index < 0 ? 0 : index
  var row = Math.floor(current / cols)
  var col = current % cols

  if (dx !== 0) {
    var next = current + dx
    if (next < 0) return count - 1
    if (next >= count) return 0
    return next
  }

  if (dy !== 0) {
    var targetRow = (row + dy + rows) % rows
    var candidate = targetRow * cols + col
    if (candidate >= count) candidate = count - 1
    return candidate >= 0 ? candidate : current
  }

  return current
}

function attentionCount(items, states) {
  var count = 0
  if (!isList(items)) return count
  for (var i = 0; i < items.length; i++) {
    var state = states ? states[items[i].id] : null
    if (state && state.active === true) count += 1
  }
  return count
}

if (typeof module !== "undefined" && module && module.exports) {
  module.exports = {
    TILE_TYPES: TILE_TYPES,
    DEFAULTS: DEFAULTS,
    defaults: defaults,
    isList: isList,
    normalizeSettings: normalizeSettings,
    normalizeItems: normalizeItems,
    normalizeItem: normalizeItem,
    emptyState: emptyState,
    parseCommandOutput: parseCommandOutput,
    commandFor: commandFor,
    tileSettings: tileSettings,
    mergedSettings: mergedSettings,
    stringList: stringList,
    groupNames: groupNames,
    displayTiles: displayTiles,
    sections: sections,
    shortName: shortName,
    fullName: fullName,
    detailFor: detailFor,
    fuzzyScore: fuzzyScore,
    filterTiles: filterTiles,
    gridColumns: gridColumns,
    gridRows: gridRows,
    moveCursor: moveCursor,
    attentionCount: attentionCount
  }
}
