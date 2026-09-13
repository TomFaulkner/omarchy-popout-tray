# Tray

One bar icon that pops open a grid of tiles. Everything in the tray is owned by
this plugin — a polled command, a click action, or a QML file you point at — so
the bar keeps a single small slot while the stuff you only need occasionally
lives one click away.

## Why it exists

With enough plugins in the right and center sections, the bar runs out of room
and the sections overlap. The bar has exactly three regions (`left`, `center`,
`right`) and one bar at a time, so there is nowhere to move things to.

A plugin cannot host another plugin's widget either:

- `shell.serviceFor(id)` returns a service only for your own plugin id.
- `summon`/`hide`/`toggle`/`updateEntryInline` are scoped the same way unless
  the plugin *is* the active bar.
- Other plugins' widget components are visible in the catalog snapshot, but only
  the built-in bar can hand a widget its live service, so an embedded foreign
  widget renders empty.

So instead of embedding other plugins, the tray ships tiles:

| Type      | What it is |
|-----------|------------|
| `widget`  | Renders another installed plugin's real bar-widget component in the tile. No fork, no copy: the settings are the ones you already had on that plugin's bar entry. |
| `command` | Polls `exec` every `interval` seconds. Prints plain text or Waybar-style JSON (`text`, `tooltip`, `class`/`alt`). `class: "active"` lights the tile and the bar dot. |
| `action`  | Runs `onClick` (or `onRightClick` / `onMiddleClick`) on click. Nothing is polled. |
| `qml`     | Loads `source` as the tile body. Injected: `tile`, `tray`, `bar`, `tileState`. |

## Widget tiles (no forks)

Every plugin with `kind: "service"` receives the widget catalogue, and that
snapshot carries the live `Component` for each registered bar widget — the same
one a replacement bar gets. The tray is a service, so it can instantiate another
plugin's widget directly and hand it the three things a bar widget needs
(`bar`, `moduleName`, `settings`). To put one in the tray, copy its bar entry
into `items` and add `"type": "widget"`:

```json
{ "id": "nosignal.quattrolitaire", "type": "widget", "label": "Quattrolitaire" }
```

Everything it needs from the bar is forwarded to the real bar: tooltips, click
targets, the one-popout-at-a-time coordinator, and `run()` — which is how most
widgets open their own overlay. Two things cannot be forwarded:

- **The widget's own live service.** Only the trusted built-in bar can mint
  that, so a widget that reads `bar.shell.serviceFor(<its own id>)` renders
  inert here. Of the plugins installed on this machine that is hass, omarr,
  lotus, recall, omarewind, omaconnect, and tomato-timer; the other 24 ask for
  nothing from `bar.shell`.
- **Settings writes.** `updateEntryInline` is scoped to the caller, so the tray
  persists them itself, under `tiles.<id>` inside its own `shell.json` entry.
  Right-click cycles and similar survive a restart.

`summon`/`hide`/`toggle` are routed to `omarchy-shell shell <verb> <id>` as a
separate process, so a widget that opens its own panel still works here.

Widgets that declare an `IpcHandler` (pinball does) log a duplicate-target
warning while the tray is open: the bar's copy keeps the target, and the tray's
copy goes unused. Harmless, and it goes away if you take the widget out of the
bar.

An `action` tile is how an installed plugin with an overlay or panel entry point
gets into the tray, since `omarchy-shell shell toggle <id>` is a separate
process and not subject to the in-shell scope:

```json
{ "id": "hass", "type": "action", "label": "Home", "onClick": "omarchy-shell shell toggle hass '{}'" }
```

Plugins that are bar-widget only (`unifi`, `stocks`, `portwatch`, `omarr`,
`nvme-health`, `downloads`, …) have nothing to summon — they come in as a
`command` or `qml` tile you write, or stay in the bar.

## Install

Omarchy refuses symlinks *inside* a plugin folder, but the plugin directory
itself may be a symlink:

```sh
ln -sfn "$PWD" ~/.config/omarchy/plugins/io.github.tomfaulkner.tray
ln -sfn "$PWD/bin/omarchy-tray" ~/.local/bin/omarchy-tray
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.tomfaulkner.tray
```

Then add the widget to a bar section (or let `enable` place it in `right`) and
give it items — with `omarchy-tray`, below, or by hand in `shell.json`.

