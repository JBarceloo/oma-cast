// Versioned JSON documents: the clone's migrations framework. [D]
//
// SPEC §6.2 planned numbered .sql migrations over SQLite. The Quickshell
// build keeps each store as one JSON document instead (no native deps), and
// keeps the same rules: numbered steps, applied in order, recorded in a
// history, never re-run, and a document from a newer build is left alone.
//
// A migration is { version: <int>, name: "<slug>", up: function(doc) }.
// `up` mutates or returns the document; version 1 builds it from nothing.

function validateMigrations(migrations) {
  for (var i = 0; i < migrations.length; i++) {
    var m = migrations[i]
    if (!m || typeof m.up !== "function") throw new Error("Migration " + i + " has no up()")
    if (m.version !== i + 1) throw new Error("Migration versions must be 1.." + migrations.length + " in order; got " + m.version + " at " + i)
    if (!/^[a-z0-9][a-z0-9-]*$/.test(String(m.name || ""))) throw new Error("Migration " + m.version + " needs a kebab-case name")
  }
}

function latestVersion(migrations) {
  return migrations.length
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

// Parse raw file text. Empty or missing text means a new document.
// Returns { doc, error }; a parse error leaves doc null so the caller can
// set the unreadable file aside instead of overwriting it.
function parse(text) {
  var raw = String(text || "").trim()
  if (!raw) return { doc: null, error: "" }
  try {
    var value = JSON.parse(raw)
    if (!value || typeof value !== "object" || Array.isArray(value))
      return { doc: null, error: "document is not a JSON object" }
    return { doc: value, error: "" }
  } catch (e) {
    return { doc: null, error: String(e && e.message || e) }
  }
}

// Bring `doc` (or null for a new document) up to the latest version.
// Returns { doc, from, to, applied: [names], changed, readOnly, error }.
// `now` is injectable so tests are deterministic.
function migrate(doc, migrations, now) {
  validateMigrations(migrations)
  var latest = latestVersion(migrations)
  var stamp = typeof now === "number" ? now : Date.now()
  var current = doc ? clone(doc) : {}
  var from = doc ? Number(current.schemaVersion || 0) : 0

  if (!isFinite(from) || from < 0 || Math.floor(from) !== from)
    return { doc: null, from: from, to: from, applied: [], changed: false, readOnly: true, error: "invalid schemaVersion " + current.schemaVersion }

  // Written by a newer build: use it as-is, never write it back.
  if (from > latest)
    return { doc: current, from: from, to: from, applied: [], changed: false, readOnly: true, error: "" }

  var history = Array.isArray(current.schemaHistory) ? current.schemaHistory : []
  var applied = []
  for (var v = from + 1; v <= latest; v++) {
    var m = migrations[v - 1]
    // `ctx.from` is the document's version before this migrate() call, so a
    // migration can tell a fresh document (0) from an upgrade (1, 2, …).
    var next = m.up(current, { from: from, version: v })
    if (next !== undefined) current = next
    if (!current || typeof current !== "object") throw new Error("Migration " + v + " (" + m.name + ") returned no document")
    history = history.concat([{ version: v, name: m.name, appliedAt: stamp }])
    applied.push(m.name)
  }

  current.schemaVersion = Math.max(from, latest)
  current.schemaHistory = history
  return { doc: current, from: from, to: current.schemaVersion, applied: applied, changed: applied.length > 0, readOnly: false, error: "" }
}

function serialize(doc) {
  return JSON.stringify(doc, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    validateMigrations: validateMigrations,
    latestVersion: latestVersion,
    parse: parse,
    migrate: migrate,
    serialize: serialize
  }
}
