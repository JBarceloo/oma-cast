# 03 — Raycast 2.8.2 extension runtime and protocol (static RE)

Scope: how `@raycast/api` extensions are run, the React reconciler and render-tree wire format, the full API→RPC surface, the manifest schema, Script Commands, Store install/update, and macOS-specific parts with Linux substitutes.

Method: static reading only. I pretty-printed these with esbuild (no execution):
- `B/api/node_modules/@raycast/api/index.js` (740 KB, the one runtime file shipped to extensions; no `.d.ts`, no `package.json`)
- `B/backend/index.mjs` (7.4 MB, the extension host)
- `B/frontend/main-window-*.js` (the UI that consumes render trees)

`B` = `/Applications/Raycast.app/Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources`.

Legend:
- **[O]** observed verbatim in code.
- **[I]** inferred.
- Minified identifiers are given only so you can find things again, for example `backend.mjs:D3` = `function D3` in the pretty-printed backend.

No REA session was opened. Everything was done with shell tools and esbuild formatting.

---

## 0. Architecture at a glance

```
 Swift host app (AppKit)  <--"host.*" RPC-->  backend Node process (index.mjs, bundled node v22.23.3)
        ^                                         |  one process, many worker_threads
        | "frontend:main" RPC                     |  new Worker(B/api/node_modules/@raycast/api/index.js)
 Web frontend (B/frontend/*.js, React UI)         v
   renders render-tree JSON  <-- extensionHost.render ---  Worker: @raycast/api runtime + extension code
   user events --> backend.extensionHost.callNodeCallback --> worker "nativeCallback"
```

- **[O]** The backend runs on the bundled Node in `~/Library/Application Support/com.raycast.macos/node/runtime/node-v22.23.3-darwin-arm64` (the `backend.pid` is next to it). The tarball is `B/node/node-v22.23.3-darwin-arm64.tar.gz`.
- **[O]** Each extension entry-point run is one **`worker_threads` Worker** inside that backend process. It is not a child process. Workers are pooled and prewarmed.
- **[O]** The worker's main module is the API bundle itself (`A2i = ie(r3, "@raycast","api","index.js")`). The API runtime `require()`s the extension's `dist` file.
- For a Linux clone: the backend is reusable JS logic. Replace the Swift `host.*` calls and the web frontend with your own (for example GTK/Qt/webview).

---

## 1. Launching a command

### 1.1 On-disk layout [O]

| Item | Path |
|---|---|
| Installed build dir | `~/.config/raycast/extensions/<uuid or name>/` (`nx(e)=join(homedir,".config","raycast","extensions", e.uuid \|\| e.name)`). Store installs use the store **uuid**; dev/local builds use the **name**. |
| Command entry | `<buildDir>/<commandName>.js` |
| Tool entry | `<buildDir>/tools/<toolName>.js` |
| Widget entry | `<buildDir>/widgets/<name>.js` (`rx()`) |
| Other files in build | `package.json` (processed manifest), `assets/`, `skills/` (allowed-files filter at `backend.mjs:136492`) |
| Module resolution | `~/.config/raycast/extensions/node_modules` is a **symlink → `B/api/node_modules`**, repaired on every worker creation (`l2i`). The worker env also has `NODE_PATH=B/api/node_modules`. Extensions keep `@raycast/api`, `react` and `react/jsx-runtime` **external**. `@raycast/utils` and everything else is bundled into each `dist/*.js`. |
| Support dir (`environment.supportPath`) | `join(SUPPORT_DIR,"extensions", uuid\|\|name)`, created before launch. On macOS SUPPORT_DIR = `~/Library/Application Support/com.raycast.macos`. |
| Assets (`environment.assetsPath`) | `<buildDir>/assets` |
| Dev log | `<buildDir>/dev.log`. Each `logCommand` appends a line `JSON.stringify([Level,message])` and the file is truncated after 50 lines (`M0i`, `A0i=50`). |
| node compile cache | `~/.config/raycast/node-compile-cache` (`NODE_COMPILE_CACHE`) |
| Shipped React | react 19.2.1, react-reconciler 0.31.0, react-devtools-core 6.1.1 (`react-devtools-raycast`, connects to `localhost:8097` in development only) |

Built `dist/*.js` files are CommonJS (esbuild output). They `module.exports.default = Command` and `require("@raycast/api")` / `require("react/jsx-runtime")` (see `B/api/template/dist/*.js`).

### 1.2 Worker creation (`backend.mjs` class `L2i`, around line 136040) [O]

```js
new Worker(".../@raycast/api/index.js", {
  workerData: {
    isDevelopment, canAccessAI, canAccessBetterAIModels, canAccessWindowManagement,
    textSize: "medium", appearance: "light"|"dark",
    resolvedProxyConfig, caCertPaths, systemCAs, isBrowserExtensionInstalled,
    workerPath, maxHeapSizeMb: 100 },
  stdin: true, stdout: true, stderr: true,
  env: { PATH, NODE_ENV: isDevelopment?"development":"production",
         NODE_PATH: B/api/node_modules, RAYCAST_VERSION, RAYCASTX:"1",
         RAYCAST_SCHEME, HOME, TMPDIR, TEMP, LC_ALL, TZ, FAVICON_PROVIDER, NODE_COMPILE_CACHE },
  resourceLimits: { maxOldGenerationSizeMb: 100 } })
```

- **Memory limit is a 100 MB JS heap per command.** An OOM is reported as `"Command terminated after reaching the extension memory limit (100 MB JS heap)."` (code 23 `OutOfMemory`).
- **Pool:** 1 prewarmed prod worker and/or 1 dev worker (`P2i=1`, `F2i=1`). `getFromPool` pops one and asynchronously creates a replacement. Background launches always create a fresh worker. The pool is re-warmed on these events: `browserExtensionDidConnect`, `updateAppearance`, `updateTheme`, `updateFaviconProvider`, `updateProxySettings`, `auth:userChanged`, `nodeExtension:installed`, `nodeExtension:updated`, `nodeExtension:uninstalled`, the developer setting changing, and the userDefault `NodeExtensionWorkerPrewarmingDisabled` changing.
- **Sandbox: none beyond the worker.** The worker has full Node (fs, net, child_process). The API monkey-patches `child_process.spawn/exec/execFile/fork` to report `{kind:"child-process", event:{type:"spawned",pid,executable}|{type:"exited",pid}}` to the parent. The parent kills tracked children when the worker ends (`releaseChildProcesses`). The worker's `console.*` is redirected to the `logCommand` notify. HTTP(S) goes through a bundled undici/proxy-agent configured from `resolvedProxyConfig` plus custom and system CAs.
- **Integrity:** if userDefault `ExtensionIntegrityCheckEnabled` is set (default false), the entry file's sha digest and mtime (stored at install time) are verified. A mismatch gives `"The entry point file appears to be corrupted"`.

### 1.3 Session start (`backend.mjs:D3`) [O]

1. Resolve `<buildDir>/<name>.js`. If it is missing: `"Missing executable. You might need to build/reinstall the extension."`
2. At most 4 live sessions per entry point. The oldest non-exempt sessions are unloaded first.
3. Build the `initialize` params, then call `worker.load(params)` → `request("initialize", params)`:

```jsonc
{ "id": "<sessionId>", "entryPointName": "search", "ownerOrAuthorName": "raycast",
  "entryPointType": "command" | "tool" | "widget" | "model_provider",
  "entryPointMode": "view" | "no-view" | "menu-bar",
  "extensionName": "my-ext",
  "preferences": { "<prefName>": { "type":"textfield", "value":..., "default":..., /*manifest fields*/ } },
  "supportPath": "...", "assetsPath": "<buildDir>/assets",
  "enableMemoryReporting": false, "startedAt": 1729000000000,
  "launchType": "userInitiated" | "background",
  "namedExport": undefined,            // default export unless set
  "timeout": <number|undefined>,
  // command:
  "argumentValues": {"query":"foo"}, "launchContext": "<JSON string or null>",
  "fallbackText": "...", "draftValues": "<JSON string>", "commandPath": "<abs path to dist js>",
  // tool:   "arguments": "<JSON string>", "toolPath": "...", "shouldExecuteFunctionsBeforeReturning": true
  // model_provider: "modelProviderPath", "model", "request", "streamId"
}
```

The worker's `initialize` handler (`v3` → `mC`) does the following:
- Sets `process.env.EXTENSION_NAME`, `COMMAND_NAME`, `ASSETS_PATH`, `SUPPORT_PATH`, and `RAYCAST_SESSION=id`.
- Waits for proxy/CA setup.
- Dispatches on type and mode:

| entryPointType / mode | Worker behavior (`L3`) |
|---|---|
| command / `no-view` | `require(commandPath)[namedExport\|\|"default"]`. If it is a function, call it with `LaunchProps`. `initialize` resolves with the return value once the promise settles. **The backend then unloads the worker immediately** (`entryPoint.mode==="no-view" && !deferNoViewUnload → E3()`). |
| command / `view`, `menu-bar` | The export must be a valid React element type. Async functions are rejected with `"Async main functions for 'view', 'menu-bar', or 'widget' commands are unspecified behavior…"`. The runtime then does `createRoot(Symbol("raycast-root")).configure({onPromoteTree: requestNativeMount}).render(<Command {...launchProps}/>)`. `initialize` resolves right away and the worker stays alive. |
| tool | `require(toolPath)[export](JSON.parse(arguments))`. The result is JSON-serialized, and function values are either executed or turned into callback ids (`__raycast_function_<key>_<n>_action`). |
| model_provider | Exports `getModels` or `streamCompletion(model, request)`. Chunks go out as the notify `modelProviderStreamChunk {streamId, chunk}`. AI only, noted. |
| widget | `"Widgets are not supported in this build"`. |

`LaunchProps` passed to the command (`vx`):

```js
{ fallbackText, arguments: argumentValues||{}, launchType,
  get launchContext(){ return JSON.parse(launchContext, reviver) },
  draftValues /* parsed: {id: value} with {type:"date"} values turned into Date */ }
```

The reviver decodes `"__raycast_serialized_date__<ISO>"` and `"__raycast_serialized_buffer__<b64>"`. `launchCommand` uses the matching replacer.

### 1.4 Lifecycle, timeouts, unload [O]

