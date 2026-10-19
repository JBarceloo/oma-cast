# 01 — Native host layer and IPC (Raycast 2.8.2, macOS)

Scope: the Swift host (`Contents/MacOS/Raycast`, module `RaycastDesktopApp`), the Rust coordinator (`Frameworks/libraycast_host.dylib`, crate `raycast_host`, UniFFI 0.31.2), the Node backend transport (`backend/index.mjs`), the WebView bridge (`frontend/*.js`), and the helpers (2 XPC services, Palette input method, Updater agent and daemon).

Method: static only (`strings`, `nm`, `otool`, `plutil`, `codesign -d`, plus reading the minified JS). Raycast was never launched or attached to, and nothing touched the network. A REA/Hopper session failed to open: a stale, earlier Hopper document blocked cleanup, and `close_binary` reported `cleanup_incomplete` for `/tmp/rea-FRMFwj`. No decompilation was used, so numeric timeouts are not recovered (see Unknowns).

Legend: **[O]** = observed directly (literal string, symbol or code quoted). **[I]** = inferred from the observed evidence.

---

## 0. Architecture in one picture

```
┌───────────────────────────── Raycast.app (Swift/AppKit, LSUIElement) ─────────────────────────────┐
│  WKWebView windows (main panel, settings, ai-chat, notes, hud, popovers…)                        │
│     JS ──window.webkit.messageHandlers.ipcRequest.postMessage({method,data,destination,…})──┐    │
│     JS ◀──evaluate `window.ipcRequest(method,data)` / `window.ipcNotification(method,data)`─┐│    │
│     ipc://image|file-preview|emoji-glyph|raycast-sprite  (WKURLSchemeHandler)              ││    │
│     local://file…                                       (WKURLSchemeHandler)              ││    │
│                                                                                           ▼│    │
│  WebViewRequestHandler / WebViewDispatcher / FrontendNotificationQueue  ── "host" methods → native handlers (≈300)
│        │ destination "backend"                                                                  │
│        ▼                                                                                        │
│  RaycastHostShared.Coordinator (Swift UniFFI wrapper) ──FFI──▶ libraycast_host.dylib (Rust/tokio)│
│                                                   Supervisor actor → Process → MessageProcessor  │
│                                                                    │ stdin/stdout JSON lines      │
│ XPC: com.raycast.macos.accessibility / .pasteboard                 ▼                              │
│ Palette.app (IMK palette input method)        node (extracted from bundled tarball) backend/index.mjs
│ LaunchAgent com.raycast.macos.updater → LaunchDaemon …updater.daemon      └─ WS server 127.0.0.1:7265 (browser ext)
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Endpoints/destinations **[O]** (backend JS `Tft` list and the Swift strings):
`host`, `backend`, `external` (browser extension, via the backend WS), and the frontends
`frontend:main`, `frontend:ai`, `frontend:settings`, `frontend:themeStudio`, `frontend:playground`, `frontend:welcome`, `frontend:proWalkthrough`, `frontend:hud`, `frontend:notes`, `frontend:feedback`, `frontend:quickLook`.

The Rust coordinator handles only host↔backend traffic. The **Swift host is the router**:
- Requests from a WebView with `destination:"backend"` go to `Coordinator.send`.
- Backend requests with `destination:"frontend:main"` arrive in `EventHandler.on_request(uuid, method, destination=Frontend, data)`. Swift forwards them into the WebView with `window.ipcRequest(method, data)`.
- Backend notifications arrive in `on_notification(method, data, destinations[])` and Swift fans them out with `window.ipcNotification(method, data)` (`RaycastDesktopApp/WebViewDispatcher.swift forwardNotification(method:data:destination:)`, `FrontendNotificationQueue.enqueue(method:data:destination:)`) **[O]**.

---

## 1. Rust host ↔ Node backend wire protocol

### 1.1 The Rust FFI surface (UniFFI metadata, with doc comments) [O]
Exported `_UNIFFI_META_RAYCAST_HOST_*` symbols in `libraycast_host.dylib` include these:

- `Coordinator::new(config: Config, event_handler: EventHandler)`
- `Coordinator.start() -> Result<(), StartError{AlreadyRunning|StopRequested|Failed|InternalCommunicationError}>`
- `Coordinator.stop() -> Result<TerminationOutcome{code: Option<i32>, graceful: bool}, StopError{NotRunning|AlreadyStopping|InternalCommunicationError}>`. Doc: "Waits for the backend to exit, joining an existing shutdown and suppressing automatic restart."
- `Coordinator.send(id: Option<String>, method, data: Vec<u8>, timeout: Option<Duration>, sentry_trace: Option<SentryTrace{trace_id,baggage}>) -> Result<CoordinatorSendResponse{data, timings: CoordinatorResponseTiming{backend, coordinator}}, SendError{Timeout|ProcessTerminated|FailedToSerialize|FailedToDeserialize|InvalidJsonData|RequestError|InternalCommunicationError}>`. Doc: "If `None` or invalid UUID, a new UUID will be generated… A zero duration means no timeout."
- `Coordinator.notify(method, data, coalesce_key: Option<String>)`. Doc: "Notifications share the requests' delivery channel… while queued, a newer emission with the same method and key drops this one."
- `Coordinator.get_state() -> CoordinatorState{Stopped|Running|Error}`
- `Coordinator.note_power_transition(PowerTransition{WillSleep|DidWake})`. Doc: "request budgets stop counting from WillSleep until the backend answers again after DidWake… Call it before sending the matching `system.sessionStatusUpdate`."
- `Coordinator.note_windows_open(open: bool)`. Doc: "restarts a backend whose file-system work has stalled only once none [of the windows] is [open] (XRAY-8697)".
- `Coordinator.boost_execution_speed_for(duration)`. This applies to Windows EcoQoS only and is a no-op on macOS.
- Callback interface `EventHandler`: `on_request(uuid, method, destination: InboundRequestDestination{Frontend|Host}, data) -> Result<Vec<u8>, RequestError{Other(String)|MethodNotImplemented}>`, `on_notification(method, data, destinations: Vec<String>)`, `on_backend_log(level, message)`, `on_backend_performance_log(message, timestamp)`, `on_backend_stall(capture_id, stuck_on, details)`, `on_failure(…)` ("non-zero exit code and won't be restarted after exhaustion of retries"), and `should_record_backend_trace()`.
- `init_logger(handler: LogHandler{on_log, on_panic}, is_development)`, `shutdown_logger()`, `shutdown_coordinator_runtime(timeout)`
- `NativeSentryClient` (add_breadcrumb, set_telemetry_tags, set_user_id, test_*)
- `Config` record: `engine: EngineConfig{Subprocess|EmbeddedNode}`, `executable_path`, `executable_code_requirement` (csreq the spawned node must satisfy *before* it receives secrets), `script_path`, `environment: BackendEnvironment`, `pid_file_path`, `secrets: Secrets`, `tracing_metadata`, `startup_timeout`, `request_timeout` ("Default budget for a host request without a per-method timeout, in awake time"), `shutdown_timeout`, `startup_timeout_extension`, `max_restart_attempt`, `max_restart_attempt_duration`, `is_dev_server_running`, `enable_performance_metrics`.
- `Secrets{database_key, signature_secret, release_api_token, posthog_api_key}`. Doc: "Delivered to the backend in the `initialize` handshake message rather than through the environment."
- `EmbeddedNode` is "inside the host process via libnode (`../Frameworks/libnode.dylib`)". This build logs "The embedded Node engine was requested but this build does not include the embedded-node feature. Using the subprocess engine." In practice it is **always a subprocess on macOS** [O]. (`raycast_useEmbeddedNode` user default exists.)

### 1.2 Process launch [O unless marked]
- Node comes from `node/node-v22.23.3-darwin-arm64.tar.gz`. Swift `NodeBackend.installNode()` unpacks it, logs "Node.js binary already exists at … Skipping installation." and "…is not the signed Node.js build. Reinstalling.", and checks the requirement `anchor apple generic and identifier "node" and certificate leaf[subject.OU] = "HX7739G8FX"`.
- Node args seen in the Rust strings: `--max-semi-space-size=4` and `--disable-sigusr1`. The script is `backend/index.mjs` (`script_path`).
- The PATH comes from the user's login shell (`Shell.swift shellEnvironment()`, `/usr/bin/printenv`). The doc says "`PATH`, resolved from the user's login shell".
- PID file: `RAYCAST_PID_FILE_PATH`. Rust `pid.rs` logs "Killed previous instance which was running with PID …". The JS writes it with "Writing PID file…" and `rename` retries.
- Environment variables (BackendEnvironment, with doc strings):
  `NODE_ENV` (development|production), `RAYCAST_VERSION`, `RAYCAST_GIT_COMMIT_HASH`, `RAYCAST_OS_NAME`, `RAYCAST_OS_ARCH`, `RAYCAST_OS_IDENTIFIER`, `RAYCAST_OS_VERSION`, `LC_ALL` (BCP‑47), `TZ` (IANA), `RAYCAST_CACHE_DIR`, `RAYCAST_SUPPORT_DIR`, `RAYCAST_LOGS_DIR`, `RAYCAST_APPLICATION_PATH`, `RAYCAST_API_ENVIRONMENT`, `RAYCAST_API_CUSTOM_BACKEND_URL`, `RAYCAST_API_CUSTOM_FRONTEND_URL`, `RUST_LOG`, `RAYCAST_ENABLE_PERFORMANCE_LOGS`, `RAYCAST_ENABLE_HANG_DETECTOR`, `RAYCAST_ENABLE_ROOT_SEARCH_LOGS`, `RAYCAST_DEVELOPMENT_TEST_UPDATES`, `RAYCAST_REQUEST_TRACING`, `RAYCAST_SENTRY` (a single JSON blob: enabled, dsn, environment, release, userId, sampleRate, tracesSampleRate, spotlight, dist, tags), `startupTrace`, `RAYCAST_BUNDLE_ID`, `HOME`, `TMPDIR`, `PATH`, `RAYCAST_LOCALE_DECIMAL_SEPARATOR`, `RAYCAST_LOCALE_GROUPING_SEPARATOR`, `RAYCAST_WORKSPACE_DIR`, `RAYCAST_WORKSPACE_LABEL` (dev only), `RAYCAST_ENABLE_PERF_METRICS`.

### 1.3 Framing [O, from both sides]
Transport: newline‑delimited UTF‑8 over the child's stdin/stdout. stderr is not part of the protocol. JS logs also go to a file (`mh`).

**Host → Node** (each line is one JSON object; JS `handleStdinData` splits on `\n`, then `JSON.parse`, then switches on `type`):
```jsonc
// 1) handshake, sent once right after spawn (Rust: "Failed to send initialization message")
{"type":"initialize","databaseKey":"…","signatureSecret":"…","releaseApiToken":"…","posthogApiKey":"…"}

