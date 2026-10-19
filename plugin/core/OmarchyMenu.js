// The Omarchy menu as a source of root-search commands. [D]
//
// Reads the same JSONC files the Omarchy menu does
// ($OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc, then the user's
// ~/.config/omarchy/extensions/omarchy-menu.jsonc on top, by id) and follows
// its documented format: ids are object keys, dotted ids imply the parent,
// `action` makes a runnable row, `target` links to another submenu, anything
// else is a submenu. `when`/`checked`/`disabled` are bash conditions.
//
// This is our own reading of that data format; Omarchy's MenuModel.js is not
// imported, so a change inside the shell cannot break the launcher at load.

// Full-line // comments and trailing commas, as the format allows.
function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

function parentOf(id) {
  var dot = id.lastIndexOf(".")
  return dot < 0 ? "root" : id.slice(0, dot)
}

function normalizeItem(id, raw) {
  var aliases = Array.isArray(raw.aliases) ? raw.aliases.filter(function(a) { return typeof a === "string" && a })
    : (typeof raw.aliases === "string" && raw.aliases ? [raw.aliases] : [])
  return {
    id: id,
    parent: typeof raw.parent === "string" ? raw.parent : parentOf(id),
    kind: raw.action ? "action" : (raw.target ? "link" : "menu"),
    icon: String(raw.icon || ""),
    iconFont: String(raw.iconFont || ""),
    label: String(raw.label || id),
    title: String(raw.title || ""),
    description: String(raw.description || ""),
    action: String(raw.action || ""),
    target: String(raw.target || ""),
    provider: String(raw.provider || ""),
    aliases: aliases,
    when: String(raw.when || ""),
    checked: String(raw.checked || ""),
    disabled: String(raw.disabled || "")
  }
}

// Returns { items: [normalized], error }. A file that does not parse yields
// no items and an error, never a throw.
function parse(raw) {
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return { items: [], error: "" }
  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (e) {
    return { items: [], error: String(e && e.message || e) }
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return { items: [], error: "menu is not an object" }
  var source = parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items) ? parsed.items : parsed
  var items = []
  for (var id in source) {
    var entry = source[id]
    if (!entry || typeof entry !== "object" || Array.isArray(entry) || id === "root") continue
    items.push(normalizeItem(id, entry))
  }
  return { items: items, error: "" }
}

// Default items first, user items layered on top field by field (a user
// entry with only `label` relabels the built-in one), new ids appended.
function buildTree(defaultItems, userItems) {
  var byId = {}
  var order = []
  var sources = [defaultItems || [], userItems || []]
  for (var s = 0; s < sources.length; s++) {
    for (var i = 0; i < sources[s].length; i++) {
      var entry = sources[s][i]
      var prior = byId[entry.id]
      if (!prior) {
        order.push(entry.id)
        byId[entry.id] = entry
        continue
      }
      var merged = {}
      for (var k in prior) merged[k] = prior[k]
      // Only fields the user actually set override; normalizeItem filled
      // every field, so compare against an empty item's defaults.
      var blank = normalizeItem(entry.id, {})
      for (var f in entry) {
        if (f === "id") continue
        var value = entry[f]
        var isDefault = Array.isArray(value) ? value.length === 0 : value === blank[f]
        if (!isDefault) merged[f] = value
      }
      merged.kind = merged.action ? "action" : (merged.target ? "link" : "menu")
      byId[entry.id] = merged
    }
  }

  var children = { root: [] }
  for (var j = 0; j < order.length; j++) {
    var item = byId[order[j]]
    item.order = j
    var parent = byId[item.parent] || item.parent === "root" ? item.parent : "root"
    if (!children[parent]) children[parent] = []
    children[parent].push(item.id)
  }
  return { items: byId, order: order, children: children }
}

// Labels from the top-level menu down to (not including) the item.
function breadcrumb(tree, id) {
  var labels = []
  var seen = {}
  var item = tree.items[id]
  var parent = item ? item.parent : "root"
  while (parent && parent !== "root" && tree.items[parent] && !seen[parent]) {
    seen[parent] = true
    labels.unshift(tree.items[parent].label)
    parent = tree.items[parent].parent
  }
  return labels
}

function depth(tree, id) {
  return breadcrumb(tree, id).length
}

