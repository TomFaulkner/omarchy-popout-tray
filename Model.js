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
    gridColumns: gridColumns,
    gridRows: gridRows,
    moveCursor: moveCursor,
    attentionCount: attentionCount
  }
}