// 2) request host→backend (JS treats "has id && has method" as a request)
{"type":"message","id":"6f1c…-uuid","method":"rootSearch.search","data":{…},"sentryTrace":{"traceId":"…","baggage":"…"}}

// 3) response to a backend→host request (has id, no method)
{"type":"message","id":"<uuid from backend>","data":{…}}          // success
{"type":"message","id":"<uuid>","error":"Host doesn't implement handler"}  // failure; JS: reject(Error(e.error))

// 4) notification host→backend (method, no id)
{"type":"message","method":"window.focusChanged","data":{…}}
```

**Node → Host** is "framed" with ASCII control separators. **[O, verified in the final synthesis pass against `function Qft`]** Each frame is `"\x1e" + headerJson + ("\x1f" + dataJson, if there is data) + "\x1d\n"`. JS `asn()` builds the header as `JSON.stringify({...header, dataLength: Buffer.byteLength(dataJson)})`. (An earlier draft of this file left out the `\x1e`/`\x1f`/`\x1d` bytes. The examples below omit them for readability.) The Rust side reads the header with serde (`FramedInboundMessageHeader`, `data_length`) and slices `dataLength` bytes as a `RawValue` ("split payload unexpectedly used a non-message type").
```jsonc
// request backend→host or backend→frontend
{"type":"message","kind":"request","id":"<uuid>","destination":"host","method":"clipboard.placeInClipboard","dataLength":57}{"entry":{"target":"pasteboard","items":[…]},"shouldCloseWindow":true}

// response to a host request (timings: {queueDuration, handlerDuration, handlerMetrics})
{"type":"message","kind":"response","id":"<uuid>","timings":{…},"dataLength":12}{"items":[…]}
{"type":"message","kind":"response","id":"<uuid>","error":"Unknown method foo.bar"}   // errors carry no payload

// notification to frontends (destinations = subset of frontend:* list)
{"type":"message","kind":"notification","method":"indexer.stateChanged","destinations":["frontend:main",…],"dataLength":20}{"state":"indexing"}