- **Timeout:** `timeout = launchType==="userInitiated" ? undefined : Math.min(intervalMs ?? 300000, 300000) * 0.9`. The worker then does `setTimeout(this.timeout, timeout * 1e3)`. **Observed unit mismatch:** `XN(interval)` returns milliseconds, but `load()` multiplies by 1000 again, so the effective background timeout is about 270,000 s. The intent was almost certainly about 270 s (0.9 × min(interval, 5 min)). When it fires: `worker.terminate()`, error code 14 `Timeout`. User-initiated runs have no timeout.
- **Unload** (`unload()`): send `request("terminate",{code:0})`. The worker unmounts the React root and calls `process.exit(code)`. If there is no answer within 500 ms, `worker.terminate()`. The worker `exit` event emits `commandExited {code}` and the session-ended event.
- **View commands** stay loaded until the frontend calls `extensionHost.unloadEntryPoint({sessionId})`, which happens when the user pops out of the command or closes it.
- **Menu-bar** (`LNn` service; `B` does the render itself):
  - Runs in the background on its `interval`, minimum 10 s.
  - When the menu opens (`handleMenuWillOpen`) it reloads the command as `userInitiated`.
  - The session is unloaded 5 s after a render completes with `isLoading:false` (`FNn=5e3`), and after the menu closes.
  - A click on an item calls the item's `actionCallbackId` (queued if the command is still loading).
  - Rendering `null` hides the status item.
- **Background interval scheduler** (`wGi`):
  - Commands with `interval` (`^\d+(s|m|h|d)$`, minimum 10 s) run as `launchType:"background"`.
  - Only when the command setting `syncedMeta.intervalEnabled === true`, which is set the first time a user runs it.
  - At most 8 concurrent background runs. Pauses on system sleep and resumes 5 s after wake. Failures back off.
- **Exceptions:**
  - Worker `uncaughtException` / `unhandledRejection` / React ErrorBoundary → notify `commandException` (serialized RayError), then `process.exit(code)`.
  - The backend source-maps the stack in a separate short-lived Worker (`@raycast/source-mapper/index.js`, 10 s timeout) and logs it to `dev.log`.
  - For user-initiated commands it calls `frontend.extensionHost.commandException(...)`, which shows the error screen.
  - Public store extensions also POST a Sentry envelope to `backend.raycast.com/api/v1/exceptions` (dev extensions do not).
- **Error codes** (`Gm`): 0 Unknown, 1 UncaughtException, 2 UnhandledRejection, 3 StdInError, 4 StdOutError, 5 WorkerMessageError, 6 WorkerError, 7 APIRequestError, 8 WorkerRequestError, 9 MethodError, 10 Custom, 11 UnknownCommand, 12 BackgroundRun, 13 MenuBar, 14 Timeout, 15 ErrorBoundary, 16 OAuth, 17 AlreadyTerminated, 18 CaptureException, 19 InvalidAPI, 20 InvalidPackage, 21 InvalidServer, 22 InvalidEntryPointFile, 23 OutOfMemory, 24 OrganizationExtensionPolicy, 25 OAuthUnavailableInBackground.
- **Render-loop guard:** after more than 20 consecutive no-change renders, a console warning appears: "Raycast might arbitrarily decide to terminate the extension".

### 1.5 Worker ⇄ backend message envelope (postMessage, structured clone) [O]

```jsonc
{ "kind": "request", "id": "<nanoid21>", "method": "showToast", "params": {...} }   // worker->host or host->worker
{ "kind": "result",  "id": "<same>", "result": { "success": true,  "value": ... } }
{ "kind": "result",  "id": "<same>", "result": { "success": false, "error": {RayError} } }
{ "kind": "notify",  "method": "logCommand", "params": {...} }                       // no reply
{ "kind": "child-process", "event": { "type":"spawned","pid":123,"executable":"/bin/sh" } }
```

- Host→worker methods (`addMethod`): **`initialize`**, **`nativeCallback`**, **`terminate`**.
- The backend validates every worker request with a zod table (`Wjn` for requests, `Gjn` for notifies). Invalid params give `"Invalid parameters for method X"`. Strings have lone surrogates and NULs stripped.
- In a clone you can keep exactly this envelope. To isolate extensions better on Linux you could put it over a child-process IPC channel. The API bundle only uses `require("worker_threads").parentPort` and `workerData`, so you would shim `worker_threads` in a child process if you wanted real process isolation.

---

## 2. The reconciler and the render tree

### 2.1 Reconciler [O]

- Built with `react-reconciler` 0.31 in **persistence mode** (`supportsPersistence:true`, `supportsMutation:false`, `cloneInstance`, `createContainerChildSet`, `finalizeContainerChildren`).
- `createInstance(type, props)` returns `{...propsWithoutChildren, name: type, childElements: [], propElementsFromChildren: {}}`. Text instances are not supported.
- `appendInitialChild` (`EX`) routes children per parent type: a section, an item, an `actionPanel` slot, a `detail` slot, `emptyView`, `searchBarAccessory`, `metadata`, and so on. Loose items are auto-wrapped in implicit sections with id `__raycast_implicit_section_<n>`.
- On every commit, `finalizeContainerChildren` → `onPromoteTree(root)` → `requestNativeMount` (`Zs`), which:
  1. Clears the callback table `nodeCallbacks`.
  2. Converts the host-instance tree into the **view model** (`rootViewNode`, `cu`).
  3. Diffs it against the previous model (`PF`) to get the change flags `{actionPanel, gridSections, listSections}`.
  4. If nothing changed, sends `renderEmpty {}`. If the tree is suspended (`Suspense` fallback or no children), sends `renderSuspense {}` and sets `navigationStack.body.isLoading = true`. Otherwise it sends `render`.
  5. `render` params: `{renderTree: <string>, gzipped: <bool>}`. `renderTree = JSON.stringify({model, changes})`. If it is over 30,000 bytes and gzip+base64 saves at least 20%, it is sent gzipped+base64.

Root component structure:
`StrictMode > "ray-root" > ErrorBoundary > Suspense(fallback "ray-top-level-suspense") > NavigationRoot("ray-navigation-stack") > NavigationView > <Command/>`

The navigation stack keeps `routes: [{node, onPop}]`. Only the **top** route is serialized (`childElements[last]`). `push`/`pop` update `navigationInfo {action: "new"|"push"|"pop"|"localPop"|"idle", id}`.

### 2.2 Host component (JSX intrinsic) names [O]

`ray-root`, `ray-navigation-stack`, `ray-top-level-suspense`, `ray-list`, `ray-list-section`, `ray-list-item`, `ray-list-item-detail`, `ray-grid`, `ray-grid-section`, `ray-grid-item`, `ray-empty-view`, `ray-detail`, `ray-metadata`, `ray-metadata-label`, `ray-metadata-link`, `ray-metadata-separator`, `ray-metadata-taglist`, `ray-metadata-taglist-item`, `ray-form`, `ray-form-textfield`, `ray-form-passwordfield`, `ray-form-textarea`, `ray-form-checkbox`, `ray-form-datepicker`, `ray-form-dropdown`, `ray-form-tagpicker`, `ray-form-tagpicker-item`, `ray-form-separator`, `ray-form-description`, `ray-form-filepicker`, `ray-search-bar-dropdown`, `ray-search-bar-linkaccessory`, `ray-action-panel`, `ray-menu-section`, `ray-menu-item`, `ray-submenu-item`, `ray-menu-bar-extra`, `ray-menu-bar-extra-item`, `ray-menu-bar-extra-section`, `ray-menu-bar-extra-separator`, `ray-menu-bar-extra-submenu`, `ray-widget` (disabled).

Public component → host node mapping:

| Public API | Host node | Notes |
|---|---|---|
| `List` (`EmptyView`, `Section`, `Item`, `Item.Detail`, `Dropdown`, `Dropdown.Section/Item`) | ray-list, ray-empty-view, ray-list-section, ray-list-item, ray-list-item-detail, ray-search-bar-dropdown, ray-menu-section, ray-menu-item | Dropdown.Item → `ray-menu-item {id: value}`. Dropdown id defaults to `"default_dropdown_id"`. |
| `Grid` (+ `Section`, `Item`, `EmptyView`, `Dropdown`, enums `Grid.ItemSize` small/medium/large, `Grid.Inset` zero/sm/md/lg, `Grid.Fit` contain/fill) | ray-grid… | `columns` is clamped to 1..8 |
| `Detail` (+ `Detail.Metadata` .Label/.Link/.Separator/.TagList/.TagList.Item) | ray-detail, ray-metadata… | |
| `Form` + `TextField`, `PasswordField`, `TextArea`, `Checkbox`, `DatePicker` (`Type` date/date_time, `isFullDay`), `Dropdown` (+Section/Item), `TagPicker` (+Item), `FilePicker`, `Separator`, `Description`, `LinkAccessory` | ray-form-* | Fields are `forwardRef` with `ref.focus()` → `formSetFocus {itemId}` and `ref.reset()` → `formReset {itemId}` |
| `ActionPanel` (+`Section`, `Submenu`, `Item`=Action) | ray-action-panel, ray-menu-section, ray-submenu-item | |
| `Action` + `CopyToClipboard`, `CreateQuicklink`, `CreateSnippet`, `InstallMCPServer`, `Open`, `OpenInBrowser`, `OpenWith`, `Paste`, `Push`, `ShowInFinder`, `SubmitForm`, `Trash`, `ToggleQuickLook`, `PickDate`; `Action.Style` regular/destructive | all are `ray-menu-item` (OpenWith is a `ray-submenu-item`) | The variants are plain JS wrappers around `Action` that call APIs inside `onAction`. See 3.3. |
| `MenuBarExtra` (+`Item` incl. `alternate`, `Section`, `Separator`, `Submenu`) | ray-menu-bar-extra… | |

Selection semantics:
- `List.Item` and `Grid.Item` render their `actions` and `detail` children **only when they are the selected item** (`useIsSelectedItem`). Before any selection, that is the first item rendered.
- `List`/`Grid` `actions` are used only when no item is selected.
- The serializer **hoists** the single resulting `ray-action-panel` to `commandView.actions` and the item detail to `List.detail`.
- Therefore the host must send `onSelectionChange` so the worker re-renders the actions of the newly selected item.

