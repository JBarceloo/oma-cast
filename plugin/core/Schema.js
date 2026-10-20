
var settingsMigrations = [
  {
    version: 1,
    name: "general-settings",
    up: function(doc) {
      doc.general = {
        windowMode: "expanded",
        showFavoritesInCompactMode: true,
        windowPresentationMode: "mouse-screen",
        popToRootTimeout: 90,
        escapeKeyBehavior: "pop-back-or-close",
        navigationBindings: "emacs",
        rootSearchSensitivity: "medium",
        uiZoom: 1,
        theme: "omarchy"
      }
      doc.commands = {}
      return doc
    }
  }
]

var frecencyMigrations = [
  {
    version: 1,
    name: "frecency",
    up: function(doc) {
      doc.items = {}
      doc.searchHistory = []
      return doc
    }
  }
]

var SEARCH_HISTORY_LIMIT = 20

function pushSearchHistory(history, query) {
  var q = String(query || "").trim()
  var list = Array.isArray(history) ? history.slice() : []
  if (!q) return list
  list = list.filter(function(item) { return item !== q })
  list.unshift(q)
  return list.slice(0, SEARCH_HISTORY_LIMIT)
}

var documents = {
  settings: { file: "settings.json", migrations: settingsMigrations },
  frecency: { file: "frecency.json", migrations: frecencyMigrations }
}

var configDefaults = {
  logLevel: "info",
  keepVisibleOnFocusLoss: false
}

function withConfigDefaults(value) {
  var out = {}
  for (var key in configDefaults) out[key] = configDefaults[key]
  if (value && typeof value === "object" && !Array.isArray(value)) {
    for (var k in value) {
      if (configDefaults[k] !== undefined && typeof value[k] === typeof configDefaults[k]) out[k] = value[k]
    }
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    settingsMigrations: settingsMigrations,
    frecencyMigrations: frecencyMigrations,
    pushSearchHistory: pushSearchHistory,
    SEARCH_HISTORY_LIMIT: SEARCH_HISTORY_LIMIT,
    documents: documents,
    configDefaults: configDefaults,
    withConfigDefaults: withConfigDefaults
  }
}