// non-message payloads (single JSON object, no dataLength)
{"type":"startupCheckpoint","phase":"step"}       // after each startup step → Rust "Extending timeout deadline"
{"type":"startupCheckpoint","phase":"finished"}   // → Rust "Process is now running"
{"type":"shutdownCheckpoint","phase":"started"}
{"type":"shutdownCheckpoint","phase":"graceful"}
{"type":"log","level":"info","message":"…"}       // levels: trace|debug|info|warning|error|fatal
{"type":"performanceLog","message":"…","timestamp":"…"}
```
- If `data` is `undefined` the header is emitted without `dataLength` [O, JS `asn`].
- Payloads over 1 MiB only trigger a warning ("Writing oversized payload"); there is no hard cap [O].
- Data is JSON. Large int64 values are handled with a `JSON.rawJSON` / BigInt reviver [O].

### 1.4 Method naming and dispatch [O]
- Methods are `namespace.method` strings. The backend resolves them by walking a nested handler object (`lut(handlers, "a.b")`).
- The backend handler namespaces (`SZa`) are: `memoryHistory, ai, aiRuntime, analytics, appFlags, remoteNotifications, auth, uiTesting, browserExtension, calculator, calendars, clipboard, color, contacts, permissions, database, legacyDatabase, debug, diagnostics, dictation, emojiPicker, feedback, focus, fileSystem, flightTracker, frecency, imageProxy, indexer, linkInfo, mcp, menuBar, appMenuBarItems, newsletter, onboarding, userActivity, userDefaults, releases, appleShortcuts, system, themes, snippets, quicklinks, rootSearch, screenshots, store, settings, hotkey, extensionHost, notes, organizations, translator, trials, typingPractice, scriptCommands, windowManagement, windowsRunCommands, weather, general`, plus `bext` for external callers. The frontend can call about 732 backend methods.
- The typed client is generated code (`Cft` in the backend, `Yt` in the frontend), for example `Q.host.clipboard.placeInClipboard(arg)` → `dispatchRequest("host","clipboard.placeInClipboard",arg,{timeout})`. Notification emitters use a Proxy: `$.indexer.emitStateChanged(x)` → method `indexer.stateChanged`, broadcast to all `frontend:*` destinations. Subscribers: `subscribeX` ↔ inbound `ns.x`.
- Per-method backend→host timeouts [O]: default 5000 ms (JS `request(...,r=5e3)`). `appleShortcuts.getAllAppleShortcuts` uses 120000, `applications.getSelectedText` and `getTextBeforeCaret` use 7500, `applications.terminate` uses 10000. On SIGTERM the backend calls `host raycast.quit` with a 1000 ms timeout.
- Methods the host sends to the backend that are visible in Swift strings [O]: `system.healthPing`, `system.healthDatabase`, `system.healthFileSystem`, `system.sessionStatusUpdate` ({status: willSleep|didWake}), `system.networkConfigurationChanged`, `system.powerSourceChanged`, `system.handleDeeplink`, `system.copyLogFiles`, `settings.getGeneralSettings`, `settings.getInternalExtensionSettings`, `settings.getCloudSyncSettings/Status`, `snippets.expandSnippet`, `snippets.getAllKeywordSnippets`, `snippets.updateAccessedAt/CopyCount`, `userDefaults.get`, `general.openRaycastCommand`, `general.trackApplicationExecutedByHotkey`, `general.frontmostAppUpdate`, `general.runningApplicationsUpdate`, `general.menuBarOwningAppUpdate`, `general.updateKeyboardLayoutSelection`, `general.updateSystemAccentColor`, `general.invalidateAppIcons`, `general.updateIconsCacheVersion`, `general.notifyHyperKeyError`, `general.dispatchNativeEvent`, `general.emitKeyboardEvent`, `general.setWindowCaptureActive`, `general.shouldCloseWindow`, `general.prepareIfOpenedByHost`, `general.refreshManagedSignInPolicy`, `general.updateManagedSignInUserEmail`, `window.focusChanged`, `window.visibilityChanged`, `window.appearanceChanged`, `window.floatingChanged`, `window.closed` (the backend subscribes to closed/focusChanged/visibilityChanged), `notes.getWindowData`, `notes.getCurrentWindowData`, `notes.navigateToNote`, `menuBar.actionCallback`, `menuBar.menuWillOpen/menuDidClose`, `menuBar.itemRemoved`, `menuBar.showExceptionInMainWindow`, `permissions.notifyPermissionChanged/notifyPermissionsSnapshot`, `calendars.notifyEventsChanged`, `contacts.notifyContactsChanged`, `systemNotifications.notificationClicked`, `media.*Changed` (audio level and device change streams), `windowManagement.openedWindowsChanged`, `windowManagement.resolveLayoutBounds`, `virtualDesktops.virtualDesktopsChanged`, `focus.*` (session and blocked-app events), `ai.createNewChat/openChatFolder/attachScreenAwareness/prepareForReveal`, `memoryHistory.recordEvent`, `diagnostics.setIssue/clearIssue`, `indexer.prepopulate`, `releases.checkForUpdates`, `releases.canShutDownForAutoInstall`, `debug.*`.

### 1.5 Lifecycle, health checks, restart [O; numbers unknown]
- **States**: Coordinator `Stopped|Running|Error`. Inner process states are `Starting/Running/Stopping` (string `startingstoppinggraceful`). TerminationState is `none|Graceful|…`. Restart reasons are `Initial|Started|Requested|Instructed|InstructedNoRestart|Independent`.
- **Startup**: spawn → verify the code requirement on the live pid ("Refusing to start …: it does not satisfy the code requirement") → write `initialize` → wait for `startupCheckpoint`. Each `step` extends the deadline by `startup_timeout_extension`, and `finished` marks it Running. While Starting, host requests and notifications queue up ("Flushing N queued messages"). The host-notification queue is bounded ("Dropped the oldest queued host notification from a full queue"). Startup failures are logged with "Backend exited during startup with code {code} ({code_hex}), {lifetime_ms} ms after spawn. Last step: {last_step}". Exit code 0 without a shutdown checkpoint "Treating it as a crash."
- **Health** (`health.rs`): the host probes `system.healthPing` (returns nothing), `system.healthDatabase` and `system.healthFileSystem` (return `{workMs}`; Rust struct `ProbeResult{workMs}`). It keeps per-probe stats (`_samples=`, `_p50_ms=`, `_p95_ms=`, `_last_ms=`, `_hist=`, `_work_p95_ms=`, `_in_flight_ms=`, `post_wake_ping_ms=`) and logs "Backend health …", "The backend's database is slow while the backend itself answers promptly", "Backend stalled: …, stall_capture_id=…" (→ `on_backend_stall`). If the fs probe stalls, it runs "Restarting a backend whose file-system work stalled: backend_instance=…, fs_unanswered_ms=…", but only once `note_windows_open(false)`.
- **Budgets/awake clock** (`awake_clock.rs`, `budget_clock.rs`): request timeouts count only awake time. They pause on WillSleep ("Request budgets paused on …") and resume after the first answer post-DidWake.
- **Restart strategy** (`restart_strategy.rs`): it restarts after a crash up to `max_restart_attempt` within `max_restart_attempt_duration`, then logs "Maximum restart attempts reached" → `on_failure` → Swift `handleUnrecoverableFailure` ("Raycast crashed unexpectedly and failed to restart.", with an app relaunch attempt).
- **Shutdown**: "Closing stdin to signal graceful shutdown" → the JS sees `stdin end`, runs the shutdown steps, and sends `shutdownCheckpoint started`/`graceful` → after `shutdown_timeout` the host logs "Graceful shutdown timed out. Force killing process." (SIGKILL). The JS also exits on SIGINT/SIGTERM/SIGQUIT/SIGHUP, on stdin end, and on stdout EPIPE.

### 1.6 Linux equivalent
Keep this layer as is. It is already portable Rust with tokio (the coordinator was written for Windows too, with `native.dll` references). On Linux:
- Spawn a system `node` (or a bundled one) with the same flags. Pass secrets in `initialize` and keep the database key in **libsecret / Secret Service** (gnome-keyring, KWallet via ksecretd), replacing the macOS Keychain.
- Replace the code-requirement check with a path-plus-hash check, or ship node inside a read-only location (AppImage, or `/usr/lib/<app>/node` from a pacman package).
- Sleep/wake: subscribe to **logind `org.freedesktop.login1.Manager.PrepareForSleep`** and call `note_power_transition`. Network changes come from **NetworkManager D-Bus** and power-source changes from **UPower**.
- If you use Tauri, the Rust coordinator can live in the Tauri core process, which removes the Swift↔Rust FFI layer.

---

## 2. WebView ↔ host/backend bridge

### 2.1 Script message handlers [O]
- `window.webkit.messageHandlers.ipcRequest`. This is a **WKScriptMessageHandlerWithReply** (the binary imports `addScriptMessageHandlerWithReply:contentWorld:name:`). The frontend client (`register-query-client-*.js`, class `nn`):
  ```js
  const reply = await window.webkit.messageHandlers.ipcRequest.postMessage({
    method: "clipboard.placeInClipboard",
    data: JSON.stringify(arg),          // string, not object
    destination: "host" | "backend",    // "external" is rewritten to "backend"
    timeout: ms/1000,                   // seconds (float), optional
    sentryTrace: {...}                  // optional
  });
  // reply is a JSON string; parsed result is returned directly,
  // or {data, timings} when window.enablePerformanceMetrics is set (Swift appends `,"mainThreadResume":…`)
  ```
  Swift side: `WebViewRequestHandler.userContentController(_:didReceive:)` → `handleRequest(method:destination:dataString:timeout:sentryTrace:)`. It logs "Web view received unhandled method" and "Forwarding ipc request" (for backend).
- `window.webkit.messageHandlers.logger.postMessage({level, message, timestamp})`. This is the performance log channel (`RaycastIPC.WebViewLogger`).
- Portal, popover and action-panel windows use extra per-window handlers through `WeakScriptMessageHandler` (`PortalWindowController.portalWindowDidReceiveMessage`). The host injects JS that defines `window.resizeTo(w,h)`, `window.setAnchorRect(x,y,w,h)`, `window.startDrag(x,y)`, `window.resetPosition()`, `window.bounce()`, `window.makeKey()`, `window.animateOut()`, `window.cancelAnimateOut()`, each wired to `window.webkit.messageHandlers.<name>.postMessage(...)`. Handler names: `resizeWindow, setAnchorRect, animateOut, cancelAnimateOut, makeKey, bounce, startDrag, resetPosition` [O].

### 2.2 Host → page calls [O]
The host evaluates these with `evaluateJavaScript` / callAsync:
- `window.ipcRequest(method, dataString)` returns a JSON string. The host-injected wrapper throws `"window.ipcRequest is not available"` if it is missing. This is used for backend requests that target `frontend:main` (e.g. `extensionHost.render`, `general.showToast`, `uiTesting.*`) and for host-originated frontend calls.
- `window.ipcNotification(method, dataString)` delivers notifications. The frontend `NotificationCenter` debounces certain methods (50 ms).
- Callbacks: `window.onPlace('<side>')`, `window.onAnimateOutComplete()`, `window.onPointerDownOutside?.()`, `window.onMouseEntered/Exited?.()`, `window.__raycastPrepareInitialRevealFocus()`, and a synthetic `KeyboardEvent` dispatch for secure-input workarounds.
- Native DOM events are `native:<name>` CustomEvents on `window` (`window.addNativeEventListener`), e.g. `native:ai-chat-menu`, `native:ai-chat-history`, `native:dictation-hud`, `native:drag-and-drop`. They are triggered through `general.dispatchNativeEvent`.
- Boot-injected globals: `window.identifier` ("main", …), `window.homedir`, `window.initialAppearance`, `window.initialThemes`, `window.initialGeneralSettings`, `window.initialAuthUser`, `window.enablePerformanceLogs`, `window.enablePerformanceMetrics`, `window.raycastApi.environment`, `window.sentry.load = {baggage…}`, and notes boot JSON (`makeNotesBootJSON`).
- The frontend also exposes `window.showMainWindow(compact, prepId)`, `window.hideMainWindow()`, `window.warmupMainWindow()` and `window.mainRouter` for the host to call.

### 2.3 Custom URL schemes (WKURLSchemeHandler) [O]
- `ipc://` → `WebViewIPCSchemeHandler` (has an `ImagePipeline`). Paths:
  `ipc://image?path=…&width=…&height=…&trimTransparentPadding=1` (app and file icons, thumbnails), `ipc://file-preview?path=…&width&height&fit=contain|cover`, `ipc://emoji-glyph…`, and `ipc://raycast-sprite/<id>#s` (an SVG `<symbol id="s">` sprite). Responses use `Cache-Control: max-age=31536000, immutable`. It handles `contactThumbnail` and others.
