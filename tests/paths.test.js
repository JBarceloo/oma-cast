const test = require("node:test")
const assert = require("node:assert/strict")
const Paths = require("../plugin/core/Paths.js")

const envOf = (vars) => (name) => vars[name] || ""

test("defaults follow the XDG base directory spec", () => {
  const p = Paths.resolve(envOf({ HOME: "/home/u", XDG_RUNTIME_DIR: "/run/user/1000" }))
  assert.equal(p.config, "/home/u/.config/oma-launcher")
  assert.equal(p.configFile, "/home/u/.config/oma-launcher/config.json")
  assert.equal(p.db, "/home/u/.local/share/oma-launcher/db")
  assert.equal(p.extensions, "/home/u/.local/share/oma-launcher/extensions")
  assert.equal(p.cache, "/home/u/.cache/oma-launcher")
  assert.equal(p.logs, "/home/u/.local/state/oma-launcher/logs")
  assert.equal(p.runtime, "/run/user/1000/oma-launcher")
  assert.equal(p.scriptCommands, "/home/u/.config/oma-launcher/script-commands")
})

test("absolute XDG overrides win, relative ones are ignored", () => {
  const p = Paths.resolve(envOf({
    HOME: "/home/u/",
    XDG_CONFIG_HOME: "/cfg/",
    XDG_DATA_HOME: "relative/data",
    XDG_STATE_HOME: "/st"
  }))
  assert.equal(p.config, "/cfg/oma-launcher")
  assert.equal(p.data, "/home/u/.local/share/oma-launcher")
  assert.equal(p.state, "/st/oma-launcher")
})

test("missing HOME is an error", () => {
  assert.throws(() => Paths.resolve(envOf({})), /HOME is not set/)
})

test("startup creates the persistent dirs and the runtime dir", () => {
  const p = Paths.resolve(envOf({ HOME: "/h", XDG_RUNTIME_DIR: "/r" }))
  assert.deepEqual(Paths.directoriesToCreate(p), [
    "/h/.config/oma-launcher", "/h/.local/share/oma-launcher/db", "/h/.cache/oma-launcher",
    "/h/.local/state/oma-launcher/logs", "/h/.local/state/oma-launcher/backups", "/r/oma-launcher"
  ])
})