Ids:
- Every host node that can carry callbacks needs an `id`: the user-supplied id, or `useId()` = 21-char nanoid using alphabet `useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict`.
- Form fields use the user's required `id`. `Dropdown.Item` / `TagPicker.Item` use `value`.

### 2.3 Callback references [O]

- Function props become **strings** during serialization: `callbackId = "<node.id>_<propName>"`, for example `"Xo8…k_onAction"`, `"navigationStack_onPop"`, `"<listId>_onSearchTextChange"`, `"<listId>_onSelectionChange"`, `"<listId>_onLoadMoreItems"`, `"<itemId>_onSelect"`, `"<fieldId>_onChange|onBlur|onFocus|onCreate"`. The id→function map is rebuilt on every render.
- Non-tree callbacks live in a second map (`apiCallbacks`):
  - `toast_<id>_onHide`, `toast_<id>_onPrimaryAction`, `toast_<id>_onSecondaryAction`
  - `alert_<id>_onPrimaryAction`, `alert_<id>_onDismissAction`
  - `oAuth_onRedirect_<codeChallenge>`
  - `ai_answer_<nanoid>` (AI stream)
  - `menu_bar_extra_item_<sha256 hash chain>_action`
- **Invocation:**
  1. The frontend calls `backend.extensionHost.callNodeCallback({sessionId, callbackId, data})`.
  2. The backend sends worker `request("nativeCallback", {sessionId, callbackId, data})`.
  3. The worker looks the callback up and runs it inside `reconciler.batchedUpdates`.
  4. The worker replies `{data: JSON.stringify(returnValue)}`. An unknown id still replies `{data: undefined}`.

Callback payloads (from frontend code, `mw.js` ~15142–15906) [O]:

| Callback | `data` sent |
|---|---|
| `onAction` (normal action, item `onAction`, metadata tag) | none (`undefined`) |
| `onAction` of `type:"submit-form"` | `{ "<fieldId>": {"type":"textField"\|"textArea"\|"default", "value": ...}, "<dateId>": {"type":"date","value":"<ISO>"} }`. The API unwraps this to `{id: value}` with Date objects. If the handler returns `false`, the worker sends `shakeMainRaycastWindow`. |
| `onAction` of `type:"date-picker"\|"date-time-picker"` (Action.PickDate) | date (string → `Date`) |
| `onSearchTextChange`, dropdown `onChange`, field `onChange`, `onSelectionChange` | `{ "value": <string\|bool\|string[]\|ISO>, "eventCount": <int> }`. `eventCount` is a monotonically increasing counter used to reconcile controlled values. Throttled to 250 ms when `throttlingEnabled`. |
| `onBlur` / `onFocus` | value. The API turns it into `{target:{id, value}, type:"blur"\|"focus"}`. |
| `onSelect` (submenu / item) | none |
| submenu `onAction` (= `onOpen`) | none. Submenu `onSearchTextChange` gets `{value, eventCount:0}`. |
| `onLoadMoreItems` | none |
| `navigationStack_onPop` | id |

Controlled values are serialized as `{value, eventCount}` objects (schema `RN = {value: any|null, eventCount: number}`). This applies to `searchBarText`, `selectedItemId`, and field `value`/`defaultValue`. The host must echo the latest `eventCount` back so it knows whether its local edit is newer than the model.

### 2.4 Render tree schema (backend zod, `backend.mjs` ~66344–66368, verbatim field names) [O]

```text
RenderPayload = { model: CommandView, changes: { actionPanel: bool, gridSections: bool, listSections: bool } }
CommandView   = { kind:"commandView", navigationStack: NavStack, actions?: ActionMenu, onStatusChange?: string }
NavStack      = { kind:"navigationStack", id:"navigationStack", body: List|Grid|Form|Detail (|MenuBarExtra),
                  navigationInfo:{ action:"new"|"push"|"pop"|"localPop"|"idle", id?: string }, onPop?: cbId }
ActionMenu    = { id?, title?, sections:[ { id, title?, items:[ ActionItem ] } ] }
ActionItem    = { id, title, icon?: Image, shortcut?: Shortcut, keywords?: string[], min?: ISO, max?: ISO,
                  autoFocus?: bool, type?: "action"|"submit-form"|"date-picker"|"date-time-picker",
                  style?: "regular"|"destructive", onAction?: cbId,
                  submenu?: ActionMenu, + SearchBarBase }          // submenus: onAction = onOpen
SearchBarBase = { searchBarText?: Controlled, searchBarPlaceholder?, keepSectionOrder?, onSearchTextChange?: cbId,
                  throttlingEnabled?, isLoading?, filteringEnabled? }
Pagination    = { itemsPerPage?: number, hasMoreItems?: bool, onLoadMoreItems?: cbId }
Dropdown(searchBarAccessory) = { kind:"Dropdown", id, tooltip, placeholder?, storeValue?, value?:Controlled,
                  defaultValue?:Controlled, onChange?, menu:{ id?, sections:[{id,title?,items:[{id,title,icon?,keywords?}]}] }, +SearchBarBase }
List   = { kind:"List", id, navigationTitle?, isLoading, isShowingDetail, selectedItemId?: Controlled,
           onSelectionChange?, searchBarAccessory?: Dropdown, emptyView?: EmptyView, detail?: ListDetail,
           sections:[ { kind:"Section", id, title?, subtitle?, items:[ ListItem ] } ], +SearchBarBase, +Pagination }
ListItem = { kind:"Item", id, title, titleTooltip?, subtitle?, subtitleTooltip?, icon?: Image, iconTooltip?,
             keywords?, quickLook?:{name?,path?}, onSelect?,
             accessories?:[ { kind:"Accessory", text?, date?: epochMs, tag?: string|epochMs, icon?: Image,
                              color?: Color, tooltip? } ] }
ListDetail = { kind:"Detail", id?, markdown?, isLoading?, metadata?: Metadata }
EmptyView  = { kind:"EmptyView", id, icon?, title?, description? }
Grid   = { kind:"Grid", id, columns?(1-8), itemSize?:"small"|"medium"|"large", fit?:"contain"|"fill",
           aspectRatio?:"1"|"3/2"|"2/3"|"4/3"|"3/4"|"16/9"|"9/16", inset?:"zero"|"sm"|"md"|"lg",
           navigationTitle?, isLoading, selectedItemId?, onSelectionChange?, searchBarAccessory?, emptyView?,
           sections:[ { kind:"Section", id, title?, subtitle?, columns?, fit?, aspectRatio?, inset?, items:[GridItem] } ],
           +SearchBarBase, +Pagination }
GridItem = { kind:"Item", id, title?, subtitle?, keywords?, quickLook?, content?: Image, color?: Color (instead of content),
             contentTooltip?, accessory?:{ kind:"Accessory", icon: Image, tooltip? }, onSelect? }
Detail = { kind:"Detail", navigationTitle?, isLoading, markdown, metadata?: Metadata }
Metadata = { kind:"Metadata", items:[ {kind:"Label",id,title,text?,textColor?,icon?} | {kind:"Separator",id}
             | {kind:"Link",id,title,text?,target:url} | {kind:"TagList",id,title,items:[{kind:"Item",id,text?,icon?,color?,onAction?}]} ] }
Form = { kind:"Form", navigationTitle?, isLoading, enableDrafts, searchBarAccessory?:{kind:"LinkAccessory",target,text},
         items:[ FormItem ] }
FormItem common = { id, title?, info?, error?, storeValue: bool, autoFocus: bool, value?:Controlled, defaultValue?:Controlled,
                    onChange?, onBlur?, onFocus? }
  TextField  {kind:"TextField", placeholder?, isSecure: bool}       // PasswordField = TextField with isSecure:true
  TextArea   {kind:"TextArea", placeholder?, enableMarkdown: bool}
  Checkbox   {kind:"Checkbox", checkboxTitle (= label)}
  DatePicker {kind:"DatePicker", type?:"date"|"date_time", min?:ISO, max?:ISO}   // value.value is ISO string
  Dropdown   {kind:"Dropdown", placeholder?, menu:{id,sections:[...]}, +SearchBarBase}
  TagPicker  {kind:"TagPicker", placeholder?, suggestionValues:[{title,value,icon?}], onCreate?}
  FilePicker {kind:"FilePicker", canChooseFiles, canChooseDirectories, showHiddenFiles, allowMultipleSelection}
  Separator  {kind:"Separator", id}
  Description{kind:"Description", id, title?, text}
MenuBarExtra = { kind:"MenuBarExtra", id, title?, icon?, tooltip?, isLoading?,
   items:[ {kind:"Item", hash, title, subtitle?, icon?, tooltip?, shortcut?, actionCallbackId?, alternate?: Item}
         | {kind:"Separator"} | {kind:"Submenu", hash, title, icon?, items} | {kind:"Section", hash, title?, items} ] }
Image = { source?: ImageSource, fallback?: ImageSource, mask?:"circle"|"roundedRectangle", tintColor?: Color }
        | { source: { fileIcon: "<path>" } }
ImageSource = Icon token ("bird-16") | url | path-or-asset-name string | { light, dark }
Color = "raycast-blue"|"raycast-green"|"raycast-magenta"|"raycast-orange"|"raycast-purple"|"raycast-red"|"raycast-yellow"
        |"raycast-primary-text"|"raycast-secondary-text" | "#hex"/css string | { light, dark, adjustContrast? }
Shortcut = {modifiers:("cmd"|"ctrl"|"opt"|"alt"|"shift"|"windows")[], key} | {macOS:{…}, Windows:{…}} (also lowercase "windows")
Controlled = { value: any|null, eventCount: number }
```

Notes:
- In the worker, `Je()` wraps a bare string, a `{fileIcon}`, or a `{light,dark}` into `{source: …}`. Every `icon` in the tree is therefore an object.
- List accessory `text`/`date` colors are only kept if they are one of the 9 named Raycast colors. Tag colors accept any value.
- Asset-relative image paths resolve against `<buildDir>/assets/…` [O `backend.mjs:140829`, frontend uses `extensionPath`].

### 2.5 Concrete example [O-derived]

Command:

```tsx
<List searchBarPlaceholder="Search" onSearchTextChange={setQ} throttle>
  <List.Item id="a" title="Alpha" icon={Icon.Bird} accessories={[{text:"x"}]}
    actions={<ActionPanel><Action.CopyToClipboard content="Alpha"/></ActionPanel>}/>
</List>
```