- `local://file…` → `WebViewLocalSchemeHandler`. It serves local files (media too: `X-Playback-Session-Id`, `Access-Control-Allow-Origin`).
- Pages load from the bundled `frontend/*.html`, with `allowFileAccessFromFileURLs` / `allowUniversalAccessFromFileURLs` enabled. Dev mode uses `http://localhost:3000/3001/5001` [O strings; prod uses file URLs, I].
- HTML entry points: `main-window, settings-window, ai-chat-window, notes-window, theme-studio-window, welcome-window, pro-walkthrough-window, feedback-window, auxiliary-window-prewarm` (+ playground, hud and quickLook identifiers).

### 2.4 Other sockets
- **No localhost websocket between the WebView and the host.**
- The **backend** runs `ExternalWebSocketServer` on `127.0.0.1:7265` (Production; Internal 7262, Dev 7261; it falls back to 7266 on EADDRINUSE) for the browser extension (`external` destination, `bext.*`). Messages: request `{id, method, params?}` → `{id, result}` / `{id, error:{message}}`, and `{"method":"ping"}` → `{result:{value:"pong"}}` [O]. It can be disabled with `externalWebSocketServerEnabled`.
- OAuth loopback servers on `127.0.0.1:0` exist in the backend for MCP and calendar sign-in [O].

### 2.5 Linux equivalent
- **Tauri 2 / wry (WebKitGTK on Linux)** is the closest fit:
  - Custom protocols `ipc://` and `local://` → `register_asynchronous_uri_scheme_protocol` (WebKitGTK `webkit_web_context_register_uri_scheme`).
  - Inject an initialization script that polyfills `window.webkit.messageHandlers.ipcRequest.postMessage` as a Promise over Tauri `invoke`, or over WebKitGTK `script-message-with-reply-received` (WebKitGTK ≥ 2.40 supports message handlers with reply natively). The frontend bundle then runs **unmodified**.
  - Implement `window.ipcRequest` / `window.ipcNotification` calls with `webview.eval()` / `evaluate_javascript`.
- Electron is the alternative: `contextBridge` exposes the same shim, and `protocol.handle('ipc')`.

---

## 3. Window model

