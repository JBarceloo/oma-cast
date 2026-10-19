// In-process method registry: the clone's "backend" surface (SPEC §3.4).
//
// Methods keep Raycast's dotted `namespace.method` names so the reference
// method lists stay usable. There is no wire protocol: the launcher UI, the
// IPC handler and later services all dispatch through one registry. [D]
//
// Loaded both by QML (`import "core/Rpc.js" as Rpc`) and by node --test, so
// it has no imports and exports through the module guard at the bottom.

function createRegistry() {
  return {
    handlers: {},
    subscribers: {}
  }
}

function isMethodName(method) {
  return /^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)+$/.test(String(method || ""))
}

// register(reg, "system", { healthPing: fn, ... }) adds system.healthPing.
// Registering a name twice is a programming error, so it throws.
function register(registry, namespace, handlers) {
  var ns = String(namespace || "")
  if (!/^[A-Za-z][A-Za-z0-9.]*$/.test(ns)) throw new Error("Invalid namespace " + ns)
  for (var name in handlers) {
    if (typeof handlers[name] !== "function") continue
    var method = ns + "." + name
    if (registry.handlers[method]) throw new Error("Method already registered " + method)
    registry.handlers[method] = handlers[name]
  }
}

function unregister(registry, namespace) {
  var prefix = String(namespace || "") + "."
  for (var method in registry.handlers) {
    if (method.indexOf(prefix) === 0) delete registry.handlers[method]
  }
}

function methods(registry) {
  return Object.keys(registry.handlers).sort()
}

function errorMessage(error) {
  if (error && typeof error.message === "string") return error.message
  return String(error)
}

function isThenable(value) {
  return !!value && typeof value.then === "function"
}

// Synchronous dispatch for callers that cannot wait, such as IPC. Returns
// { ok: true, data } or { ok: false, error }. A handler that answers with a
// promise yields { ok: true, pending: true }: the call ran, its result is
// delivered later through call().
function callSync(registry, method, data) {
  var handler = registry.handlers[String(method || "")]
  // Same text as Raycast's backend for an unknown method [O].
  if (!handler) return { ok: false, error: "Unknown method " + method }
  try {
    var result = handler(data === undefined ? null : data)
    if (isThenable(result)) return { ok: true, pending: true }
    return { ok: true, data: result === undefined ? null : result }
  } catch (error) {
    return { ok: false, error: errorMessage(error) }
  }
}

// Promise-based dispatch. Rejects with an Error whose message is the
// handler's error, mirroring the frontend `ipc` proxy contract.
function call(registry, method, data) {
  var handler = registry.handlers[String(method || "")]
  if (!handler) return Promise.reject(new Error("Unknown method " + method))
  try {
    return Promise.resolve(handler(data === undefined ? null : data))
  } catch (error) {
    return Promise.reject(error instanceof Error ? error : new Error(errorMessage(error)))
  }
}

// Notifications: `ns.thing` methods fanned out to subscribers, the
// in-process analogue of ipcNotification (SPEC §3.2). Returns an
// unsubscribe function.
function subscribe(registry, method, callback) {
  var key = String(method || "")
  var list = registry.subscribers[key] || []
  list = list.concat([callback])
  registry.subscribers[key] = list
  return function() {
    var current = registry.subscribers[key] || []
    registry.subscribers[key] = current.filter(function(cb) { return cb !== callback })
  }
}

// Returns how many subscribers were notified. A throwing subscriber does not
// stop the others; its error goes to onError when given.
function emit(registry, method, data, onError) {
  var list = registry.subscribers[String(method || "")] || []
  for (var i = 0; i < list.length; i++) {
    try {
      list[i](data)
    } catch (error) {
      if (onError) onError(method, error)
    }
  }
  return list.length
}

if (typeof module !== "undefined") {
  module.exports = {
    createRegistry: createRegistry,
    isMethodName: isMethodName,
    register: register,
    unregister: unregister,
    methods: methods,
    callSync: callSync,
    call: call,
    subscribe: subscribe,
    emit: emit
  }
}