`render` params:

```jsonc
{ "renderTree": "{\"model\":{...},\"changes\":{...}}", "gzipped": false }
```

Decoded:

```json
{
 "model": {
  "kind": "commandView",
  "navigationStack": {
   "kind": "navigationStack", "id": "navigationStack",
   "navigationInfo": { "action": "new", "id": "" },
   "onPop": "navigationStack_onPop",
   "body": {
    "id": "V1StGXR8_Z5jdHi6B-myT", "kind": "List", "isLoading": false, "isShowingDetail": false,
    "searchBarPlaceholder": "Search", "throttlingEnabled": true,
    "onSearchTextChange": "V1StGXR8_Z5jdHi6B-myT_onSearchTextChange",
    "sections": [ { "kind": "Section", "id": "__raycast_implicit_section_0",
      "items": [ { "kind": "Item", "id": "a", "title": "Alpha",
                   "icon": { "source": "bird-16" },
                   "accessories": [ { "kind": "Accessory", "text": "x" } ] } ] } ]
   }
  },
  "actions": {
   "sections": [ { "id": "__raycast_implicit_section_0",
     "items": [ { "id": "q8Bc…", "title": "Copy to Clipboard", "icon": { "source": "copy-clipboard-16" },
                  "onAction": "q8Bc…_onAction" } ] } ]
  }
 },
 "changes": { "actionPanel": true, "gridSections": true, "listSections": true }
}
```

The user presses Enter. The frontend sends:

```json
{ "sessionId": "…", "callbackId": "q8Bc…_onAction" }
```

The worker runs Clipboard.copy → `setClipboard`, then `closeMainRaycastWindow`, then `showHUD {"title":"Copied to Clipboard",...}`, and replies `{"data": undefined}`.

The user types "al". The frontend sends:

```json
{ "callbackId": "V1St…_onSearchTextChange", "data": { "value": "al", "eventCount": 1 } }
```

That triggers a new `render`, or `renderEmpty` if nothing changed.

Frontend keyboard conventions [O, `xK`]:
- The first action gets Enter.
- If the first action is `submit-form`, it gets ⌘Enter instead.
- The second action gets ⌘Enter, or the tertiary shortcut if the first was submit-form.
- Reserved shortcuts are stripped by the API: ⌘W, Delete, ⌘K, ⌘,, ⌘P, ⇧⌘/, Enter, ⌘Q, ⌘Esc, ⌘Enter, ⌘A, Esc, ⌥Delete, ⌘Delete, DeleteForward.

---

## 3. `@raycast/api` surface (as shipped) and the RPC each call sends

### 3.1 Exports [O] (module.exports at end of `index.js`)

`AI, Action, ActionPanel, ActionPanelItem, ActionPanelSection, ActionPanelSubmenu, Alert, AlertActionStyle, BrowserExtension, Cache, Clipboard, Color, CopyToClipboardAction, Detail, Form, FormCheckbox, FormDatePicker, FormDropdown, FormDropdownItem, FormDropdownSection, FormSeparator, FormTagPicker, FormTagPickerItem, FormTextArea, FormTextField, Grid, Icon, Image, ImageMask, Keyboard, LaunchType, List, ListItem, ListSection, LocalStorage, MenuBarExtra, Notes, OAuth, OpenAction, OpenInBrowserAction, OpenWithAction, PasteAction, PopToRootType, PushAction, ShowInFinderAction, SubmitFormAction, Toast, ToastStyle, TrashAction, WindowManagement, allLocalStorageItems, captureException, captureMemorySnapshot, clearClipboard, clearLocalStorage, clearSearchBar, closeMainWindow, confirmAlert, copyTextToClipboard, environment, getApplications, getDefaultApplication, getFrontmostApplication, getLocalStorageItem, getPreferenceValues, getSelectedFinderItems, getSelectedText, launchCommand, open, openCommandPreferences, openExtensionPreferences, pasteText, popToRoot, preferences, randomId, removeLocalStorageItem, render, setLocalStorageItem, showHUD, showInFinder, showToast, specialKeys, trash, unstable_AI, updateCommandMetadata, useActionPanel, useId, useNavigation, useUnstableAI`

The deprecated aliases in that list (`CopyToClipboardAction`, `FormTextField`, `allLocalStorageItems`, `copyTextToClipboard`, `pasteText`, `preferences`, `render`, `useActionPanel`, `randomId`, `specialKeys`, …) are still present and map to the new APIs.

### 3.2 Function → worker RPC method and params [O]

Wire params are the zod `Wjn` schema in the backend. All are `request` kind unless noted.

| API | method | params → returns |
|---|---|---|
| `showToast(opts)` / `new Toast().show()` | `showToast` | `{title, message?, style:"SUCCESS"\|"FAILURE"\|"ANIMATED", onHide:"toast_<id>_onHide", primaryAction?:{title, shortcut?, onAction:"toast_<id>_onPrimaryAction"}, secondaryAction?:{…}}` → void. Default style is Success. |
| toast setters (`title`/`message`/`style`/actions) | `updateToast` | same shape |
| `toast.hide()` | `hideToast` | `{}` |
| `showHUD(title, {clearRootSearch, popToRootType})` | `showHUD` | `{title, clearRootSearch:false, popToRootType:"default"\|"immediate"\|"suspended"}` |
| `confirmAlert(opts)` / Alert | `showAlert` | `{title, message?, icon?: JSON-string Image, primaryAction?:{title, style?:"default"\|"cancel"\|"destructive", onAction:"alert_<id>_onPrimaryAction"}, dismissAction?:{…"alert_<id>_onDismissAction"}}`. Resolves true/false when the callback fires. Defaults: "Confirm" / "Cancel". |
| `closeMainWindow({clearRootSearch, popToRootType})` | `closeMainRaycastWindow` | `{clearRootSearch:false, popToRootType:"default"}` |
| `popToRoot({clearSearchBar})` | `popToRoot` | `{clearSearchBar:true}` |
| `clearSearchBar({forceScrollToTop})` | `clearSearchBar` | `{forceScrollToTop:true}` |
| `openExtensionPreferences()` / `openCommandPreferences()` | same names | `{}` |
| `open(target, app?)` | `open` | `{path:target, app?: string}`. `app` is the string, or `raycastAppId`/`windowsAppId`/`path`/`localizedName`/`bundleId` of an Application. The backend closes the main window first, then `host.fileSystem.openFile`. |
| `showInFinder(path)` | `showInFinder` | `{path}` (tilde-expanded, realpath) |
| `trash(paths)` | `trashItems` | `{paths:[…]}` → `{trashed, notTrashed}`. Throws if any were not trashed. |
| `getApplications(path?)` | `getApplications` | `{path:"" \| realpath \| "__raycast_remote_url__"}` → `{value: Application[]}` |
| `getDefaultApplication(path)` | `getDefaultApplication` | `{path}` → `{value: Application}` |
| `getFrontmostApplication()` | `getFrontmostApplication` | `{}` → `{value: Application}` |
| Application shape | — | `{name, localizedName?, path, raycastAppId, bundleId?, windowsAppId?}` |
| `getSelectedText()` | `getSelectedText` | `{}` → `{text}` |
| `getSelectedFinderItems()` | `getSelectedFinderItems` | `{}` → `{items:[{path}]}` |
| `updateCommandMetadata({subtitle})` | `updateCommandMetadata` | `{subtitle: string\|null}`. Commands only. |
| `launchCommand({name,type,arguments,context,fallbackText,extensionName?,ownerOrAuthorName?})` | `launchCommand` | `{ownerOrAuthorName?, extensionName?, name, type:"userInitiated"\|"background", arguments?, context: JSON-string(with date/buffer replacer)\|null, fallbackText?}` |
| `Clipboard.copy(content,{concealed,transient})` | `setClipboard` | `{contents: {text}\|{html,text?}\|{file:path}, concealed:bool}`. A string or number becomes `{text}`. Buffers are rejected. |
| `Clipboard.paste(content)` | `paste` | `{contents}` |
| `Clipboard.clear()` | `clearClipboard` | `{}` |
| `Clipboard.read({offset})` / `readText` | `getClipboard` | `{offset:0..5}` → `{text, html?, file?}`. The offset reads Raycast's clipboard **history** DB, not just the system pasteboard. |
| `LocalStorage.getItem/setItem/removeItem/allItems/clear` | `getLocalStorageItem {key}`→`{value\|null}`, `setLocalStorageItem {key,value: string\|number\|bool}`, `removeLocalStorageItem {key}`, `allLocalStorageItems {}`→`{values}`, `clearLocalStorage {}` | The backend stores these as the per-extension `localStorage` object inside node extension settings (encrypted settings DB), with writes serialized per extension. |
| `Cache` | **no RPC** | Pure fs in the worker. See 3.4. |
| `getPreferenceValues()` | **no RPC** | Built from `initialize.preferences`: `{name: pref.value ?? pref.default}`. `preferences` (deprecated) is the raw map. |
| `environment` | **no RPC** | `{raycastVersion (env RAYCAST_VERSION), isDevelopment, appearance, theme, textSize, ownerOrAuthorName, extensionName, commandName/entryPointName, commandMode/entryPointMode, entryPointType, assetsPath, supportPath, launchType, launchContext, canAccess(api)}`. `canAccess(AI)` = workerData.canAccessAI; `BrowserExtension` = isBrowserExtensionInstalled; `WindowManagement` = canAccessWindowManagement (Pro); everything else true. |
| `OAuth.PKCEClient` (`redirectMethod` web/app/appURI/clientIdMetadataDocument, `providerName`, `providerIcon`, `providerId`="default", `description`) | `initOAuth {flow:"PKCE", redirectMethod, onRedirect:"oAuth_onRedirect_<challenge>", providerIcon?, providerName, description?}` → `{state, redirectURI}`; `authorizeOAuth {url}`; `setOAuthTokens {tokenSet:{accessToken, providerId, providerName, refreshToken?, idToken?, expiresIn?, scope?, updatedAt}}`; `getOAuthTokens {providerId}` → `{tokenSet?}`; `removeOAuthTokens {providerId}` | PKCE verifier/challenge are computed in the worker (S256, base64url of 32 random bytes). The auth URL is built in the worker (client_id, redirect_uri, response_type=code, scope, code_challenge, S256, state + extras). The redirect arrives as nativeCallback `{authorizationCode}`. Tokens are stored per extension in settings `oauthTokens[providerId]`. `clientIdMetadataDocument` default = `https://www.raycast.com/.well-known/oauth-client-metadata/raycast.json`. Not available in background launches. |
| `BrowserExtension.getContent({format,cssSelector,tabId})` | `browserExtensionGetContent` | → `{value}` (default format html) |
| `BrowserExtension.getTabs()` | `browserExtensionGetTabs` | → `{value:[{tabId,title?,url?,favicon?,active}]}`, mapped to `{id,…}` |
| `BrowserExtension.executeJavaScript(script,{tabId})` (undocumented) | `browserExtensionExecuteJS` | `{script, tabId?}` → `{value?}` |
| `WindowManagement.getActiveWindow()` | `getActiveWindow` | → `{window:{id, application?, bounds:{position:{x,y},size:{width,height}}\|"fullscreen", desktopId, fullScreenSettable, resizable, positionable, active}}` |
| `WindowManagement.getWindowsOnActiveDesktop()` | `getWindowsOnActiveDesktop` | → `{windows:[…]}` |
| `WindowManagement.getDesktops()` | `getDesktops` | → `{desktops:[{id, screenId, size:{width,height}, active, type:"User"\|"FullScreen"}]}` |
| `WindowManagement.setWindowBounds({id, bounds, desktopId?})` | `setWindowBounds` | bounds: `{position?:{x?,y?}, size?:{width?,height?}}` \| `"fullscreen"` |
| `AI.ask(prompt,{creativity,model,signal})` | `completePrompt` | `{streamCallbackId:"ai_answer_<id>", prompt, temperature: none 0/low .5/medium 1/high 1.5/maximum 2 or number, model?}`. Chunks come back as nativeCallback `{value}`. Returns a Promise plus an EventEmitter "data". AI is out of scope, noted only. |
| `AI.experimental_decide`, `AI.refreshModels` | `aiDecide`, `refreshModels` | AI. Noted only. |
| `Notes.search/create`, `Note#getContent/updateContent/delete/open` | `searchRaycastNotes {query,page}`, `createRaycastNote {content,format}`, `readRaycastNote {noteId,format}`, `updateRaycastNote`, `deleteRaycastNote`, `openRaycastNote` | In this build the backend stubs most of these: read returns "To be implemented", search returns empty, update throws "Not implemented". |
| `captureException(e)` | notify `captureException` | serialized RayError (code 18) |
| `captureMemorySnapshot(label)` | notify `reportMemoryUsage` | `{label, timestamp, heapSizeLimit, totalHeapSize, totalAvailableSize, usedHeapSize}` (only if `enableMemoryReporting`) |
| `console.*` | notify `logCommand` | `{sessionId, level:"debug"\|"info"\|"warn"\|"error", message}` |
| unhandled errors | notify `commandException` | `{_isRayError, code, title, name, message, stack, reactComponentStack?, reactOwnerStack?, breadcrumbs?, diagnostics?, sessionId}` |
| Form `ref.focus()` / `ref.reset()` | `formSetFocus {itemId}` / `formReset {itemId}` | |
| `Action.SubmitForm` returning false | `shakeMainRaycastWindow {}` | |
| `Action.ToggleQuickLook` (needs `quickLook` on item) | `toggleQuickLook {path, name?}` | |
| `Action.CreateQuicklink` | `createQuicklink {link, name?, application?, iconName?}` | |
| `Action.CreateSnippet` | `createSnippet {snippet, name?, keyword?}` | |
| `Action.InstallMCPServer` | `installMCPServer {name, transport:"stdio"\|"sse", command?, args?, url?, additionalConfiguration?, iconName?, description?}` | |
| view rendering | `render {renderTree, gzipped}`, `renderEmpty {}`, `renderSuspense {}` | |
| `useNavigation()` | **no RPC** | `{push(el, onPop), pop()}` changes the React route stack, which produces a new render with `navigationInfo`. |
| `Keyboard` | constants | `Keyboard.Shortcut.Common` (Copy ⌘⇧C, CopyDeeplink ⌘⇧C, CopyName ⌘⌥C, CopyPath ⌘⌃C, Save ⌘S, Duplicate ⌘D, Edit ⌘E, MoveDown ⌘⌥↓, MoveUp ⌘⌥↑, New ⌘N, Open ⌘O, OpenWith ⌘⇧O, Pin ⌘., Refresh ⌘R, Remove ⌃X, RemoveAll ⌃⇧X, ToggleQuickLook ⌘Y; each also has a `Windows` variant), `Keyboard.Shortcut.Reserved`, `DeprecatedKeys` |
| `Color` | enum | Blue, Green, Magenta, Orange, Purple, Red, Yellow, PrimaryText, SecondaryText → `raycast-*`. `Brown = {light:"#714426", dark:"#9F6138"}`. |
| `Image.Mask` | enum | Circle "circle", RoundedRectangle "roundedRectangle" |
| `Toast.Style` | enum | Success "SUCCESS", Failure "FAILURE", Animated "ANIMATED" |
| `Alert.ActionStyle` | enum | Default "default", Cancel "cancel", Destructive "destructive" |
| `LaunchType` | enum | UserInitiated "userInitiated", Background "background" |
| `PopToRootType` | enum | Default "default", Immediate "immediate", Suspended "suspended" |
| `Icon` | enum | 478 entries `Name → "<token>-16"`. See the appendix. |