### 3.1 Windows (Swift classes) [O]
`RaycastDesktopApp.*`:
- **MainWindow** (launcher)
- **WebViewPanel** (NSPanel subclass; `So7NSPanelC` is referenced) and **WebViewWindow** (regular NSWindow, `makeActive(_:isFloating:queryItems:)`, `window.floatingChanged`)
- **SettingsWindow**, **AiChatWindow** (+ `AiChatHistoryMenu`, `raycast_AIChatAlwaysOnTop`, `setAiChatWindowFloating`), **NotesWindow**, **ThemeStudioWindow**, **PlaygroundWindow**, **WelcomeWindow**, **ProWalkthroughWindow**, **FeedbackWindow**
- **HUDWindow**, **PinnedHUDWindow**, **DictationHUDWindow**, **ActionPanelWindow**, **AlertWindow**, **DialogWindow**, **TooltipWindow**, **InfoCardWindow**, **PortalWindow**/**AnchoredPortalWindow** and **Popover** (web popovers anchored to rects)
- **FocusSessionPanelWindow**, **FocusAppOverlay**, **FocusGlowOverlay**
- **GridPlacementWindow**, **GridHighlightWindow** (window-management grid), **BackgroundWindow**, **AiContextCapturePanel/Overlay** (screen-element picker with a Metal outline)
- **MenuBarStatusItem** (+ `MenuBarStatusItemPositionKeeper`, `TidyMenuBarService` with an event tap `com.raycast.tidy-menu-bar.event-tap`), **MenuBarExtraController/Service** (extension menu-bar items)
- An **AuxiliaryWebContentPrewarmer** keeps a hidden prewarmed web view (`auxiliary-window-prewarm.html`).

### 3.2 Launcher panel behavior [O strings; mechanics partly I]
- `LSUIElement=true` (no Dock icon). The main window is a borderless, floating panel (`setFloatingPanel:`, `setLevel:`, `NSVisualEffectView`/`BlurView` for vibrancy, custom corner radius via an `NSThemeFrame` swizzle).
- Show/hide is driven over IPC: `raycast.showMainWindow({compactMode, preparationId})`, `raycast.hideMainWindow`, `raycast.warmupMainWindow`, `raycast.setMainWindowPreparation`, `raycast.setCompactMode`, `raycast.resizeWindow`, `raycast.resetPosition`, `raycast.shakeMainWindow`, `raycast.toggleBounceAnimation`, `raycast.confetti`.
- **Warmup/reveal state machine** (`idle|warming|revealing|cancelling`, `expanded|compact`): "Main window warmup started", "Main window will reveal", keyboard-focus verification after reveal, and `MainWindowInputCapture` buffers keystrokes typed between the hotkey and the WebView getting focus, then replays them ("Main window input replay…").
- **Hide on blur**: `windowDidResignKey` → `resignKey(keepWindowVisible:)`. Overrides: `settings.keepMainWindowVisibleOnResignKey`, `raycast.mainViewKeepsWindowVisibleChanged`, and `settings.keepMainWindowVisibleDuringDevelopment`. `popToRootTimeout` options `none|1-minute|5-minutes|10-minutes|15-minutes|30-minutes`.
- **Positioning**: `windowPresentationMode` = `mouse-screen | active-screen | primary-screen`, with a cached per-screen position (`raycast_window_cachedPosition_`). `moveToActiveSpace` / `switch-space` behavior. `windowActivationBehavior` and `windowMode` (default/compact) settings exist.
- **Input source auto-switch** on show (`InputSourceAutoSwitcher`, `settings.enforcedInputSourceId`, TIS* APIs).
- **Single instance**: `SingleInstanceGuard` (`SingleInstance.lock` with a holder PID, and activating the existing instance). The translocation guard refuses read-only volumes.

### 3.3 Hotkeys [O]
- Carbon `RegisterEventHotKey` / `UnregisterEventHotKey` / `InstallEventHandler` are imported, along with `CGEventTapCreate` (`com.raycast.keyboard-event-tap`).
- `RaycastMacOSUtils/Shortcut+Registry|Subscribers|Subscription|Observation|Virtualization|DoubleTapStateMachine` gives double-tap modifier hotkeys.
- `SymbolicHotkey.swift` uses private `CGSGetSymbolicHotKeyValue/CGSIsSymbolicHotKeyEnabled/CGSSetSymbolicHotKeyEnabled` to disable Spotlight's ⌘Space (`hotkey.commandSpaceAvailability`, `disable/enableSymbolicHotkey`). `GlobeKey.swift` resets the Fn/Globe key.
- IPC: `hotkey.register({id, hotkey})`, `hotkey.update`, `hotkey.remove({id})`, `hotkey.validate`, `hotkey.replaceCommandHotkeys({hotkeys})` ("Command hotkeys reconciled"), `hotkey.translateKeyCodes`, `hotkey.updateGlobal` (launcher hotkey), and `hotkey.toggleRecording` (shortcut recorder). Triggering → `general.openRaycastCommand` and `general.trackApplicationExecutedByHotkey`. Hotkey scopes are `local|global`. Push-to-talk hotkeys exist for dictation (`c:r:dictation::-::dictateText` etc.). Command ids look like `c:r:applications::*::application::=::…`.
- **Hyper key** (`RaycastHyperKey` module: `KeyRemapper`, `HID+DeviceManager`, `HID+SystemClient`, `HyperKey+Controller`):
  - It remaps Caps Lock (or Right Control, `RAYCAST_HYPERKEY_RIGHT_CONTROL`) at the IOHID level. It sets `HIDKeyboardModifierMappingSrc/Dst` through `IOHIDServiceClientSetProperty`, like `hidutil`, and handles the event tap.
  - It synthesizes ⌃⌥⇧⌘ (`includeShift` option), and a quick press can do a `capsLockAction` (`useCapsLockHyperKey(quickPressAction:hyperKeyFlags:)`).
  - Secure-input mode mirrors hotkeys with `RegisterEventHotKey`, because event taps are blind under Secure Input. Diagnostics: `settings.hyperKeyHealthSnapshot`, `hyperKeyDiagnosticLogging`.
  - IPC: `settings.hyperKey({keyCode, includeShift, capsLockAction})`.

### 3.4 Linux equivalent

| macOS | Wayland (primary) | X11 fallback |
|---|---|---|
| Floating non-activating NSPanel | **wlr-layer-shell** overlay surface (`gtk4-layer-shell` / `gtk-layer-shell`; wry can use GTK window + layer-shell) with `keyboard_interactivity=exclusive/on_demand`. Works on Hyprland, KDE (KWin supports layer-shell), Sway. **GNOME has no layer-shell**: use an undecorated always-on-top xdg-toplevel, or a small GNOME Shell extension | override-redirect or `_NET_WM_WINDOW_TYPE_DIALOG` + `_NET_WM_STATE_ABOVE`, `XSetInputFocus` |
| Hide on resign key | GTK `notify::is-active` / focus-out on the surface; layer-shell `on_demand` focus loss | FocusOut event |
| Vibrancy | Hyprland `layerrule = blur, <namespace>`; KDE `org_kde_kwin_blur` protocol (KWindowEffects); GNOME: none (Blur-my-Shell extension) | compositor-dependent (picom blur) |
| Screen-with-mouse positioning | Hyprland IPC `cursorpos`/`monitors`; KWin script; layer-shell `set_monitor`; GNOME: no cursor position without an extension | `XQueryPointer` + XRandR |
| Global hotkey | **xdg-desktop-portal GlobalShortcuts** (KDE, Hyprland's xdph, GNOME ≥ 48). Otherwise, a CLI/D-Bus toggle (`myapp toggle`) the user binds in the compositor (`bind = SUPER, Space, exec, …` in Hyprland) | `XGrabKey` (e.g. `global-hotkey` crate) |
| Per-command hotkeys | the same portal (one shortcut per id), or the compositor-bind + CLI approach | XGrabKey |
| Double-tap modifier, Hyper key, hotkeys under secure input | an evdev/uinput daemon: **keyd** or **kanata** configs (`capslock = overload(hyper, esc)`), or your own small evdev reader (needs the `input` group). XKB `caps:hyper` option for a pure remap | XKB `caps:hyper` / xcape |
| Spotlight ⌘Space conflict | n/a (GNOME: `gsettings` for the conflicting `switch-input-source` keybinding) | n/a |
| Input-source switching | IBus/Fcitx5 D-Bus (`fcitx5-remote -s`), GNOME `org.gnome.desktop.input-sources`, KDE `org.kde.keyboard` D-Bus | `setxkbmap` |
| Single instance | D-Bus well-known name (`org.example.Raycast`, GApplication) or a unix socket in `$XDG_RUNTIME_DIR` | same |

---

## 4. Native capabilities exposed by the host

### 4.1 Complete host method inventory [O]
These are all the `destination:"host"` methods in the generated clients: frontend 319 ∪ backend 206 = 408. The schema is **cross-platform**, and some methods are Windows-only (windowsTaskbar, MS Store, getShell*, runAsAdministrator, navigation.minimizeToTray, …). Marks: (FE) = frontend only, (BE) = backend only. Methods whose `ns.method` string also appears in the macOS binary are confirmed. Strings of 15 bytes or less are inlined by Swift, so a missing string does not prove a method is absent.

- **appMenuBar**: getMenuBar (FE), pressMenuItem (FE). Search the frontmost app's menu bar via AX (Accessibility XPC).
- **appleShortcuts**: getAllAppleShortcuts (BE), runAppleShortcut (FE). ScriptingBridge to Shortcuts.app.
- **applications**: getAllFiles (FE), getAllForPath, getAllInstalled (BE; `kMDItemContentTypeTree == 'com.apple.application-bundle'`), getAllRunning, getCategory (BE; LSApplicationCategoryType), getDefault, getDefaultSearchScopes (FE), getDeveloperClis (BE), getFocusedTextFieldContent, getFrontmost, getFrontmostWindowContext, getRecentFiles (FE), getSelectedContent, getSelectedText, getTextBeforeCaret, hide (FE), hideAllExceptFrontmost, open, quitActive (FE), quitAll, restart (FE), reveal (FE), runAsAdministrator (FE), runAsUser (FE), selectAll (FE), showDesktop, terminate, toggleStageManager, unhideAllHidden, uninstall (FE)
- **auth**: userChanged (BE)
- **bluetooth**: cancelPairing, forgetDevice, getAirPodsPower, getDetails, getDiscovery, getState, pairDevice, respondPairing, setConnection, startDiscovery, stopDiscovery (all FE), hasAdapter (BE)
- **calendars** (EventKit): createEvent, deleteEvent, deleteReminder, editEvent, getCalendars, getEvent, getEvents, getReminder, getReminders, respondToEvent
- **clipboard**: clearPasteboard (BE), convertImageToPng (FE), copyFile (FE), decodeQrCode (BE), getFilePaths (FE), getImagePaths (FE), placeInClipboard (`{entry:{target:"pasteboard",items:[{representations:[{content,contentType,mimeType}]}]},shouldCloseWindow}`; the backend's `paste` wraps it with overridePasteboard/excludeMainWindow/waitForPaste), plus `clipboard.shouldCaptureUniversalClipboard` (Swift)
- **contacts** (Contacts.framework): getContact, getContacts (BE), getContactsChanges (BE)
- **contextMenu**: open (FE). Native NSMenu.
- **debug**: emitSentryHostError, simulateHostCrash, testBackendGracefulShutdown (FE)
- **dictionary** (DCS*, private API): extractTerm, getHtmlDefinitions, getSuggestions
- **fileSystem**: annotateImage, dragStart, getQuickAccessRecentFiles, placeInTrashWithElevation, showFileInfo, showOpenFileDialog, showSaveFileDialog (FE); placeInTrash (BE); emptyTrash, getSelectedItems (Finder selection), openFile, openInTerminal, openTrash, revealFile, toggleHiddenFiles
- **hotkey**: register, update, remove, validate, replaceCommandHotkeys, translateKeyCodes (BE); commandSpaceAvailability, disableSymbolicHotkey, enableSymbolicHotkey, symbolicHotkeyStatus, toggleRecording, updateGlobal (FE)
- **location** (CoreLocation/MapKit): getCurrentLocation, resolvePlace, estimateTravelTime (BE)
- **media**: turnVolumeUp/Down, setVolume, toggleMute, playPause, nextTrack, previousTrack, toggleMicrophoneMute, toggleCameraMute (BE); getInputDevices, getApplications, setApplicationVolume, setApplicationMuted (per-app audio); FE: get/set Input/Output devices, settings, volume, mute, enabled, enhancements, format, listening, setDefaultInputDevice, getMicrophoneAccess/setMicrophoneAccess, Start/StopAudioLevelsWatching + get*AudioLevels, getMediaSessions, toggleMediaSessionPlayPause, skipMediaSessionNext/Previous, seekMediaSession, setMediaSessionRepeat/Shuffle (Now Playing), playSystemSound, playCustomSound, getTtsInstallStatus, installTtsLanguagePack
- **menuBar** (extension menu-bar extras via NSStatusItem): updateItems ({items}), removeItem, hideItem, showError, migrateStatusItemPlacement (BE); getItems (FE)
- **navigation** (window switcher via AX): closeWindow, getAllWindows, minimizeWindow, switchToWindow, toggleFullscreen, minimizeToTray (FE)
- **palette** (the Palette IME helper): activate, getCaretPositionEnabled, setCaretPositionEnabled, getStatus, resetSetup, showFileAccessPanel (FE)
- **permissions**: checkPermission, requestPermission, openSystemSettings. Permission keys seen: `permission.accessibility`, `permission.calendars`, `permission.contacts`, plus screen recording, automation (`AEDeterminePermissionToAutomateTarget`), location, microphone, camera.
- **raycast** (app/window control): showMainWindow, hideMainWindow, hideWindow, warmupMainWindow, setMainWindowPreparation, resizeWindow, resetPosition, setCompactMode, setAppearance, resignKeyWindow, shakeMainWindow, toggleBounceAnimation, confetti, toggleZoom, show{Settings,AiChat,Notes,ThemeStudio,Playground,Welcome,ProWalkthrough,Feedback}Window, showWindowCaptureOverlay, setAiChatWindowFloating, setAiChatWindowCloseHandler, setAiChatHistoryMenu, openMainWindowFromWelcome/FromProWalkthrough, openRaycastMainAtRoute, getFocusedRaycastWindowIdentifier, mainViewHotkeyPresentedChanged, mainViewKeepsWindowVisibleChanged, webViewStateChanged, inspectWebView/toggleInspectWebView, purgeWebContentMemory, teardownComplete, dragStart, start/stop/cancelDictation, captureDictationContext, getDictationAudioLevels, pressDictationSubmitKey, retryDictationTranscription, formatCalculatorResultNumber, workspaceBrowser, workspaceTerminal, quit, restart, terminateOtherInstances, removePreviousAppBundle, getRecentLogs, revealLogFiles, captureMemoryDump, setTelemetryTags, pdfExtraction (PDFKit), onboarding (completeOnboarding, acceptWelcomeTos, set/consumeWelcomeResumeStep, welcomeLaunchStepChanged, getWindowsOnboardingState, completeV2Welcome)
- **raycastFocus** (Focus sessions, app/website blocking): startSession, notifySessionStarted, toggleSession, pauseSession, resumeSession, completeSession, completeSessionWithReason, cancelSession, moveSessionToMenuBar, handleWebsiteSnooze
- **releases**: performInstallUpdate, getUpdaterBackgroundItemStatus, getStartupContext, checkForMSStoreUpdate, installMSStoreUpdate
- **screenshots**: getDefaultScreenshotLocations
- **settings**: hyperKey, uiZoom, themeChanged, generalSettingsChanged, internalExtensionSettingsUpdated, keepMainWindowVisibleDuringDevelopment (BE); FE: openAtLogin (SMAppService), menuBarItem, tidyMenuBar, windowPresentationMode, windowActivationBehavior, windowCacheMode/setWindowCacheDuration/getWindowCacheDurations, showWindowsImmediately, keepMainWindowVisibleOnResignKey, enforcedInputSourceId, hyperKeyDiagnosticLogging(+Status), hyperKeyHealthSnapshot, hyperKeySecureInputModeEnabled/setHyperKeySecureInputMode, get/setWebContentProcessMode, webKitRenderUpdatesNear60Fps, clearMemoryCache, togglePerformanceLogs, recordStallDiagnostics, previewThemeBackgroundColors, raycastApiEnvironment, internalLogoVariant, enableSilentUpdates, (get)alwaysShowWelcomeWindowOnStart, openFoldersInTabs, Windows-only taskbar/UIAccess items
- **sharingService**: getMenuItems, openPicker, performShare (NSSharingService)
- **snippets**: register ({snippetIds, keywords}), remove (BE), expand (FE). The host watches keystrokes and expands keywords.
- **system**: lockScreen, logOut, sleep, hibernate, sleepDisplays, showScreenSaver, ejectAllDisks, dismissNotifications, toggleQuickLookPreview, showQuickLookPreviewIfNeeded, isQuickLookPreviewVisible, toggleSystemAppearance, toggleAirplaneMode, toggleBluetooth, toggleHdr, toggleNightLight, get/setStickyKeysShortcutNotification, getManagedSignInPolicy, getSystemAppearance, getComputerSystemInfo, getDeviceTagFallbackSeed, getMemorySample, setPreventIdleSleep, isOnBatteryPower, isEnergySaverSupported, toggleEnergySaver, wakeDetected, readClassicKeychainValue, readSharedKeychainValue, readClassicUserDefaults, executeInTerminal; FE: getDisplays, getAvailableInputSources, openPreference, revealPreference, openCamera, performHapticFeedback, replaceSpotlightGesture, fixLoginItems, restart, shutDown, Windows-only run-command/shell items
- **systemNotifications**: show ({id,title,body}), dismiss. UNUserNotificationCenter; clicks come back as `systemNotifications.notificationClicked`.
- **uiTesting**: getBuildFlavor, listWindows, screenshot, screenshotForDocs, executeInWindow, typeText, resizeWindow, toggleMainWindow, triggerHotkey
- **userDefaults**: didChange
- **virtualDesktops** (Spaces via private CGS*): getAll, getActiveIndex, getByIndex, switch (+ FE: close, rename, moveActiveWindow)
- **weather** (WeatherKit): getCurrentWeather
- **wifi**: hasAdapter, toggleRadio (BE); FE: getState, getDetails, getConnectivity, scan, join, setConnection, forgetProfile, setProfile, getPassword
- **windowManagement** (AX window control): getDesktops, getActiveWindow, getWindowsOnActiveDesktop, getVisibleWindows, getMinimizedWindows, setWindowBounds, minimizeWindow, closeWindow, toggleAlwaysOnTop, cycleAppWindows, showGridPlacement, openAndSetWindowBounds, getOpenedWindows, getTrayItems, clickTrayItem; the host also notifies `openedWindowsChanged`
- **workspace** (AI context, ScreenCaptureKit + AX): getWorkspaceContext, getFrontmostAppContext, getFocusedElementContext, captureFocusedWindow, captureScreen, captureScreenArea, captureWindowById, captureAiContext

Backend → `frontend:main` requests (Swift relays them to the WebView): `uiTesting.*` (Playwright-like: snapshot, click, type, fillForm, pressKey, mouse*, evaluate, waitFor…), `extensionHost.{render,renderEmpty,renderSuspense,showToast,hideToast,showHUD,showAlert,popToRoot,clearSearchBar,closeMainRaycastWindow,commandException,initOAuth,authorizeOAuth,open*Preferences,ensureBrowserExtensionInstalled,getToolPreferences,createSnippet,createQuicklink}`, `image.renderImage(s)` (the host also uses this to render menu-bar icons), `calendars.{openCalendarEvent,joinMeetingForEvent,handleMeetingAutoJoin}`, `general.{refreshRootSearch,showExtensionInstall,showThemeImport,showPromptImport,showAiModeImport,showMcpOAuth,showImportSettingsData,handleExtensionOAuthCallback,canInstallUpdateInBackground,showToast,confirmRemoteAiChatPairing,closeMainWindow,openRaycastCommand,confirmExternalCommandLaunch,openRaycastMainAtRoute,openSettings}`, `notes.{parseNoteContent,serializeNoteContent,insertNoteContent}`, `windowManagement.executeLayout`.

Backend → frontends notifications (`emit*`), as an abridged list: `ai.*Updated/Invalidated/Stream*`, `auth.userChanged/accessTokenChanged`, `clipboard.stateChanged`, `indexer.stateChanged/updated/semanticStateChanged/applicationsUpdated`, `settings.update*` (theme, uiZoom, windowMode, windowPresentationMode, escapeKeyBehavior, navigationBindings, openAtLogin, showInMenuBar, …), `extensionHost.*`, `snippets.updated`, `quicklinks.updated`, `notes.updated`, `themes.updated`, `system.sessionStatusChanged`, `releases.downloadStatus`, `calendars.*`, `contacts.contactsChanged`, `userDefaults.defaultChanged`, `appFlags.flagsChanged`, `mcp.serversUpdated`. The host itself emits `media.*Changed`, `menuBar.itemsChanged`, `windowManagement.openedWindowsChanged/trayItemsChanged`, `virtualDesktops.virtualDesktopsChanged`, `window.*`.

### 4.2 Native mechanisms behind them [O imports/strings]
- **Accessibility**: `AXUIElement*`, `AXObserver*`, `AXTextMarker*`, `AXIsProcessTrusted(WithOptions)`. Selected text uses `AXSelectedText`/`AXSelectedTextRange`/`AXStringForRange`, with a fallback of copying through the pasteboard [I]. Frontmost element/app uses `AXFocusedUIElement`/`AXFocusedApplication`. Menu bar uses `AXMenuItemCmdChar…`.
- **Keystroke injection / paste**: `CGEventCreateKeyboardEvent`, `CGEventPost`, `CGEventPostToPid`, `CGEventSource*`, `IOHIDSetModifierLockState`. Snippet paste flow (Accessibility XPC): write to the pasteboard → send ⌘V → verify "The target did not request snippet pasteboard data after the paste shortcut" → restore the selection.
- **Pasteboard**: NSPasteboard. It honors the nspasteboard.org markers `org.nspasteboard.TransientType/ConcealedType/AutoGeneratedType` and `com.apple.is-remote-clipboard` (Universal Clipboard).
- **Window list / Spaces**: `CGWindowListCopyWindowInfo`, private `CGSCopyManagedDisplaySpaces`, `CGSGetActiveSpace`, `CGSCopySpacesForWindows`, `CGSSpaceGetType`, and `CoreDockSendNotification` (Mission Control/show desktop).
- **Screen capture**: ScreenCaptureKit (`shareableContent()`), `CGPreflight/RequestScreenCaptureAccess`.
- **OCR**: Vision.framework is linked [O], for QR decoding (`clipboard.decodeQrCode`) and text recognition [I].
- **Calendar/Reminders**: EventKit (`EKEventStoreChangedNotification`) in `CalendarEventStore`. **Contacts**: CNContactStore + `CNContactStoreDidChangeNotification`.
- **Location/Maps**: CoreLocation + MapKit (`estimateTravelTime`). **Weather**: WeatherKit.
- **Files**: Spotlight `MDQuery*`/`MDItem*`, `FSEventStream*` (`FileSystemWatchdog`), QuickLookUI/QuickLookThumbnailing, DiskArbitration (eject), `LSCopyDefaultApplicationURLForURL`.
- **Power/session**: `IOPS*` (battery), NSWorkspace will-sleep/did-wake and session active/resign notifications, `CGSessionCopyCurrentDictionary`. Lock/sleep are done through `NSWorkspace+SystemCommands.swift` [O file name; exact mechanism I].
- **Audio**: CoreAudio `AudioObject*` (devices, per-app volume), AVFoundation (mic for dictation), system sounds.
- **Notifications**: UserNotifications (`UserNotificationManager`). **Launch at login**: ServiceManagement (`BackgroundItemService`, register/unregister/notRegistered). **Keychain**: `SecItem*`. **Code signing checks**: `SecCode*`, `SecRequirementCreateWithString`.
- **URL schemes / documents**: `CFBundleURLSchemes` = `raycast`, `raycast-x`, `com.raycast`, `com.raycast-x` → forwarded as `system.handleDeeplink` to the backend. Document type `.rayconfig` (settings import). An NSServices entry "Send to Raycast AI" (`sendToAIChat`).
- **Secure input detection**: `IsSecureEventInputEnabled` (`SecureInputMonitor`).

### 4.3 Linux equivalents per capability

| Capability | Linux (Wayland-first) | X11 / notes |
|---|---|---|
| App list, icons, categories | XDG `.desktop` files (`$XDG_DATA_DIRS/applications`), `Categories=`; icons via the icon theme (`gtk::IconTheme`, `freedesktop-icons` crate); `ipc://image` renders them | same |
| Open app / default app | `gio launch`/`gtk-launch`, D-Bus activation, `xdg-mime query default`, `xdg-open` | same |
| Running/frontmost app, window list, focus, close, minimize, bounds, always-on-top, cycle | **Hyprland IPC** (`hyprctl -j clients/activewindow`, `dispatch movewindowpixel/resizewindowpixel/focuswindow/closewindow/pin`, socket2 events); **KWin** scripting via D-Bus (`org.kde.kwin.Scripting`) or the `kdotool` approach; **GNOME** needs a Shell extension (e.g. "Window Calls" D-Bus); wlroots: `wlr-foreign-toplevel-management` / `ext-foreign-toplevel-list` (list/activate/close only) | EWMH via `x11rb`/`wmctrl`/`xdotool` |
| Virtual desktops / Spaces | Hyprland workspaces (`dispatch workspace N`); KWin `org.kde.KWin.VirtualDesktopManager`; GNOME extension or `org.gnome.Shell` eval (disabled by default); `ext-workspace-v1` where available | `_NET_CURRENT_DESKTOP` |
| Selected text | PRIMARY selection (`wl-paste --primary`, `ext/wlr-data-control`) as the cheap path; AT-SPI2 `Text.GetSelection` on the focused accessible (`atspi` crate) | XA_PRIMARY |
| Focused field content / text before caret | **AT-SPI2** `Text` interface (GTK/Qt/Chromium/Firefox expose it; Electron needs `--force-renderer-accessibility`); or an **input-method engine** (IBus/Fcitx5 `surrounding text`) | same |
| App menu bar search | KDE global menu: `com.canonical.dbusmenu` via `com.canonical.AppMenu.Registrar`; GTK `org.gtk.Menus`; AT-SPI menu roles. Coverage is partial | same |
| Paste / keystroke injection | **wtype** / `zwp_virtual_keyboard_v1` (wlroots, Hyprland), **RemoteDesktop portal** `NotifyKeyboardKeycode` (GNOME/KDE, needs consent), `ydotool`/uinput (universal, needs a daemon with uinput access) | XTest (`xdotool key ctrl+v`) |
| Snippet keyword expansion | evdev keyboard monitor (`input` group) + delete/paste via uinput; **or an IBus/Fcitx5 engine** (the closest analogue of Raycast Palette: commit text, read surrounding text and caret rect) | XRecord / XInput2 raw events |
| Clipboard history + write | `wl-clipboard` / **`ext-data-control-v1`** (wlr-data-control on older compositors; KDE supports it; GNOME does not, so fall back to a focused-window `wl-paste --watch` or a GNOME extension). Honor `x-kde-passwordManagerHint=secret` as the ConcealedType analogue | XFixes `SelectionNotify` |
| Screen / window / area capture | **xdg-desktop-portal Screenshot/ScreenCast** (PipeWire); wlroots: `grim` + `slurp`, `hyprshot`; KDE `spectacle`/`org.kde.KWin.ScreenShot2` | `XGetImage`, `maim` |
| OCR / QR | Tesseract (`leptess`) or PaddleOCR/ONNX; `zbar`/`rqrr` for QR | same |
| Calendar / reminders | **evolution-data-server** D-Bus (GNOME Online Accounts), KDE **Akonadi**, or direct CalDAV (`libdav`/`minicaldav`) | same |
| Contacts | EDS address book / Akonadi / CardDAV | same |
| Location | **GeoClue2** D-Bus (or the Location portal) | same |
| Notifications | `org.freedesktop.Notifications` (`notify-rust`); action-invoked signal = notificationClicked | same |
| Lock / logout / sleep / hibernate / shutdown / restart | **logind** D-Bus (`LockSession`, `Suspend`, `Hibernate`, `PowerOff`, `Reboot`); logout via `TerminateSession` or the DE session manager (`org.gnome.SessionManager.Logout`, `org.kde.Shutdown`); Hyprland `hyprctl dispatch exit` | same |
| Screen saver / sleep displays | `org.freedesktop.ScreenSaver`; DPMS: `hyprctl dispatch dpms off`, KWin `org.kde.Solid.PowerManagement`, GNOME `org.gnome.Mutter.DisplayConfig` power-save mode | `xset dpms force off` |
| Prevent idle sleep | `org.freedesktop.ScreenSaver.Inhibit` / logind `Inhibit` / idle-inhibit portal | same |
| Empty trash / trash / reveal | `gio trash`, the FreeDesktop Trash spec; reveal via `org.freedesktop.FileManager1.ShowItems` | same |
| Eject disks | **UDisks2** D-Bus (`Filesystem.Unmount`, `Drive.PowerOff`) | same |
| Dark mode toggle | portal `org.freedesktop.appearance color-scheme` (read); set via `gsettings set org.gnome.desktop.interface color-scheme`, `plasma-apply-colorscheme`/`lookandfeeltool`, Hyprland per-config | same |
| Night light | GNOME `org.gnome.settings-daemon.plugins.color night-light-enabled`; KDE `org.kde.KWin.NightLight`; Hyprland `hyprsunset` | `redshift` |
| Volume, mute, devices, per-app volume | **PipeWire/WirePlumber** (`wpctl`, `pipewire-rs`) or PulseAudio API (`libpulse`) | same |
| Media keys / now playing | **MPRIS** D-Bus (`playerctl`) | same |
| Mic mute | `wpctl set-mute @DEFAULT_SOURCE@ toggle` | same |
| Bluetooth | **BlueZ** D-Bus (`bluer` crate); battery via `org.bluez.Battery1` | same |
| Wi-Fi / airplane | **NetworkManager** D-Bus (`nmcli`), `rfkill` | same |
| Battery / power source | **UPower** D-Bus; power profiles (`power-profiles-daemon`) = Energy Saver | same |
| Sleep/wake/network change events | logind `PrepareForSleep`, NetworkManager `StateChanged` | same |
| Quick Look | GNOME **sushi** (`org.gnome.NautilusPreviewer`), or your own preview window (poppler, image, text) | same |
| File/thumbnail icons | the freedesktop **thumbnail spec** (`~/.cache/thumbnails`, `org.freedesktop.thumbnails.Thumbnailer1` / tumbler) | same |
| File open/save dialogs | **FileChooser portal** (`ashpd`) | GTK dialogs |
| Dictionary | `dictd`/`sdcv` (StarDict) or Wiktionary dumps | same |
| Weather | Open-Meteo / MET Norway API | same |
| Menu-bar extras (status items) | **StatusNotifierItem** (`ksni` crate) + `com.canonical.dbusmenu`; Waybar/KDE tray show them; GNOME needs the AppIndicator extension | XEmbed tray |
| Sharing service | the portal `OpenURI`, `xdg-email`, KDE Purpose | — |
| Launch at login | XDG autostart `~/.config/autostart/*.desktop`, the **Background portal** `RequestBackground(autostart=true)`, or a systemd user unit | same |
| URL scheme `raycast://` | `.desktop` `MimeType=x-scheme-handler/raycast;` + `xdg-mime default`; the second instance forwards argv over D-Bus to the primary (`system.handleDeeplink`) | same |
| Keychain | **libsecret** (`oo7` / `secret-service` crate) | same |
| Permissions UX | portals ask per-capability; AT-SPI needs `org.a11y.Status IsEnabled=true` (`gsettings set org.gnome.desktop.interface toolkit-accessibility true`); uinput/evdev need the `input` group or udev rules | — |
| Haptics, Stage Manager, Apple Shortcuts, WeatherKit, Universal Clipboard | no equivalent; drop them or stub them out (KDE Connect can partly replace Universal Clipboard) | — |

---

## 5. XPC services, Palette helper, Updater

### 5.1 `Raycast Accessibility.xpc` (`com.raycast.macos.accessibility`, ServiceType=Application) [O]
- Swift module `RaycastMacOSAccessibility`: `Service.swift`, `Router.swift`, and the workers `AppMenuBarWorker`, `NavigationWorker`, `SnippetInjectionWorker`, `WebsiteBlockingWorker`, `WorkspaceWorker`. It runs AX work out of process, so AX hangs or crashes cannot block the main app.
- Messages (enum `XPC.Accessibility`, `IdentifiableMessage`): `ObserveMenuBarChange`, `ToggleFullscreen`, `StartSnippetInjection`, `CancelSnippetInjection`, `SnippetInjectionCompleted`, `StartWebsiteBlocking`, `StopWebsiteBlocking`, `RestoreWebsiteInBrowser`, `WorkspaceAppContextNodeDetail`, `WorkspaceAppContextSummary`, `WorkspaceSummary`. Error strings show shorter, inlined messages too: get menu bar, press menu item, get navigation windows, switch to/close/minimize window ("Failed to press menu item", "Failed to get navigation windows", …).
- Snippet injection: it writes to the pasteboard, sends the paste shortcut to the target pid, verifies the cursor (`AXSelectedTextRange`, `AXSelectedTextChanged`), and restores the selection. It has cancellation states (`cancelledBeforeMutation`, `cancelRequestedAfterMutation`).
- Website blocking (Focus): it reads the browser URL via AppleScript (`tell application "…" … URL of …`) and AX (Safari `navigationBarAssistantBarTextField`, Firefox `urlbar-go-button`, Chrome `commandBarToolbarButton`), then redirects to `https://raycast.com/focus-session`. It reports `focus.websiteBlockedActivityEvent`.
- **Linux**: a separate worker process (Rust) speaking JSON over a unix socket or D-Bus, which does the AT-SPI, compositor-IPC and uinput work. Do website blocking with a **browser extension** (you already need one for `bext.*`) instead of AppleScript.

### 5.2 `Raycast Pasteboard.xpc` (`com.raycast.macos.pasteboard`) [O]
- `Raycast_Pasteboard/ClipboardCaptureWorker.swift`, `ClipboardEntryExtractor.swift`, `ClipboardSequence.swift`, `Router.swift`, `Service.swift`. This is clipboard **history capture**.
- It detects changes by **tailing the unified log of `pasteboard-server`** (regexes `Current generation after remote pasteboard change:\s+(?<generation>\d+)`, `Resolving promise for pboard 'Apple CFPasteboard general' generation:(?<generation>\d+)`), and falls back to polling `changeCount`. It handles Universal Clipboard (`com.raycast.apple-universal-clipboard`), skips transient and concealed types, and serializes every representation.
- **Linux**: a `wl-paste --watch`-style daemon on **ext-data-control-v1 / wlr-data-control** (KDE, Hyprland, Sway). On GNOME, use a Shell extension or a focused-only fallback. On X11 use XFixes. Store entries in the backend DB the way the backend expects (`clipboard.*` handlers).

### 5.3 `Raycast Palette.app` (`com.raycast.macos.palette`) [O]
- It is an **InputMethodKit palette input method**: `InputMethodType=palette`, `InputMethodServerControllerClass=RCPaletteInputController`, `TISInputSourceID=com.raycast.macos.palette`. The main app registers and selects it with `TISRegisterInputSource/TISEnableInputSource/TISSelectInputSource`.
- Selectors: `insertText:replacing:targetProcessID:targetBundleID:completion:`, `performInsertion:…`, `inspectCaretForProcessID:targetBundleID:completion:`, `attributesForCharacterIndex:lineHeightRectangle:` (caret geometry), `selectedRange`, `markedRange`, `validSelection:`.
- Error states: `input-method-active`, `secure-input-enabled`, `input-client-activation-timed-out`, `caret-geometry-unavailable`, `client-has-selected-text`, `client-caret-before-keyword`, `insertion-not-confirmed`, `inserted`.
- Purpose: insert snippet text **without the clipboard** and get the **caret position** (to place popups and for the AI "caret position" feature: `palette.getCaretPositionEnabled`). It talks to the host over a connection (`sessionConnection` fd; `com.raycast.palette.injection` queue) [I: unix socket].
- **Linux**: write an **IBus engine or Fcitx5 addon**. It can `commit_text`, use `delete_surrounding_text` to remove the keyword, and read `surrounding_text` and the cursor location (`SetCursorLocation`). This is the cleanest snippet-expansion path on Wayland (GNOME uses IBus; KDE and Hyprland usually Fcitx5).

### 5.4 Updater (`Contents/Resources/Updater`, LaunchAgent `com.raycast.macos.updater`) and UpdaterDaemon (LaunchDaemon `com.raycast.macos.updater.daemon`) [O]
- Agent (`Updater/Service.swift`, `Work+Update.swift`, `Work+Restart.swift`, `Work+ProcessSweep.swift`): it accepts one XPC session at a time (update/restart/bootstrap states). It mounts the DMG and verifies the bundle and its id. It shuts down running instances (terminate, then force), replaces the bundle, falls back to the **privileged daemon** across volumes or for permission issues, sweeps leftover processes inside the bundle and backend directories, and relaunches with `--silent-restart`, retrying on failure.
- Daemon: root, "Caller is not an authorized updater agent". It backs up, copies from the DMG, removes quarantine, and replaces the bundle as root (`replaceItemAtURL:…`).
- Backend side: `releases.performInstallUpdate`, `releases.getUpdaterBackgroundItemStatus`, `releases.emitDownloadStatus`.
- **Linux**: ship it as an **Arch package (PKGBUILD/AUR)** so pacman does updates, or as an AppImage with `appimageupdatetool` / zsync. If you self-update into `/opt`, use `pkexec` with a polkit action instead of a daemon. To restart, re-exec yourself after the backend's graceful shutdown.

---

## 6. Unknowns / caveats
- Numeric values for `startup_timeout`, `request_timeout`, `shutdown_timeout`, `startup_timeout_extension`, `max_restart_attempt(_duration)`, and the health-probe interval/thresholds are set from Swift or Rust code. They are not recovered without decompilation (REA/Hopper was unavailable). Reasonable clone defaults: startup 30 s + 10 s per step, request 5 s (matches the JS default), shutdown 3–5 s (the JS races its own shutdown against 3 s/5 s), 3 restarts within 60 s, and a ping every ~10 s with a stall threshold of ~10 s.
- The XPC wire format (XPCSession + Codable `IdentifiableMessage`) and short message names are not fully enumerable from strings.
- Whether `window.ipcRequest` is invoked via `callAsyncJavaScript` or `evaluateJavaScript` (both selectors are imported) is not confirmed; behaviorally it returns a Promise of a JSON string.
- Some host methods in the shared schema are Windows-only. On macOS, a missing handler returns `RequestError::MethodNotImplemented` / "Host doesn't implement handler" [O].

## 7. Key evidence locations
- `/Applications/Raycast.app/Contents/Frameworks/libraycast_host.dylib`: `_UNIFFI_META_RAYCAST_HOST_*` symbols (blobs with doc comments), serde names `FramedInboundMessageHeader/FramedInboundPayloadHeader`, and `[backend-coordinator]` log strings.
- `…/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources/backend/index.mjs`: stdio server class (`handleStdinData`, `handleInitialization`, `nsn`/`asn` framing, offsets ~1.74 MB), `Qft` stdout writer (~0.79 MB), generated host client `function Cft(e)` (~0.75 MB), handler map `SZa` (~7.36 MB), and external WS server (`zSa={Development:7261,Internal:7262,Production:7265}`).
- `…/frontend/register-query-client-CHYpWjSJ.js`: `window.webkit.messageHandlers.ipcRequest.postMessage`, `window.ipcRequest/ipcNotification`, generated `host`/`backend` clients, and the notification center.
- `/Applications/Raycast.app/Contents/MacOS/Raycast`: Swift strings (`RaycastDesktopApp/*.swift`, handler method names, injected JS) and imported APIs.
- Helper binaries and their plists, as listed in section 5.