## Adding plugins to the tray

```sh
omarchy-tray list                       # what is installed, where, and what fits
omarchy-tray add hegjon.unifi           # tile in the tray, plugin stays in the bar
omarchy-tray add hegjon.unifi --move    # tile in the tray, out of the bar
omarchy-tray remove hegjon.unifi
```

`list` marks `NEEDS-SERVICE` for widgets that read their own service through
`bar.shell.serviceFor`: they load in the tray but render inert, because only
the built-in bar can hand a widget its service.

`--move` deletes the plugin's bar entry and records it in the top-level
`plugins[]` array. That matters: a third-party bar widget is enabled by being
somewhere in `shell.json`, and the tray's `items` do not count — without the
`plugins[]` entry the widget is no longer registered and the tile comes up
"not installed". `remove` drops that entry again when the plugin is not in the
bar, which disables it.

Both commands back up `shell.json` first and reload the shell config. To do it
by hand, copy the plugin's bar entry into the tray's `items` and add
`"type": "widget"`; to take it out of the bar as well, move `{"id": "<id>"}`
into the top-level `plugins[]` array.

## Configuration

Everything lives inline on the bar entry in `~/.config/omarchy/shell.json`; the
shell hot-reloads it on save.

```json
{
  "version": 1,
  "bar": {
    "layout": {
      "right": [
        {
          "id": "io.github.tomfaulkner.tray",
          "label": "More",
          "glyph": "⋯",
          "columns": 4,
          "tileWidth": 96,
          "tileHeight": 76,
          "showLabels": true,
          "items": [
            { "id": "updates", "type": "command", "label": "Updates", "glyph": "󰏖",
              "exec": "~/.config/omarchy/tray/scripts/updates", "interval": 900 },
            { "id": "hass", "type": "action", "label": "Home", "glyph": "",
              "onClick": "omarchy-shell shell toggle hass '{}'" },
            { "id": "gpu", "type": "qml", "label": "GPU",
              "source": "~/.config/omarchy/tray/tiles/gpu.qml" }
          ]
        }
      ]
    }
  }
}
```

| Key | Default | Meaning |
|-----|---------|---------|
| `label` | `Tray` | Panel header and tooltip title |
| `glyph` | `⋯` | Bar icon |
| `columns` | `4` | Grid columns (clamped to the tile count) |
| `tileWidth` / `tileHeight` | `96` / `76` | Tile size in px |
| `showLabels` | `true` | Show each tile's label |
| `items[]` | `[]` | The tiles |

Per tile: `id` (defaults to `tileN`, duplicates get a suffix), `type`
(`command` / `action` / `qml`, unknown → `action`), `label`, `tooltip`, `glyph`,
`exec`, `interval` (seconds, min 1), `onClick`, `onRightClick`,
`onMiddleClick`, `source`.

One tray per bar: `allowMultiple` is off, and deliberately so. Every instance
would push its own settings into the shared service and the last one to mount
would win, and `updateEntryInline` can only address one entry per plugin id, so
a second tray's settings would land on the first one. Grouping inside a single
tray is the supported shape.

## Using it

- **Left click** the bar icon: open or close the tray. `omarchy-shell shell
  toggle io.github.tomfaulkner.tray` does the same, so it can be bound to a key.
- **Right click** the bar icon: re-run every command tile now.
- **Arrows**: move the cursor. **Enter** or **Space**: activate the tile.
  **R**: refresh. **Esc**: close. **Tab**: hand off to the next bar panel.
- **Left / right / middle click** a tile: that tile's `onClick` /
  `onRightClick` / `onMiddleClick`, falling back to `onClick`.

Command tiles are polled from the shared service, so one bar widget per monitor
does not mean two sets of timers. Tiles whose `exec` fails simply keep their
last text.

## Files

| File | Role |
|------|------|
| `Service.qml` | Owns config, command polling, and action running |
| `BarWidget.qml` | The bar icon, its attention dot, and the popout |
| `TrayPanel.qml` | KeyboardPanel popout: header, grid, keyboard nav |
| `Tile.qml` | One tile: glyph, text, tooltip, hover, click |
| `Model.js` | Pure config/parsing/grid logic (unit tested) |
| `examples/` | A starter entry, two scripts, one QML tile |

## Tests

```sh
node test/model.test.js
```

## License

MIT