Each request may also record a breadcrumb `{category, data:{function}}`, which is attached to error reports.

### 3.3 What the `Action.*` variants do (pure JS wrappers) [O]

| Variant | Behavior |
|---|---|
| CopyToClipboard | `Clipboard.copy(content,{transient,concealed})`, `onCopy`, `closeMainWindow()`, `showHUD("Copied to Clipboard")`. Default icon `copy-clipboard-16`. |
| Paste | `Clipboard.paste`, `onPaste`, `closeMainWindow()` |
| Open | `open(target, application)`. Shows a failure toast on error. Default icon `finder-16`. |
| OpenInBrowser | `Open`, title "Open in Browser", icon `globe-01-16` |
| OpenWith | Submenu populated by `getApplications(path)`. Items use icon `{fileIcon: app.raycastAppId}`. |
| ShowInFinder | `showInFinder(path)`, `closeMainWindow()` |
| Trash | Confirm alert, then `trash()`, with an animated, then success or failure toast |
| Push | `useNavigation().push(target, onPop)` then `onPush` |
| SubmitForm | `type:"submit-form"` |
| PickDate | `type:"date-picker"\|"date-time-picker"`. "Full day" is encoded as milliseconds === 1. |
| ToggleQuickLook | Hidden unless the selected item has `quickLook`. Default shortcut ⌘Y. |
| CreateQuicklink / CreateSnippet / InstallMCPServer | RPC calls listed in 3.2 |

### 3.4 `Cache` on-disk format (pure worker fs) [O]

- Directory: `<supportPath>/com.raycast.api.cache/<namespace?>/`. On Windows the namespace is sanitized.
- `journal` file: first line `1` (version). Then one line per entry, `<key-with-spaces-as-_> <id> <sizeBytes>`, ordered least→most recently used.
- Values: one file per entry, named `<id>`, containing the UTF-8 string.
- Default capacity is 10,000,000 bytes. LRU eviction.
- API: `get, has, set, remove, clear({notifySubscribers}), subscribe, isEmpty`.

This is portable as is.

---

## 4. Manifest (`package.json`) schema

From the backend zod schemas `Lm`/`Tdt`/`Cdt`/`cdt`, around `backend.mjs:20826–20832` [O].

**Top level:**
- `$schema?`, `name`, `title`, `description`, `icon`, `author` (required)
- `keywords?[]`, `owner?`, `contributors?[]`, `pastContributors?[]`, `categories?[]`, `access?: "public"|"private"`, `license?`
- `commands?[]`, `widgets?[]`, `tools?[]`, `preferences?[]`
- `ai?: {skills?:[{name,title,icon?}], mcp?, instructions?, modelProvider?}`

**Store-install strict variant (`Lm`):**
- `name` matches `^[a-z0-9][\w_\-.]*$` (1–255 chars), `title`, `icon` required.
- Command `name` matches `^[a-z][\w_\-.]*$`.
- Tool `name` is 1–64 chars.
- On install, `name` has any `@workaround/` prefix stripped.

**Command:**
- `name`, `title`, `subtitle?`, `description`, `icon?`, `keywords?[]`
- `mode: "view"|"no-view"|"menu-bar"`
- `preferences?[]`, `arguments?[]` (max 3), `interval?` (e.g. `"90s"`, `"1m"`, `"12h"`, `"1d"`; regex `^\d+(s|m|h|d)$`; minimum 10 s; used for no-view and menu-bar)
- `disabledByDefault?: bool`

**Argument:**
- `{type:"text"|"password"|"dropdown", name (2–255 chars, `^[a-zA-Z0-9-._~]*$`), placeholder (required), required?: bool, data? (dropdown: [{title,value}] min 1)}`
- Values arrive as strings in `LaunchProps.arguments[name]`. Missing ones become `""`.

**Preference** (extension-level or command-level):
- Common fields: `{name, title, description (≥8 chars), required: bool, placeholder?, type}`.
- `type` is one of `"textfield" | "password" | "checkbox" | "dropdown" | "appPicker" | "file" | "directory"`.

| Type | Extra fields | Value delivered to the worker |
|---|---|---|
| checkbox | `label` (required), `title` optional/empty, `default: bool` or `{macOS?:bool, Windows?:bool}` | bool |
| dropdown | `data:[{title, value: string\|number}]` (min 1), `default` | Defaults to the first item's value when unset |
| textfield, password | `default: string` or `{macOS, Windows}` | string |
| appPicker | — | Resolved to an Application object; `"none"` → undefined |
| file, directory | — | Path, tilde-expanded, existence- and kind-validated |

- Per-platform defaults use keys `macOS` / `Windows`. A Linux clone should add `Linux`, or fall back to `macOS`.