// guards: { when: {id: bool}, checked: {...}, disabled: {...} } from the
// guard script. A `when` that has not been answered yet shows the row, as
// the Omarchy menu does. A hidden submenu hides everything under it.
function isVisible(tree, guards, id) {
  var seen = {}
  var current = id
  while (current && current !== "root" && tree.items[current] && !seen[current]) {
    seen[current] = true
    if (guards && guards.when && guards.when[current] === false) return false
    current = tree.items[current].parent
  }
  return true
}

var GUARD_GROUPS = 8

function guardLine(id, tag, expression) {
  return "if { " + expression + "\n} >/dev/null 2>&1; then echo '" + id + ":" + tag + ":1'; else echo '" + id + ":" + tag + ":0'; fi\n"
}

// One bash script that answers every guard as `<id>:<w|c|d>:<0|1>` lines,
// dealt into parallel subshells because most guards wait on process start.
// Ids come from the menu files; anything that is not a plain id is skipped
// so it cannot break out of the quoted echo.
function guardScript(tree) {
  var lines = []
  for (var i = 0; i < tree.order.length; i++) {
    var item = tree.items[tree.order[i]]
    if (!/^[A-Za-z0-9._-]+$/.test(item.id)) continue
    if (item.when) lines.push(guardLine(item.id, "w", item.when))
    if (item.checked) lines.push(guardLine(item.id, "c", item.checked))
    if (item.disabled) lines.push(guardLine(item.id, "d", item.disabled))
  }
  if (lines.length === 0) return ""
  var groups = []
  for (var j = 0; j < lines.length; j++) groups[j % GUARD_GROUPS] = (groups[j % GUARD_GROUPS] || "") + lines[j]
  var script = ""
  for (var k = 0; k < groups.length; k++) script += "{\n" + groups[k] + "} &\n"
  return script + "wait\n"
}

function parseGuardOutput(text) {
  var out = { when: {}, checked: {}, disabled: {} }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^([A-Za-z0-9._-]+):([wcd]):([01])$/.exec(lines[i].trim())
    if (!m) continue
    var bucket = m[2] === "w" ? out.when : (m[2] === "c" ? out.checked : out.disabled)
    bucket[m[1]] = m[3] === "1"
  }
  return out
}

function shellQuote(value) {
  return "'" + String(value === undefined || value === null ? "" : value).replace(/'/g, "'\\''") + "'"
}

// Runtime row sources named by `provider:` in the menu. These two are the
// non-app providers the shipped menu uses; each script prints
// `label\tvalue\tcurrent` per row.
var PROVIDERS = {
  "fonts": {
    script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
    icon: "",
    actionFor: function(value) { return "omarchy-font-set " + shellQuote(value) }
  },
  "power-profiles": {
    script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
    icon: "󰐋",
    actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + shellQuote(value) }
  }
}

function slugify(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "item"
}

// Provider output → action items under menuId (same shape as parsed items).
function providerItems(menuId, providerName, output) {
  var spec = PROVIDERS[providerName]
  if (!spec) return []
  var rows = []
  var taken = {}
  var lines = String(output || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\r$/, "")
    if (!line.trim()) continue
    var parts = line.split("\t")
    var label = parts[0] || ""
    var value = parts[1] || label
    var current = parts[2] || ""
    if (!label) continue
    var id = menuId + "." + slugify(value)
    while (taken[id]) id += "-"
    taken[id] = true
    var item = normalizeItem(id, { icon: spec.icon, label: label, action: spec.actionFor(value) })
    item.parent = menuId
    item.isCurrent = value === current
    rows.push(item)
  }
  return rows
}

// `omarchy-shell shell summon <id> ['<json>']` alone can run in-process.
function summonAction(action) {
  var m = /^omarchy-shell shell summon ([A-Za-z0-9._-]+)(?: '([^']*)')?$/.exec(String(action || "").trim())
  return m ? { id: m[1], payload: m[2] || "{}" } : null
}

if (typeof module !== "undefined") {
  module.exports = {
    stripJsonc: stripJsonc,
    parse: parse,
    buildTree: buildTree,
    breadcrumb: breadcrumb,
    depth: depth,
    isVisible: isVisible,
    guardScript: guardScript,
    parseGuardOutput: parseGuardOutput,
    shellQuote: shellQuote,
    PROVIDERS: PROVIDERS,
    providerItems: providerItems,
    summonAction: summonAction,
    slugify: slugify
  }
}