**Tool (AI, noted only):**
- `{name, title, description, icon?, keywords?, functionalities?: ("AI attachment provider"|"AI tool")[], mode?: "view"|"no-view"}`
- `ray build` adds `input` (a JSON-schema object generated from the TS type) and `confirmation: bool` (whether a `confirmation` named export exists). Compare `B/api/template/package.json` with `B/api/template/dist/package.json`.

**`ai.mcp`:**
- `{type?:"stdio", command, args?, env?}` or `{type?:"http"|"sse", url, headers?, oauth?: {type:"dynamic"} | {type:"static", clientId, clientSecret?, scopes?}}`

**Other files:**
- The template also emits `dist/plugin.json` with `$schema "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"` (agent plugin metadata).
- Template package scripts: `ray develop`, `ray build`, `ray lint`, `npx @raycast/api@latest publish`.
- The `ray` CLI comes from the npm `@raycast/api` package and is **not shipped** in the app.

**Command identity:**
- `commandId = "c:n:" + extensionId + "::-::" + commandName`.
- Tool ids use a separate prefix (`Tv`).
- `extensionId = bv(owner||author, name)`.

---

## 5. Script Commands [O]

**Settings:** built-in extension `script-commands`, preference `searchDirectories: string[]` (platform storage). Commands: "Search Script Commands", "Create Script Command", "Reload Script Commands".

**Discovery** (`Bcn`, `Kcn`):
- Non-recursive scan of each directory.
- Files are skipped if they are directories, larger than 2 MB, empty, contain `.template.` in the name, or are online-only (iCloud). They must pass an executable check (`lx`).
- Directory scans time out after 5 s. Incomplete scans retry after 2, 5, 10, 30 and 60 s.

**Header parsing:**
- Regex `^(?:#|REM|::|\/{2})\s*@raycast\.(\w+)\s+(.*)` (case-insensitive key). This accepts `#`, `//`, `REM`, `::` comments.
- An optional shebang on line 1 is parsed: `/usr/bin/env [-S] interp args` or `/path/interp args`.

**Keys:**

| Key | Notes |
|---|---|
| `schemaVersion` | Must be 1 |
| `title` | Required |
| `mode` | Required. `fullOutput`/`full-output`, `compact` (default), `silent`, `inline`. `inline` without `refreshTime` becomes `compact`. |
| `packageName` | Default: Title-Cased parent directory name |
| `icon`, `iconDark` | |
| `description`, `author`, `authorURL` | |
| `currentDirectoryPath` | |
| `needsConfirmation` | `"true"`; ignored for inline |
| `refreshTime` | Same `^\d+(s\|m\|h\|d)$` syntax, minimum 10 s; only for inline |
| `argument1..3` | JSON `{type:"text"\|"password"\|"dropdown", placeholder, optional, secure, percentEncoded, data}`. Ignored for inline. |

**Execution** (`RGi` / `zGi` in the backend):
- `spawn(scriptPath, args, {cwd: resolve(dirname(script), currentDirectoryPath||"."), env, stdio:["ignore","pipe","pipe"]})`. The file is executed directly; the shebang is metadata only on macOS.
- `env` = user login env with `PATH` prefixed by `/usr/local/bin:/opt/homebrew/bin`, `LC_ALL` removed, and `LANG` set.
- Arguments are positional `$1..$3`. Required ones are validated. Dropdown values must be in `data`. `percentEncoded` applies `encodeURIComponent`.

**Output handling** (frontend `fU`):

| Mode | Behavior |
|---|---|
| fullOutput | Navigates to `/extension/script-commands/output` (streamed stdout/stderr view) |
| compact | Streams with a "Running script…" toast and Cancel. Then shows a success/failure toast using the **last non-empty line** of output (ANSI stripped). |
| silent | Closes the window, then a HUD with the last line |
| inline | The first line of output becomes the root-search item **subtitle**. Error → `⚠️ Error: …`. Background-refreshed by the same interval scheduler. |

Success means exit code 0. A Windows extension→interpreter table exists (`.bat/.cmd/.ps1/.py/.js/.ts/.rb/.sh/.cs/.go`), but the macOS path executes the file directly.

**Linux:** identical logic works. Execute the file directly (needs `+x` and a shebang), and use `$PATH` from the login shell.

---

## 6. Extension Store and installation [O; endpoints listed, not contacted]

**Clients** (got/ky):
- `ab` = `https://backend.raycast.com/api/v1` (staging `https://backend.rayca.st`; custom `API_CUSTOM_BACKEND_URL`, default `http://localhost:5001`)
- `sb` = `https://backend.raycast.com` (oauth)
- `ob` = `https://x.raycast-releases.com/` (app releases)
- User-Agent `Raycast/<ver> (x-macOS-<arch> <osver>)`. Auth `Authorization: Bearer <access_token>` plus org-policy headers.

**Endpoints:**

| Purpose | Request |
|---|---|
| Browse/search | `GET store_listings?q=&page=&per_page=50&explicit_platform=macOS`; with a query `GET store_listings/search?...` (query may include `category:"<cat>"`); org stores `GET organizations/<org>/extensions[/search]?...&platform=macOS` |
| Detail | `GET extensions/<ownerHandle>/<name>` (readme included) |
| Download | `GET extensions/<ownerHandle>/<name>/download` (streamed **zip**) |
| Update check | `POST store_listings/latest` with `{"filter":{"id":[<uuid>,…]}}`. An update is needed when `updated_at*1000 > installed version date`. `kill_listed_at` → uninstall. `platforms`/`access` are checked; `"Not available on macOS."` skips. |
| First install | `POST extensions/<owner>/<name>/increment_install_count` |
| Mine | `GET me/extensions`, `GET me/contributions` |
| Other | `GET extensions/suggested`; `DELETE extensions/<owner>/<name>` (remove from store) |

**Categories:** AI Extensions, Applications, Communication, Data, Documentation, Design Tools, Developer Tools, Finance, Fun, Media, News, Productivity, Security, System, Web, Other.

**Install pipeline** (`Eaa`):
1. Download to `$TMPDIR/<uuid>-<rand>.zip`.
2. Extract with adm-zip. Safety checks: no duplicate destinations, path-traversal checks, size and entry-count limits.
3. Locate `package.json` at the root or one directory down.
4. Copy to the staging dir `~/.config/raycast/extensions/.<uuid>-<rand>.staging`.
5. Parse the manifest (strict `Lm`, de-duplicating entry points).
6. Compute a per-entry-file digest `{version:2, hash, mtime}`.
7. Render icon variants (stored under `.raycast/icon-variants`).
8. Back up any existing install to `.<uuid>-<rand>.backup`, then rename staging → `~/.config/raycast/extensions/<uuid>`.
9. Upsert DB rows: extension, commands (`isEnabled = !disabledByDefault`), tools, widgets. The DB is `node_extensions.db`, encrypted.
10. Emit `nodeExtension:installed/updated` and re-warm the worker pool.

Full rollback runs on failure. The installed `version` is the store `updated_at` date.

**The zip** is the `ray build` output: `package.json`, `assets/`, `<cmd>.js`, `tools/*.js`, optional `skills/`.

**Local/dev** (`T4i`/`D4i`):
- `importExtension({path})` registers a built folder. `localSources` = the source path. The extension id comes from `owner||author/name`. The build dir is `~/.config/raycast/extensions/<name>`.
- Dev extensions have no `uuid`, so `isDevelopment` = true unless the developer setting `useNodeProductionEnvironment` is on.
- "Fork extension" clones `source_url` into `~/Development/extensions` by default.
- AI tools `install-local-extension` / `list-local-extensions` / `uninstall-local-extension` exist.
- [I] `ray develop` (npm CLI) builds into `~/.config/raycast/extensions/<name>` and then triggers the import/refresh. The CLI is not in the app bundle, so the exact trigger is not observed here.

**Machine state:** `~/.config/raycast/extensions/` contains only the `node_modules` symlink. No third-party extensions are installed, and `node_extensions.db` is encrypted (not plain SQLite), so I could not inspect a real installed extension.

---

## 7. macOS-specific pieces and Linux substitutes

| API / feature | macOS implementation (host call) | Linux substitute |
|---|---|---|
| `getSelectedText` | `host.applications.getSelectedText` (Accessibility / synthetic ⌘C) | X11: `xclip -o -selection primary` (PRIMARY selection). Wayland: `wl-paste --primary`. Fallback: simulate Ctrl+C via `ydotool`/`wtype`/`xdotool` and read the clipboard. AT-SPI `Text.getSelection` for accessible apps. |
| `getSelectedFinderItems` | `host.fileSystem.getSelectedItems` (Finder AppleScript) | No general equivalent. Nautilus/Dolphin via DBus (`org.freedesktop.FileManager1` has no "get selection"). Use a file-manager plugin or read clipboard `text/uri-list`. Return `[]` or throw as a fallback. |
| `getFrontmostApplication` | `host.applications.getFrontmost` | X11: `_NET_ACTIVE_WINDOW` → `_NET_WM_PID` → `/proc/<pid>/exe` and the .desktop entry. Wayland: compositor-specific (Hyprland `hyprctl activewindow -j`, Sway `swaymsg -t get_tree`, KDE KWin script, GNOME extension). |
| `getApplications(path)`, `getDefaultApplication`, `Action.OpenWith` | LaunchServices | Parse XDG `.desktop` files (`$XDG_DATA_DIRS/applications`). MIME via `xdg-mime query default <mime>` / `gio mime`. `raycastAppId` → desktop-file id. `bundleId` → desktop id. |
| `open(target, app)` | `host.fileSystem.openFile` | `xdg-open` / `gio open`. With an app: `gtk-launch <desktop-id> <target>` or `gio launch`. |
| `showInFinder` | `revealFile` | DBus `org.freedesktop.FileManager1.ShowItems([uri], "")`, fallback `xdg-open dirname` |
| `trash` | `placeInTrash` | `gio trash` / freedesktop Trash spec (`~/.local/share/Trash`) |
| `Clipboard.copy/paste/read/clear` (+ concealed) | NSPasteboard + paste via synthetic ⌘V; history from Raycast DB | `wl-copy`/`wl-paste` or `xclip`/`xsel`, or GTK/Qt clipboard. Paste = put on the clipboard + `ydotool key ctrl+v` / `xdotool key ctrl+v` / `wtype`. `concealed`: set `x-kde-passwordManagerHint=secret` MIME so clipboard managers skip it. `offset` > 0 requires your own clipboard history. |
| `Action.ToggleQuickLook` | QuickLook | GNOME Sushi (`org.gnome.NautilusPreviewer.ShowFile`), or your own preview window |
| `WindowManagement.*` (Pro) | Accessibility (AX) API | X11: EWMH via `wmctrl`/xdotool/libwnck. Wayland: compositor IPC (Hyprland, Sway, KWin scripting). Generally unavailable on GNOME Wayland. `canAccess(WindowManagement)` → false when unsupported. |
| `BrowserExtension.*` | Raycast browser extension bridge (`external.bext`) | Write your own WebExtension + native-messaging host (same `getTabs`/`getContent`/`executeJS` contract) |
| `showHUD` | Native HUD window | Layer-shell overlay or `notify-send`-style transient window |
| `showToast` / `confirmAlert` | Frontend UI | Your UI layer (no OS dependency) |
| `closeMainWindow` / `popToRoot` / `clearSearchBar` / `shakeMainRaycastWindow` | Frontend/main window | Your launcher window |
| MenuBarExtra | NSStatusItem (`host.menuBar.updateItems`) | StatusNotifierItem (`org.kde.StatusNotifierItem`) + DBusMenu (`com.canonical.dbusmenu`). Supported by KDE, waybar, etc.; GNOME needs the AppIndicator extension. `alternate` (⌥-click item) has no direct equivalent: use a submenu or a modifier-aware DBusMenu. |
| OAuth redirect | `raycast://oauth` custom scheme / `https://raycast.com/redirect?packageName=…` relay | Register an `x-scheme-handler/raycast` .desktop MimeType handler. The `web` method relies on Raycast's https redirect page, which bounces to `raycast://`. |
| `getPreferenceValues` appPicker/file/directory | NSOpenPanel / LaunchServices | GTK FileChooser/portal (`org.freedesktop.portal.FileChooser`). appPicker from the .desktop list. |
| Form.FilePicker | NSOpenPanel | xdg-desktop-portal FileChooser |
| Keyboard shortcuts | "cmd" modifier | Map `cmd`→Ctrl (or Super). Raycast already ships `Windows` variants using ctrl/alt, so prefer `shortcut.Windows ?? shortcut.windows` on Linux, else translate `macOS` (cmd→ctrl, opt→alt). |
| `environment.appearance/theme` | System appearance | `org.freedesktop.appearance color-scheme` via the settings portal |
| Proxy / system CAs | `macos_export_certificate_and_key.node`, system keychain CAs | `/etc/ssl/certs/ca-certificates.crt` (Arch `ca-certificates`); env `HTTP(S)_PROXY` |
| Script Commands PATH | Prepends `/usr/local/bin:/opt/homebrew/bin` | Login-shell `PATH` (`$SHELL -lc env`) |
| `canAccess(AI)`, `AI.*`, Notes, quicklinks/snippets/MCP actions | Raycast cloud / built-ins | Out of scope. Stub with errors, or route to your own implementations. |

**Fully portable (no OS dependency):** the React reconciler, render-tree protocol, LocalStorage (backend-side store), Cache (fs), preferences, `launchCommand`, the navigation stack, the interval scheduler, and `child_process`/`fetch` usage inside extensions.

**Compatibility caveat:** many store extensions call macOS binaries directly (`osascript`, `open`, `pbcopy`, `defaults`, `mdfind`, `sqlite3` on `~/Library/...`). Those will fail on Linux whatever the API does. An optional shim PATH with `open`→`xdg-open` and `pbcopy`/`pbpaste`→`wl-copy`/`wl-paste` raises the compatibility rate. Also check `platforms` in store listings (`explicit_platform=macOS`); the store exposes `platforms` (macOS/Windows), so you can prefer Windows-compatible extensions as a proxy for "not AppleScript-bound".

---

## 8. Minimal clone checklist (derived)

1. Reuse the shipped `@raycast/api/index.js` unchanged as the worker entry. It only needs the protocol in §1.5. Or reimplement it against §2.4/§3.2.
2. Write a host (Node) that spawns `new Worker(apiIndex, {workerData, env, resourceLimits:{maxOldGenerationSizeMb:100}})`, symlinks `~/.config/raycast/extensions/node_modules`, sends `initialize`, and implements every method in the `Wjn` table (§3.2). Route `render` to the UI and UI events to `nativeCallback`.
3. The UI decodes `renderTree` (gunzip base64 if `gzipped`) and renders `commandView`. On every user interaction, call callbacks with the payloads in §2.3, and keep `eventCount` bookkeeping for controlled values.
4. Manifest loader and validator per §4. Store client per §6. Script Commands per §5.

---

## Appendix A — Icon enum (`Icon.<Name>` = token sent on the wire, rendered from Raycast's built-in icon set) [O]

The built-in icon artwork itself is in the app/frontend assets. A clone needs an equivalent icon set keyed by these tokens.

```text
AddPerson=add-person-16, Airplane=airplane-16, AirplaneFilled=airplane-filled-16, AirplaneLanding=airplane-landing-16, 
AirplaneTakeoff=airplane-takeoff-16, Airpods=airpods-16, Alarm=alarm-16, AlarmRinging=alarm-ringing-16, 
AlignCentre=align-centre-16, AlignLeft=align-left-16, AlignRight=align-right-16, AmericanFootball=american-football-16, 
Anchor=anchor-16, AppWindow=app-window-16, AppWindowGrid2x2=app-window-grid-2x2-16, AppWindowGrid3x3=app-window-grid-3x3-16, 
AppWindowList=app-window-list-16, AppWindowSidebarLeft=app-window-sidebar-left-16, AppWindowSidebarRight=app-window-sidebar-right-16, ArrowClockwise=arrow-clockwise-16, 
ArrowCounterClockwise=arrow-counter-clockwise-16, ArrowDown=arrow-down-16, ArrowDownCircle=arrow-down-circle-16, ArrowDownCircleFilled=arrow-down-circle-filled-16, 
ArrowLeft=arrow-left-16, ArrowLeftCircle=arrow-left-circle-16, ArrowLeftCircleFilled=arrow-left-circle-filled-16, ArrowNe=arrow-ne-16, 
ArrowRight=arrow-right-16, ArrowRightCircle=arrow-right-circle-16, ArrowRightCircleFilled=arrow-right-circle-filled-16, ArrowUp=arrow-up-16, 
ArrowUpCircle=arrow-up-circle-16, ArrowUpCircleFilled=arrow-up-circle-filled-16, ArrowsContract=arrows-contract-16, ArrowsExpand=arrows-expand-16, 
AtSymbol=at-symbol-16, BandAid=band-aid-16, BankNote=bank-note-16, BarChart=bar-chart-16, 
BarCode=bar-code-16, BathTub=bath-tub-16, Battery=battery-16, BatteryCharging=battery-charging-16, 
BatteryDisabled=battery-disabled-16, Bell=bell-16, BellDisabled=bell-disabled-16, Bike=bike-16, 
Binoculars=binoculars-16, Bird=bird-16, BlankDocument=blank-document-16, Bluetooth=bluetooth-16, 
Boat=boat-16, Bold=bold-16, Bolt=bolt-16, BoltDisabled=bolt-disabled-16, 
Book=book-16, Bookmark=bookmark-16, Box=box-16, Brush=brush-16, 
Bubble=speech-bubble-16, Bug=bug-16, Building=building-16, BulletPoints=bullet-points-16, 
BullsEye=bulls-eye-16, BullsEyeMissed=bulls-eye-missed-16, Buoy=buoy-16, Calculator=calculator-16, 
Calendar=calendar-16, Camera=camera-16, Car=car-16, Cart=cart-16, 
Cd=cd-16, Center=center-16, Check=check-16, CheckCircle=check-circle-16, 
CheckList=check-list-16, CheckRosette=check-rosette-16, Checkmark=checkmark-16, ChessPiece=chess-piece-16, 
ChevronDown=chevron-down-16, ChevronDownSmall=chevron-down-small-16, ChevronLeft=chevron-left-16, ChevronLeftSmall=chevron-left-small-16, 
ChevronRight=chevron-right-16, ChevronRightSmall=chevron-right-small-16, ChevronUp=chevron-up-16, ChevronUpDown=chevron-up-down-16, 
ChevronUpSmall=chevron-up-small-16, Circle=circle-16, CircleDisabled=circle-disabled-16, CircleEllipsis=circle-ellipsis-16, 
CircleFilled=circle-filled-16, CircleProgress=circle-progress-16, CircleProgress100=circle-progress-100-16, CircleProgress25=circle-progress-25-16, 
CircleProgress50=circle-progress-50-16, CircleProgress75=circle-progress-75-16, ClearFormatting=clear-formatting-16, Clipboard=copy-clipboard-16, 
Clock=clock-16, Cloud=cloud-16, CloudLightning=cloud-lightning-16, CloudRain=cloud-rain-16, 
CloudSnow=cloud-snow-16, CloudSun=cloud-sun-16, Code=code-16, CodeBlock=code-block-16, 
Cog=cog-16, Coin=coin-16, Coins=coins-16, CommandSymbol=command-symbol-16, 
Compass=compass-16, ComputerChip=computer-chip-16, Contrast=contrast-16, CopyClipboard=copy-clipboard-16, 
CreditCard=credit-card-16, CricketBall=cricket-ball-16, Crop=crop-16, Crown=crown-16, 
Crypto=crypto-16, DeleteDocument=delete-document-16, Desktop=desktop-16, Devices=devices-16, 
Dna=dna-16, Document=blank-document-16, Dot=dot-16, Download=download-16, 
Droplets=droplets-16, Duplicate=duplicate-16, EditShape=edit-shape-16, Eject=eject-16, 
Ellipsis=ellipsis-16, EllipsisVertical=ellipsis-vertical-16, Emoji=emoji-16, EmojiSad=emoji-sad-16, 
Envelope=envelope-16, Eraser=eraser-16, ExclamationMark=important-01-16, Exclamationmark=exclamationmark-16, 
Exclamationmark2=exclamationmark-2-16, Exclamationmark3=exclamationmark-3-16, Eye=eye-16, EyeDisabled=eye-disabled-16, 
EyeDropper=eye-dropper-16, Female=female-16, FilmStrip=film-strip-16, Filter=filter-16, 
Finder=finder-16, Fingerprint=fingerprint-16, Flag=flag-16, Folder=folder-16, 
Footprints=footprints-16, Forward=forward-16, ForwardFilled=forward-filled-16, FountainTip=fountain-tip-16, 
FullSignal=full-signal-16, GameController=game-controller-16, Gauge=gauge-16, Gear=cog-16, 
Geopin=geopin-16, Germ=germ-16, Gift=gift-16, Glasses=glasses-16, 
Globe=globe-01-16, Goal=goal-16, Hammer=hammer-16, HardDrive=hard-drive-16, 
Hashtag=hashtag-16, Heading=heading-16, Headphones=headphones-16, Heart=heart-16, 
HeartDisabled=heart-disabled-16, Heartbeat=heartbeat-16, Highlight=highlight-16, Hourglass=hourglass-16, 
House=house-16, Humidity=humidity-16, Image=image-16, Important=important-01-16, 
Info=info-01-16, Italics=italics-16, Key=key-16, Keyboard=keyboard-16, 
Layers=layers-16, Leaderboard=leaderboard-16, Leaf=leaf-16, LevelMeter=signal-2-16, 
LightBulb=light-bulb-16, LightBulbOff=light-bulb-off-16, LineChart=line-chart-16, Link=link-16, 
List=app-window-list-16, Livestream=livestream-01-16, LivestreamDisabled=livestream-disabled-01-16, Lock=lock-16, 
LockDisabled=lock-disabled-16, LockUnlocked=lock-unlocked-16, Logout=logout-16, Lorry=lorry-16, 
Lowercase=lowercase-16, MagnifyingGlass=magnifying-glass-16, Male=male-16, Map=map-16, 
Mask=mask-16, Maximize=maximize-16, MedicalSupport=medical-support-16, Megaphone=megaphone-16, 
MemoryChip=computer-chip-16, MemoryStick=memory-stick-16, Message=speech-bubble-16, Microphone=microphone-16, 
MicrophoneDisabled=microphone-disabled-16, Minimize=minimize-16, Minus=minus-16, MinusCircle=minus-circle-16, 
MinusCircleFilled=minus-circle-filled-16, Mobile=mobile-16, Monitor=monitor-16, Moon=moon-16, 
MoonDown=moon-down-16, MoonUp=moon-up-16, Moonrise=moonrise-16, Mountain=mountain-16, 
Mouse=mouse-16, Move=move-16, Mug=mug-16, MugSteam=mug-steam-16, 
Multiply=multiply-16, Music=music-16, Network=network-16, NewDocument=new-document-16, 
NewFolder=new-folder-16, Number00=number-00-16, Number01=number-01-16, Number02=number-02-16, 
Number03=number-03-16, Number04=number-04-16, Number05=number-05-16, Number06=number-06-16, 
Number07=number-07-16, Number08=number-08-16, Number09=number-09-16, Number10=number-10-16, 
Number11=number-11-16, Number12=number-12-16, Number13=number-13-16, Number14=number-14-16, 
Number15=number-15-16, Number16=number-16-16, Number17=number-17-16, Number18=number-18-16, 
Number19=number-19-16, Number20=number-20-16, Number21=number-21-16, Number22=number-22-16, 
Number23=number-23-16, Number24=number-24-16, Number25=number-25-16, Number26=number-26-16, 
Number27=number-27-16, Number28=number-28-16, Number29=number-29-16, Number30=number-30-16, 
Number31=number-31-16, Number32=number-32-16, Number33=number-33-16, Number34=number-34-16, 
Number35=number-35-16, Number36=number-36-16, Number37=number-37-16, Number38=number-38-16, 
Number39=number-39-16, Number40=number-40-16, Number41=number-41-16, Number42=number-42-16, 
Number43=number-43-16, Number44=number-44-16, Number45=number-45-16, Number46=number-46-16, 
Number47=number-47-16, Number48=number-48-16, Number49=number-49-16, Number50=number-50-16, 
Number51=number-51-16, Number52=number-52-16, Number53=number-53-16, Number54=number-54-16, 
Number55=number-55-16, Number56=number-56-16, Number57=number-57-16, Number58=number-58-16, 
Number59=number-59-16, Number60=number-60-16, Number61=number-61-16, Number62=number-62-16, 
Number63=number-63-16, Number64=number-64-16, Number65=number-65-16, Number66=number-66-16, 
Number67=number-67-16, Number68=number-68-16, Number69=number-69-16, Number70=number-70-16, 
Number71=number-71-16, Number72=number-72-16, Number73=number-73-16, Number74=number-74-16, 
Number75=number-75-16, Number76=number-76-16, Number77=number-77-16, Number78=number-78-16, 
Number79=number-79-16, Number80=number-80-16, Number81=number-81-16, Number82=number-82-16, 
Number83=number-83-16, Number84=number-84-16, Number85=number-85-16, Number86=number-86-16, 
Number87=number-87-16, Number88=number-88-16, Number89=number-89-16, Number90=number-90-16, 
Number91=number-91-16, Number92=number-92-16, Number93=number-93-16, Number94=number-94-16, 
Number95=number-95-16, Number96=number-96-16, Number97=number-97-16, Number98=number-98-16, 
Number99=number-99-16, NumberList=number-list-16, Paperclip=paperclip-16, Paragraph=paragraph-16, 
Patch=patch-16, Pause=pause-16, PauseFilled=pause-filled-16, Pencil=pencil-16, 
Person=person-16, PersonCircle=person-circle-16, PersonLines=person-lines-16, Phone=phone-16, 
PhoneRinging=phone-ringing-16, PieChart=pie-chart-16, Pill=pill-16, Pin=pin-16, 
PinDisabled=pin-disabled-16, Play=play-16, PlayFilled=play-filled-16, Plug=plug-16, 
Plus=plus-16, PlusCircle=plus-circle-16, PlusCircleFilled=plus-circle-filled-16, PlusMinusDivideMultiply=plus-minus-divide-multiply-16, 
PlusSquare=plus-square-16, PlusTopRightSquare=plus-top-right-square-16, Power=power-16, Print=print-16, 
QuestionMark=question-mark-circle-16, QuestionMarkCircle=question-mark-circle-16, Quicklink=quicklink-16, QuotationMarks=quotation-marks-16, 
QuoteBlock=quote-block-16, Racket=racket-16, Raindrop=raindrop-16, RaycastLogoNeg=raycast-logo-neg-16, 
RaycastLogoPos=raycast-logo-pos-16, Receipt=receipt-16, Redo=redo-16, RemovePerson=remove-person-16, 
Repeat=repeat-16, Replace=replace-16, ReplaceOne=replace-one-16, Reply=reply-16, 
Rewind=rewind-16, RewindFilled=rewind-filled-16, Rocket=rocket-16, Rosette=rosette-16, 
RotateAntiClockwise=rotate-anti-clockwise-16, RotateClockwise=rotate-clockwise-16, Rss=rss-16, Ruler=ruler-16, 
SaveDocument=save-document-16, Shield=shield-01-16, ShortParagraph=short-paragraph-16, Shuffle=shuffle-16, 
Sidebar=app-window-sidebar-right-16, Signal0=signal-0-16, Signal1=signal-1-16, Signal2=signal-2-16, 
Signal3=signal-3-16, Snippets=snippets-16, Snowflake=snowflake-16, SoccerBall=soccer-ball-16, 
Speaker=speaker-16, SpeakerDown=speaker-down-16, SpeakerHigh=speaker-high-16, SpeakerLow=speaker-low-16, 
SpeakerOff=speaker-off-16, SpeakerOn=speaker-on-16, SpeakerUp=speaker-up-16, SpeechBubble=speech-bubble-16, 
SpeechBubbleActive=speech-bubble-active-16, SpeechBubbleImportant=speech-bubble-important-16, SquareEllipsis=square-ellipsis-16, StackedBars1=stacked-bars-1-16, 
StackedBars2=stacked-bars-2-16, StackedBars3=stacked-bars-3-16, StackedBars4=stacked-bars-4-16, Star=star-16, 
StarCircle=star-circle-16, StarDisabled=star-disabled-16, Stars=stars-16, Stop=stop-16, 
StopFilled=stop-filled-16, Stopwatch=stopwatch-16, Store=store-16, StrikeThrough=strike-through-16, 
Sun=sun-16, Sunrise=sunrise-16, Swatch=swatch-16, Switch=switch-16, 
Syringe=syringe-16, Tack=tack-16, TackDisabled=tack-disabled-16, Tag=tag-16, 
Temperature=temperature-16, TennisBall=tennis-ball-16, Terminal=terminal-16, Text=text-16, 
TextCursor=text-cursor-16, TextInput=text-input-16, TextSelection=text-selection-16, ThumbsDown=thumbs-down-16, 
ThumbsDownFilled=thumbs-down-filled-16, ThumbsUp=thumbs-up-16, ThumbsUpFilled=thumbs-up-filled-16, Ticket=ticket-16, 
Torch=torch-16, Train=train-16, Trash=trash-16, Tray=tray-16, 
Tree=tree-16, Trophy=trophy-16, TwoPeople=two-people-16, Umbrella=umbrella-16, 
Underline=underline-16, Undo=undo-16, Upload=upload-16, Uppercase=uppercase-16, 
Video=video-16, VideoDisabled=video-disabled-16, Wallet=wallet-16, Wand=wand-16, 
Warning=warning-16, Waveform=waveform-16, Weights=weights-16, Wifi=wifi-16, 
WifiDisabled=wifi-disabled-16, Wind=wind-16, Window=app-window-16, Windsock=windsock-16, 
WrenchScrewdriver=wrench-screwdriver-16, WristWatch=wrist-watch-16, XMarkCircle=x-mark-circle-16, XMarkCircleFilled=x-mark-circle-filled-16, 
XMarkCircleHalfDash=x-mark-circle-half-dash-16, XMarkTopRightSquare=x-mark-top-right-square-16, Xmark=xmark-16, TwoArrowsClockwise=arrow-clockwise-16, 
EyeSlash=eye-disabled-16, SpeakerArrowDown=speaker-down-16, SpeakerArrowUp=speaker-up-16, SpeakerSlash=speaker-off-16, 
TextDocument=blank-document-16, XmarkCircle=x-mark-circle-16, 
```
