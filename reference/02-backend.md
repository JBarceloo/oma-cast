# Raycast 2.8.2 backend: services, data model, native modules, ranking

Scope: `$B/backend` (`B=/Applications/Raycast.app/Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources`). Everything here comes from static analysis: grep and brace-matched extraction over the minified `index.mjs`, `strings`/`nm`/`otool`/`objdump` on the `.node` files, and a header-only check of the user's existing (encrypted) DB files. Nothing was launched, attached to, or modified.

Legend: **[O]** = observed verbatim in the shipped artifact. **[I]** = inferred, with the reasoning given.

AI (to skip): RPC namespaces `ai.*` (117 methods), `aiRuntime.*` (95), `memoryHistory.*` (8), `dictation.*`, `mcp.*`, plus `ai.db` (tables `ai.*`), `mcp-client-sdk.cjs`, and a bundled Claude Agent SDK / Codex / Copilot CLI integration inside `index.mjs` (strings `cowork_settings.json`, `.claude.json`, `agent-*.jsonl`). The semantic/embedding index (`semantic.db`, "Raybrain") in the indexer is also AI-adjacent.

---

## 0. Process & IPC architecture [O]

- `index.mjs` is one esbuild/rolldown ESM bundle with Sentry debug IDs. Its entry runs `_1a()`, which calls `dsn()` to initialise the server.
- **Two transports**:
  1. **stdio** (class `csn`). This is the normal mode.
  2. **embedded mode** through `process._linkedBinding("raycast_host_bridge")` with `registerServer`, `emitLog`, `emitPerformanceLog`. The host can embed Node in-process.
- **Inbound (host to backend)**: newline-delimited JSON on stdin.
  - `{"type":"initialize", databaseKey, signatureSecret, releaseApiToken, posthogApiKey}`. **The SQLCipher key arrives here from the host.**
  - `{"type":"message", id?, method?, data, sentryTrace?}`. If both `id` and `method` are present it is a request. With only `id` it is a response. With only `method` it is a notification.
- **Outbound (backend to host)** framing [O] (`Qft`):
  - Format: `"\x1e" + headerJSON [+ "\x1f" + dataJSON] + "\x1d\n"`.
  - The header is `{type:"message", kind:"response"|"request"|"notification", id, method, destination(s), dataLength, timings}`.
  - Errors and non-message frames (`startupCheckpoint`, `shutdownCheckpoint`, `log`) go into the header only.
  - Payloads over 1 MiB are logged as warnings.
- **Dispatch** (`Spt` / `lut`): `method` is a dotted path, e.g. `clipboard.getAll`. It is resolved by walking the handler object tree `SZa` (+ `CZa = {bext}`), using `Object.hasOwn` at each segment. Each handler is called as `handler(data, {span, notify})`.
- **Backend-to-host requests** use the proxy `Q.<destination>.<ns>.<method>(data)`. Destinations are `host` (native Rust/Swift shell), `frontend` (UI), and `external.bext` (browser extension). Default timeout is 5 s.
- **Notifications** use the proxy `$.<ns>.emit<Event>(payload)`, which becomes the method name `<ns>.<event>`.
- **Environment** [O]: the host passes all `RAYCAST_*` env vars to the backend:

  ```
  API_CUSTOM_BACKEND_URL, API_CUSTOM_FRONTEND_URL, API_ENVIRONMENT, APPLICATION_PATH, BUNDLE_ID, CACHE_DIR,
  DEVELOPMENT_TEST_UPDATES, ENABLE_HANG_DETECTOR, ENABLE_PERF_METRICS, ENABLE_PERFORMANCE_LOGS, ENABLE_ROOT_SEARCH_LOGS,
  GIT_COMMIT_HASH, LOCALE_DECIMAL_SEPARATOR, LOCALE_GROUPING_SEPARATOR, LOGS_DIR, OS_ARCH, OS_IDENTIFIER, OS_NAME,
  OS_VERSION, PID_FILE_PATH, REQUEST_TRACING, REMOTE_AI_CHAT_RELAY, SENTRY(json), SUPPORT_DIR, UPDATE_LOG_FILE_PATH,
  USE_MS_STORE_UPDATES, VERSION, WORKSPACE_DIR, WORKSPACE_LABEL
  ```

- **Worker threads**: `calculator-worker.mjs` and `indexer-worker.mjs`. Both use a tiny `{id, method, params}` to `{id, status:"success"|"error", result}` RPC over `parentPort`, and redirect console output to the parent.
- Both workers wrap `process.dlopen` so that only native addons inside the backend dir can load. Note this for the clone's security model.
- Platform switches show the same backend ships for **darwin-arm64/x64 and win32-x64/arm64**. Only the `.node` files differ. This means the Rust crates are cross-platform except for the Apple-specific bits.

**Linux:** keep this protocol exactly as is (stdin JSONL in, RS/US/GS-framed out). It is simple to implement in Rust (tokio + serde_json) for the host side. Node 22 runs the backend unchanged once the `.node` modules are rebuilt for `linux-x64-gnu`.

---

## 1. Service / RPC map

### 1.1 Top-level handler registry [O]

The registry is `SZa` in `index.mjs`:

```
memoryHistory, ai, aiRuntime, analytics, appFlags, remoteNotifications, auth, uiTesting, browserExtension, calculator,
calendars, clipboard, color, contacts, permissions, database, legacyDatabase, debug, diagnostics, dictation, emojiPicker,
feedback, focus, fileSystem, flightTracker, frecency, imageProxy, indexer, linkInfo, mcp, menuBar, appMenuBarItems,
newsletter, onboarding, userActivity, userDefaults, releases, appleShortcuts, system, themes, snippets, quicklinks,
rootSearch, screenshots, store, settings, hotkey, extensionHost, notes, organizations, translator, trials,
typingPractice, scriptCommands, windowManagement, windowsRunCommands, weather, general     (+ bext via CZa)
```

`rootSearch` is rebuilt per process as `LXa(e)`. `ai` is extended with `createRemoteAiChatPairingLink` and `getRemoteAiChatDiagnostics`.

### 1.2 Inbound RPC methods, grouped (non-AI) [O]

The full list was extracted by brace-matching every handler object, 735 methods in total. AI namespaces are omitted. Each method is called as `<namespace>.<method>`.

- **analytics**: `getTelemetryTags`, `trackAction`, `observeFeatureState`, `track`
- **appFlags**: `getAppFlags`, `refreshAppFlags`, `setDebugAppFlag`
- **remoteNotifications**: `markNotificationRead`, `resetReadNotifications`, `createDebugNotification`
- **auth**: `getAuthorizationUrl`, `getToken`, `refreshToken`, `signout`, `getUser`
- **uiTesting**: `...XXa`, `screenshotForDocs`, `showMainWindow`, `toggleMainWindow`, `triggerHotkey`
- **browserExtension**: `sessionJWT`, `ping`, `getInstalledExtensions`, `browserActionClicked`, `browserDidFocus`, `OAuthRedirect`, `sendToAIChat`, `whoami`
- **calculator**: `calculate`, `parseDate`, `parseDuration`, `refreshCurrencies`, `historyGetAll`, `historyUpsert`, `historyDelete`, `historyDeleteAll`, `historyPin`, `historyUnpin`, `historyMovePinnedUp`, `historyMovePinnedDown`
- **calendars**: `getProviders`, `getAccounts`, `connectAccount`, `disconnectAccount`, `getAccountCalendars`, `getAccountEvents`, `notifyEventsChanged`
- **clipboard**: `add`, `copy`, `paste`, `fetchItemsAndCopy`, `fetchItemsAndPaste`, `copyTextAsFile`, `getAll`, `getLast`, `delete`, `deleteAll`, `deleteAllBeforeDate`, `deleteAllAfterDate`, `rename`, `updateContent`, `pin`, `unpin`, `movePinnedUp`, `movePinnedDown`, `getTextFromImage`, `getTags`, `setTags`, `getFilters`, `setFilter`, `deleteFilter`, `getQrCodeFromImage`, `shouldCaptureUniversalClipboard`
- **color**: `getFormatted`
- **contacts**: `getContacts`, `notifyContactsChanged`
- **permissions**: `notifyPermissionsSnapshot`, `notifyPermissionChanged`
- **database**: `resetDatabases`, `restoreDatabasesFromBackup`, `getDatabaseStatus`, `dismissRecreatedDatabases`
- **legacyDatabase**: `validatePassword`, `importQuicklinks`, `importSnippets`, `importNotes`
- **debug**: `clearRootSearchSnapshots`, `revealDatabaseAndRemoveEncryption`, `simulateNodeCrash`, `testHangDetection`, `testInstallUpdate`, `emitSentryBackendError`, `reportMemoryMetrics`, `getTestFile`, `emulateOS`, `getRegisteredTasks`, `triggerTask`, `enableTask`, `disableTask`, `runXCodeWithoutBuilding`, `testDelayRequest`, `testAppUpdated`, `createDebugClipboardHistoryEntries`
- **diagnostics**: `getActiveIssues`, `executeDiagnosticAction`, `setIssue`, `clearIssue`
- **dictation**: `registerHotkeys`, `unregisterHotkeys`, `submitIssueReport`, `canIncludeAppContext`, `migrateFromApp`, `getCustomVocabulary`, `setCustomVocabulary`, `startSession`, `acceptSession`, `cancelSession`, `finalizeSession`, `getLastTranscription`, `retryTranscription`
- **emojiPicker**: `get`, `pin`, `unpin`, `movePinnedDown`, `movePinnedUp`, `resetRanking`, `search`, `updateCustomKeywords`, `uprank`
- **feedback**: `submitClientFeedback`
- **focus**: `getSession`, `getSessionStartInput`, `startSession`, `updateSession`, `toggleSession`, `pauseSession`, `resumeSession`, `restartSession`, `completeSession`, `cancelSession`, `moveSessionToMenuBar`, `openEditSessionForm`, `trackBlockedAppEvent`, `trackBlockedWebsiteEvent`, `trackSnoozedAppEvent`, `trackSnoozedWebsiteEvent`, `searchCategories`, `createCategory`, `updateCategory`, `deleteCategory`
- **fileSystem**: `createDirectory`, `createFile`, `deleteFile`, `duplicateFile`, `getDirectoryDown`, `getDirectoryUp`, `getExpandedPath`, `getFileMetadata`, `getImageDimensions`, `getFileTextContent`, `probeTextReadable`, `moveFile`, `moveToTrash`, `readFile`, `writeFile`, `writeNewFile`, `copyFile`, `copyDirectory`, `downloadFile`, `isDirectory`, `exists`, `checkVolumesAvailability`
- **flightTracker**: `getFlight`
- **frecency**: `visit`, `getAllByIds`, `getAll`, `search`, `reset`
- **imageProxy**: `fetchImage`
- **indexer**: `index`, `search`, `searchFileContents`, `getContentSnippet`, `semanticSearch`, `classifyPaths`, `getAllApplications`, `getApplication`, `getAllPreferences`, `getAllGames`, `getGame`, `prepopulate`, `update`, `excludeFromIndex`, `installService`, `uninstallService`, `getIndexStats`, `getChurnHotspots`, `unexcludeChurnHotspot`, `getIndexingParams`, `getIndexingState`, `getRecentFiles`, `getIndexingStatus`, `getContentSearchAvailability`, `getSemanticIndexingStatus`, `getReclaimableContentIndexSize`, `reclaimContentIndexSpace`, `deleteFromIndex`, `setUserContentType`, `changeSearchEngine`, `applyContentIndexingLimits`
- **linkInfo**: `getLinkInfo`
- **mcp**: `installServer`, `installServers`, `getServers`, `updateServer`, `deleteServer`, `deleteAllServers`, `startServer`, `restartServer`, `stopServer`, `cancelAuthorization`, `logoutServer`, `refreshServerTools`
- **menuBar**: `menuWillOpen`, `menuDidClose`, `actionCallback`, `itemRemoved`, `showExceptionInMainWindow`, `activateCommand`, `deactivateCommand`
- **appMenuBarItems**: `getPinned`, `pin`, `unpin`, `movePinnedUp`, `movePinnedDown`
- **newsletter**: `signUp`
- **onboarding**: `complete`, `getSuggestedExtensions`
- **userActivity**: `trackWrappedActivity`, `trackWrappedAiChatActivity`, `countActivitiesByTypeAndYear`, `countActivitiesByTypeYearAndCommandFilter`, `getLatestActivitiesByTypeAndYear`, `getTopActivitiesByCount`, `getTopActivitiesByCountAndCommandFilter`, `getHourlyActivityDistribution`, `getDailyActivityDistribution`, `countAiChatActivitiesByTypeAndYear`, `sumAiChatWordCountByTypeAndYear`, `getTopAiChatModelsByYear`, `countAiChatActivitiesBySourceAndYear`, `countAiChatActivitiesBySourceTypeAndYear`, `trackWrappedFocusActivity`, `getFocusActivityStats`
- **userDefaults**: `delete`, `get`, `set`
- **releases**: `installUpdate`, `preflightInstallUpdate`, `canShutDownForAutoInstall`, `checkForUpdates`, `dismissReleaseNotes`, `getDownloadedUpdate`, `revealDownloadedUpdate`, `getWhatsNew`, `checkForFailedUpdate`, `getChangelog`, `getReleaseByVersion`
- **appleShortcuts**: `getAll`, `refresh`, `getFetchState`
- **system**: `openUrl`, `handleDeeplink`, `heartbeat`, `activateFileAccessServices`, `getDeviceTag`, `getLogFilePaths`, `defaultBrowserSupportsAutomation`, `exportSettingsAndData`, `importSettingsAndData`, `isExportEncrypted`, `startOnboardingImport`, `getImportSettingsDataStatus`, `getClassicMigrationStatus`, `getV2MigrationStatus`, `keepXrayData`, `adoptClassicData`, `getWindowState`, `sendFeedback`, `healthPing`, `healthDatabase`, `healthFileSystem`, `sessionStatusUpdate`, `networkConfigurationChanged`, `powerSourceChanged`, `copyLogFiles`
- **themes**: `getAll`, `getById`, `create`, `update`, `delete`
- **snippets**: `autoSnippet`, `getAllKeywordSnippets`, `getByTitle`, `create`, `update`, `delete`, `move`, `list`, `getOne`, `pin`, `unpin`, `movePinnedUp`, `movePinnedDown`, `updateAccessedAt`, `deleteAll`, `updateCopyCount`, `getTags`, `isKeywordAvailable`
- **quicklinks**: `list`, `getQuicklink`, `listLibrary`, `save`, `delete`, `deleteAll`, `update`, `move`, `updateOpenCount`, `getTags`, `pin`, `unpin`, `movePinnedUp`, `movePinnedDown`
- **rootSearch**: `recordQuickAiPrompt`, `removeQuickAiPrompt`, `clearQuickAiPromptHistory`, `search`, `activateEmptyQuery`, `handleAction`, `getItem`, `getCommandDeeplink`, `getAllAliases`
- **screenshots**: `getLatestByDate`, `search`, `pin`, `unpin`, `reorderPinned`, `getIndexingState`, `refreshIndex`, `getDefaultLocations`, `getUnavailableSearchDirectories`, `deleteScreenshot`, `getTextFromImage`, `getQrCodeFromImage`
- **store**: `checkForExtensionUpdates`, `get`, `getUserExtensions`, `getByIds`, `install`, `removeFromStore`, `getReferralCodes`, `search`
- **settings**: `getGeneralSettings`, `getCloudSyncSettings`, `getCloudSyncStatus`, `toggleCloudSyncSettings`, `overrideCloudSyncConnection`, `reconnectCloudSync`, `deleteCloudSyncData`, `hasCloudSyncData`, `getCloudSyncCategories`, `setCloudSyncCategoryEnabled`, `getCloudSyncCategoryProgress`, `getCloudSyncCurrentDeviceId`, `getCloudSyncDevices`, `updateCloudSyncDeviceDisplayName`, `deauthorizeCloudSyncDevice`, `updateGeneralSettings`, `getAllCommandSettings`, `getCommandSettings`, `getHotkeyConflicts`, `getCommandHotkeyConflict`, `openCatalog`, `openCatalogPage`, `closeCatalog`, `getCatalogExtensionsDetails`, `deleteCommandSettings`, `updateCommandSettings`, `updateCommandSettingsBatch`, `getInternalExtensionSettings`, `getContentZoom`, `updateInternalExtensionSettings`, `addAiToolConfirmationAllowListEntries`, `removeAiToolConfirmationAllowListEntry`, `resetAiToolConfirmationAllowList`, `getAllInternalExtensionSettings`, `getAllNodeExtensionSettings`, `getNodeExtensionSettings`, `updateNodeExtensionSettings`, `updateNodeEntryPointPreferences`, `setTidyMenuBar`, `browserExtensionHealthSnapshot`, `browserExtensionConnectionTest`
- **hotkey**: `getAll`
- **extensionHost**: `callNodeCallback`, `launchCommand`, `getEntryPointPreferences`, `getAllExtensions`, `getInstalledNodeExtensionSummaries`, `getExtension`, `getExtensionWithCommand`, `getCommands`, `getTools`, `hasTools`, `getDiagnostics`, `loadCommand`, `unloadEntryPoint`, `uninstall`, `startDevelopment`, `getSingleActiveDevelopmentExtension`, `stopDevelopment`, `getDevelopmentCommand`, `openInEditor`, `abortForkExtension`, `forkExtension`, `importExtension`, `getDevelopmentEntryPoints`, `usesInternalApi`, `setInternalApi`, `addCommand`, `addTool`, `createExtension`
- **notes**: `saveAttachment`, `validateAttachment`, `uploadAttachment`, `retrieveCachedAttachment`, `create`, `update`, `delete`, `deleteAll`, `pin`, `unpin`, `movePinnedUp`, `movePinnedDown`, `list`, `browse`, `count`, `getWindowData`, `getCurrentWindowData`, `setCurrentNote`, `touchAccessed`, `listDeleted`, `recoverNote`, `permanentlyDelete`, `emptyTrash`, `purgeOldDeletedNotes`
- **organizations**: `getOrganizations`, `activateOrganization`, `getOrganization`, `createOrganization`, `updateOrganization`, `deleteOrganization`, `leaveOrganization`, `getOrganizationMembers`, `addOrganizationMember`, `updateOrganizationMember`, `removeOrganizationMember`, `getInviteToken`, `resetInviteToken`, `getOrganizationWebhooks`, `createOrganizationWebhook`, `updateOrganizationWebhook`, `deleteOrganizationWebhook`, `getTrialStatus`
- **translator**: `translate`, `getAllTranslateCustomCommands`, `getTranslateCustomCommand`, `saveTranslateCustomCommand`, `updateTranslateCustomCommand`, `deleteTranslateCustomCommand`
- **trials**: `completeTrialNudge`, `disableTrialNudges`, `resetTrialNudgeState`, `createTrialExtensionCheckout`
- **typingPractice**: `getRandomTypingPracticeQuote`
- **scriptCommands**: `runScript`, `runScriptStreamed`, `cancelScript`, `getScripts`
- **windowManagement**: `getAllLayouts`, `getLayout`, `saveLayout`, `updateLayout`, `deleteLayout`, `deleteAllLayouts`, `exportLayouts`, `importLayouts`, `getSavedWindowState`, `saveWindowState`
- **windowsRunCommands**: `create`, `update`, `delete`, `getAll`, `getOne`, `getByAlias`, `getByCommand`, `getTags`, `pin`, `unpin`, `recordExecution`, `duplicate`, `deleteAll`
- **weather**: `getWeather`
- **general**: `openRaycastCommandOnMainWindow`, `menuBarOwningAppUpdate`

(`uiTesting` also spreads one unresolved object `...XXa`.)

### 1.3 Backend to host/frontend calls (what the native shell must implement) [O]

Gathered from all `Q.<dest>.<ns>.<method>(` call sites.

- **host.applications**: getAllForPath, getAllInstalled, getAllRunning, getCategory, getDefault, getDeveloperClis, getFrontmost, getFrontmostWindowContext, getSelectedText, getTextBeforeCaret, hideAllExceptFrontmost, open, showDesktop, terminate, toggleStageManager, unhideAllHidden
- **host.clipboard**: clearPasteboard, decodeQrCode, placeInClipboard `{entry:{target:"pasteboard"|"frontmost", items}, shouldCloseWindow, overridePasteboard, excludeMainWindow, throwsOnTimeout, waitForPaste, isEmojiOrSymbol}`
- **host.snippets**: register `{snippetIds[], keywords[]}`, remove `{snippetIds[]}`. **The keystroke watcher and text expansion live in the host, not in Node.**
- **host.hotkey**: register, remove, replaceCommandHotkeys, translateKeyCodes
- **host.windowManagement**: getActiveWindow, getDesktops, getWindowsOnActiveDesktop, setWindowBounds
- **host.calendars**: createEvent, deleteEvent, editEvent, getCalendars, getEvent, getEvents, respondToEvent. **host.contacts**: getContacts, getContactsChanges
- **host.fileSystem**: getSelectedItems, openFile, openInTerminal, openTrash, placeInTrash, revealFile, toggleHiddenFiles
- **host.media**: getApplications, getInputDevices, nextTrack, playPause, previousTrack, setApplicationMuted, setApplicationVolume, setVolume, toggleCameraMute, toggleMicrophoneMute, toggleMute, turnVolumeDown/Up
- **host.system**: dismissNotifications, ejectAllDisks, getComputerSystemInfo, getDeviceTagFallbackSeed, getManagedSignInPolicy, getMemorySample, getSystemAppearance, hibernate, isOnBatteryPower, lockScreen, logOut, readClassicKeychainValue, readClassicUserDefaults, readSharedKeychainValue, showScreenSaver, sleep, sleepDisplays, toggleAirplaneMode, toggleBluetooth, toggleEnergySaver, toggleHdr, toggleNightLight, toggleQuickLookPreview, toggleSystemAppearance. **host.wifi**: toggleRadio
- **host.raycast**: show/hide main/settings/AI/theme-studio/welcome/feedback windows, confetti, shakeMainWindow, dictation start/stop/cancel, revealLogFiles, terminateOtherInstances, …
- **host.raycastFocus**: startSession, pauseSession, resumeSession, cancelSession, completeSessionWithReason, handleWebsiteSnooze, moveSessionToMenuBar, notifySessionStarted
- **host.menuBar**: hideItem, removeItem, showError, updateItems, migrateStatusItemPlacement. **host.permissions**: checkPermission, requestPermission. **host.location**: estimateTravelTime, getCurrentLocation, resolvePlace. **host.weather**: getCurrentWeather
- **host.settings**: generalSettingsChanged, hyperKey, internalExtensionSettingsUpdated, keepMainWindowVisibleDuringDevelopment, themeChanged, uiZoom
- **host.workspace**: captureAiContext, captureFocusedWindow, captureScreen, captureScreenArea, getFocusedElementContext, getFrontmostAppContext
- **host.***: screenshots.getDefaultScreenshotLocations, releases.*, appleShortcuts.getAllAppleShortcuts, systemNotifications.show, userDefaults.didChange, auth.userChanged, uiTesting.*
- **frontend.extensionHost**: render, renderEmpty, renderSuspense, showToast, hideToast, showHUD, showAlert, popToRoot, clearSearchBar, closeMainRaycastWindow, createQuicklink, createSnippet, openCommandPreferences, openExtensionPreferences, initOAuth, authorizeOAuth, getToolPreferences, commandException, ensureBrowserExtensionInstalled
- **frontend.general**: openRaycastCommand, openRaycastMainAtRoute, openSettings, showToast, closeMainWindow, show{AiModeImport, ExtensionInstall, ImportSettingsData, McpOAuth, PromptImport, ThemeImport}, …
- **frontend.notes**: insertNoteContent, parseNoteContent, serializeNoteContent. These are ProseMirror conversions done in the UI.
- **frontend.windowManagement**: executeLayout. **frontend.calendars**: joinMeetingForEvent, openCalendarEvent, handleMeetingAutoJoin. **frontend.image**: renderImages
- **external.bext** (browser extension): getTabs, getTab, executeJS, switchToTab, closeTab, duplicateTab

Notifications emitted (`$.x.emitY` becomes `x.y`), e.g.:

- `clipboard.stateChanged`, `snippets.updated`, `quicklinks.updated`, `notes.updated`, `emojiPicker.stateChanged`, `calculator.historyStateChanged`, `calculator.currenciesRefreshed`
- `indexer.{stateChanged, updated, applicationsUpdated, semanticStateChanged}`
- `settings.update{Theme, WindowMode, RootSearchSensitivity, UiZoom, …}`, `settings.cloudSync{SettingsChanged, StatusChanged, DevicesChanged}`
- `extensionHost.{extensionInstalled, extensionUninstalled, extensionSettingsUpdated, sessionEnded, formReset, formSetFocus}`
- `system.{export,import}SettingsData{Progress,Completed}`, `themes.updated`, `rootSearch.aliasesChanged`

### 1.4 Feature to service map (where each Raycast feature lives)

| Feature | Backend namespace(s) | Storage | Native work |
|---|---|---|---|
| Root search / ranking | `rootSearch`, `frecency` | `frecency.db` (`root_search`), `settings_v2.commands` (alias, favorite_order, fallback_order) | none (pure JS + Rust repo) |
| App discovery | `indexer.getAllApplications/getApplication/getAllPreferences/getAllGames` | `app_index.db` (`app`) | host `applications.getAllInstalled`, indexer.node |
| File search & content index | `indexer.*` (31 methods), `fileSystem.*` | `SUPPORT_DIR/index/` (minidex + `db/` SQLite FTS5) | indexer.node, "Raycast Content Indexer" (extraction worker / OCR) |
| Clipboard history | `clipboard.*` | `clipboard.db` + `SUPPORT_DIR/clipboard/` blobs | host watches the pasteboard and calls `clipboard.add`; host pastes |
| Snippets & expansion | `snippets.*` | `main.db` (`snippets`, `router_snippet_tag`) | host keyword watcher (`host.snippets.register`) |
| Quicklinks | `quicklinks.*` | `main.db` (`quicklinks`, `router_quicklink_tag`) | frontend/host open URL |
| Calculator/units/currency/dates | `calculator.*` | `main.db` (`calculator_history`, `currencies`) | `calculator-worker.mjs` → Calculator.node (SoulverCore) **and** calculator-rs (shadow/Windows) |
| Window management | `windowManagement.*` | `main.db` (`window_management_layout_groups`, `_layouts`) | host `windowManagement.*` |
| Emoji & symbols | `emojiPicker.*` | `emoji.db` (seeded from data.node's embedded JSON) | none |
| System commands | builtin commands → host `system.*`, `media.*` | — | host |
| Floating notes | `notes.*` | `main.db` (`notes`) | frontend ProseMirror |
| Calendar / My Schedule | `calendars.*` | — (live from host; OAuth accounts via API) | host EventKit; Google/Outlook via Raycast API |
| Contacts | `contacts.*` | `main.db` (`contacts` cache) | host |
| Extensions runtime & store | `extensionHost.*`, `store.*`, `settings.*NodeExtension*` | `node_extensions.db`, `settings_v2.node_extensions`, `SUPPORT_DIR/node/runtime` | Node child processes (process-utils `adoptChildProcesses`) |
| Script commands | `scriptCommands.*` | filesystem dirs | spawn |
| Hotkeys / aliases / favorites | `settings.updateCommandSettings`, `hotkey.getAll`, `rootSearch.getAllAliases` | `settings_v2.commands` (`alias`, `macos_hotkey`, `windows_hotkey`, `favorite_order`) | host `hotkey.register` |
| Settings | `settings.*`, `userDefaults.*` | `settings_v2.db`, `main.db.user_defaults` | — |
| Cloud sync | `settings.*CloudSync*` | `sync_agent.db` + shapes over main/ai/settings_v2 | data.node `SyncAgent` (websocket to `sync.rayca.st`) |
| Themes | `themes.*` | `settings_v2.themes` | — |
| Import/export `.rayconfig` | `system.exportSettingsAndData/importSettingsAndData/isExportEncrypted` | file | Node crypto |
| Focus sessions | `focus.*` | `main.db.focus_categories`, `user_activity.user_focus_activity` | host `raycastFocus.*` (app/website blocking) |
| Screenshots search | `screenshots.*` | `screenshots.db` | fs-utils `classifyScreenshot`, OCR |
| Translator | `translator.*` | `main.db.translate_custom_commands` | Raycast API |
| Raycast Wrapped stats | `userActivity.*` | `user_activity.db` | — |
| Classic (v1) migration | `legacyDatabase.*`, `system.getClassicMigrationStatus/adoptClassicData` | reads `raycast-enc.sqlite` (SQLCipher v4) | better_sqlite3 (SQLite3MultipleCiphers) |
| Org packs (Teams) | `organizations.*` | `org_*` tables | Raycast API |

---

## 2. Persistence

### 2.1 Engines [O]

- **Main data layer**: Rust napi module `data.darwin-arm64.node`.
  - Source tree `data/core/src/...`. Repositories `data_node::repositories::{clipboard, snippets, quicklinks, notes, emoji, frecency, settings, app_index, calculator, currencies, window_management, focus_categories, user_activity, user_defaults, node_extensions, screenshots, contacts, apple_shortcuts, app_menu_bar_items, windows_run_commands, translate_custom_commands, org_packs, pending_tokens, ai, ai_runs, ai_tool_usage, ai_picker_usage}`.
  - Uses forked **rusqlite** (git checkout `rusqlite-a59c9f088fdd06a7/052ad51`), bundled **SQLite 3.53.0**, `serde_rusqlite 0.42`, and **refinery** migrations (`V{n}__name`, 248 distinct migration names).
  - The JS facade is `G.<repo>.<method>` (e.g. `G.clipboard.all`, `G.frecency.visit`).
- **Custom SQL functions** registered per connection [O]: `RAYDATE()` (default timestamp), `RAYDATE_STEP`, `RAYDATE_UNIX_NANOS`, `RAYCAST_LOWER`, `RAYACRONYM`, `RAYFIRSTLINE`, `ULID()`.
  - Primary keys in v2 tables are ULID text.
  - Timestamps are RFC 3339 text written by `RAYDATE()`.
- **Database layout** [O]: one main connection plus `ATTACH DATABASE ? AS ? KEY ?`. That is SQLCipher-style keyed attach, hence the `schema.table` prefixes in DDL.
  - The files in the user's `~/Library/Application Support/com.raycast.macos/` are `main.db, ai.db, app_index.db, clipboard.db, emoji.db, frecency.db, node_extensions.db, screenshots.db, settings.db, settings_v2.db, user_activity.db` (each with `-wal`/`-shm`), plus `sync_agent.db` when sync is on, `last_key`, `clipboard/`, `index/`, `node/`.
- **Encryption** [O + I]:
  - The first 16 bytes of `main.db`, `clipboard.db` and `emoji.db` are random, not `SQLite format 3`, so the databases are encrypted [O].
  - The key comes from the host in the `initialize` message (`databaseKey`) [O].
  - Host binary strings [O]: `.vm-database-key must contain exactly 64 hexadecimal characters`, `Backed up the database key to the login keychain`, `backUpDatabaseKeyIfNeeded`, `DatabaseKeyUnavailableAlert`, `Allow Keychain access to start Raycast`. So the key is a 32-byte random value stored as 64 hex characters in the **macOS login Keychain**.
  - There is also a `last_key` file (64 bytes) in the support dir, which the backup code copies (`copy_last_key_file`). Its exact role is unknown; I did not read it.
  - data.node imports no CommonCrypto `CCCrypt`, only `CCRandomGenerateBytes`. So the cipher is compiled in. It is likely SQLCipher or SQLite3MultipleCiphers with built-in AES [I].
  - Backups: `create_backup`, `rekeyed_backup_copy`, `set_aside_unreadable_database`, timestamped backup dirs.
- **better_sqlite3.node** is built with **SQLite3MultipleCiphers** (`sqlite3mc_*` symbols). It is only used for Classic v1 import, with `pragma cipher='sqlcipher'; legacy=4; key='<sha256(secret + "yvkwWXzxPPBAqY2tmaKrB*DvYjjMaeEf")>'` [O, `zVa`/`BVa`], and for third-party DB reads (Wispr Flow).
- **Cloud sync** (data.node `SyncAgent`, `sync/agent/src/...`):
  - Websocket via the `yawc` crate over rustls to `sync.rayca.st`.
  - Local journal `SUPPORT_DIR/sync_agent.db`, using the same encryption key.
  - Per-table "shapes" with column CRDT strategies. `open_count`, `copy_count` and `device_generations` are **GCounter**; the rest is last-writer-wins by `updated_at` [I].
  - Synced categories [O]: `ai-presets-commands, ai-history, dictation, mcp-servers, quicklinks, notes, snippets, window-management-layouts, extensions, general-settings.{appearance,ui-zoom,open-at-login,show-in-menu-bar,window-mode}`. Always on: `themes`, `internal_extensions`, `commands`, `translate_custom_commands`, `general_settings.{favicon_provider,pop_to_root_timeout,escape_key_behavior,page_navigation_keys,window_presentation_mode,navigation_bindings,root_search_sensitivity}`.
- **Indexer DB**: separate, under `SUPPORT_DIR/index/` (`version`, `category-rules`, `db/`, minidex segments, `journal.wal`, `.minidex.lock`, `dbstats.json`, `last-full-index.json`). It also has `semantic.db` (AI embeddings) and `content-index-quarantine.json`, `semantic-queue.json`.
- **JSON side files** in SUPPORT_DIR/CACHE_DIR [O]: `cloudsync-*.json`, `recent-files.json`, `update-state.json`, `remote-settings.json`, `classic-defaults.json`, `changelog.json`, logs `calculator-shadow.jsonl`.
- Paths [O]: `~/Library/Application Support/com.raycast.macos` (`.debug`/`.internal` variants). Paths are supplied through `RAYCAST_SUPPORT_DIR`, `RAYCAST_CACHE_DIR` and `RAYCAST_LOGS_DIR`.

**Linux:**

- Use `rusqlite` with feature `bundled-sqlcipher-vendored-openssl` (or `libsqlite3-sys` + SQLite3MultipleCiphers) and refinery. Keep the attach-per-domain layout.
- Store the 32-byte key hex in the **Secret Service** (libsecret / KWallet via the `keyring` or `oo7` crate). Fall back to a `0600` file, mirroring their `.vm-database-key` escape hatch.
- Use XDG dirs: `$XDG_DATA_HOME/<app>` for SUPPORT_DIR, `$XDG_CACHE_HOME/<app>` for CACHE_DIR, and `$XDG_STATE_HOME/<app>/logs` for LOGS_DIR.
- Use ULIDs with the `ulid` crate and register the same custom SQL functions.

### 2.2 Schemas (non-AI) [O]

The DDL below was extracted verbatim from the migration strings in `data.darwin-arm64.node`.

- Several tables appear in more than one version: legacy integer-id versions, plus `_new` rebuilds that become the final shape after `ALTER TABLE … RENAME`.
- The **latest** shape is usually the `_new` variant with ULID ids and `RAYDATE()`.
- Later `ALTER TABLE` columns seen in the strings:
  - app_index: `bundleName, alternateNames(JSON), keywords(JSON), executionAlias, executableName, anchor`.
  - `calculator_history.custom_name`.
  - `calculator_legacy_imports.name_pending/pin_pending`.
  - `settings_v2.general_settings`: `ui_zoom, show_favorites_in_compact_mode, hyper_key_*, tidy_menu_bar, builtin_hotkeys_preset, open_folders_in_tabs, use_spotlight_gesture`.
  - `frecency.root_search`: `search_terms, opened_at`.
  - `clipboard.entries.content_hash`, `clipboard.representations.content_search`.
- AI DDL is omitted.
- The `GeneralSettingsColumn` enum [O] lists the final general-settings columns: OpenAtLogin, ShowInMenuBar, Appearance, ThemeDarkId, ThemeLightId, WindowMode, WindowPresentationMode, WindowActivationBehavior, GlobalHotkey, FaviconProvider, EscapeKeyBehavior, EscapeKeyClosesWindow, NavigationBindings, PageNavigationKeys, UseSystemProxySettings, AdditionalCertificateAuthorities, EnforcedInputSourceId, RootSearchSensitivity, TidyMenuBar, BuiltinHotkeysPreset, UiZoom, HyperKeyCode, HyperKeyIncludeShift, HyperKeyCapsLockAction, HyperKeyDisplayShortcut, UseSpotlightGesture, OpenFoldersInTabs, ShowFavoritesInCompactMode.

Some extracted statements are truncated at the closing `)` because the strings are not NUL-terminated per statement. The column lists are complete.

```sql
CREATE TABLE settings.general (
   setting_key TEXT PRIMARY KEY,
   setting_value BLOB NOT NULL,
   frecency_date REAL
) STRICT;

CREATE TABLE settings.shortcuts (
    target TEXT PRIMARY KEY,
    alias TEXT,
    hotkey TEXT
) STRICT;

CREATE TABLE settings.extension_settings (
    extension_id TEXT NOT NULL,
    setting_key TEXT NOT NULL,
    setting_value BLOB NOT NULL,
    frecency_date REAL,
    PRIMARY KEY (extension_id, setting_key)

CREATE TABLE settings_v2.internal_extensions_new (
    id TEXT NOT NULL PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1,
    deprecated_meta TEXT,
    enabled_fallback_command_ids TEXT,
    synced_meta TEXT,
    local_meta TEXT,
    macos_synced_meta TEXT,
    windows_synced_meta TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.node_extensions_new (
    id TEXT NOT NULL PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1,
    deprecated_meta TEXT,
    oauthTokens TEXT,
    localStorage TEXT,
    storedValues TEXT,
    enabled_fallback_command_ids TEXT,
    synced_meta TEXT,
    local_meta TEXT,
    macos_synced_meta TEXT,
    windows_synced_meta TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    uninstalled INTEGER NOT NULL DEFAULT 0,
    device_generations TEXT NOT NULL DEFAULT '{}'
) STRICT, WITHOUT ROWID;

CREATE TABLE settings_v2.commands_new (
    id TEXT NOT NULL PRIMARY KEY,
    extension_id TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    alias TEXT,
    deprecated_hotkey TEXT,
    deprecated_meta TEXT,
    custom_subtitle TEXT,
    assumed_view_kind TEXT,
    favorite_order REAL DEFAULT NULL,
    fallback_order REAL DEFAULT NULL,
    status_item TEXT,
    synced_meta TEXT,
    local_meta TEXT,
    macos_synced_meta TEXT,
    windows_synced_meta TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    macos_hotkey TEXT,
    windows_hotkey TEXT,
    device_generations TEXT NOT NULL DEFAULT '{}'
) STRICT, WITHOUT ROWID;

CREATE INDEX settings_v2.idx_commands_extension_id ON commands(extension_id);

CREATE TABLE settings_v2.general_settings_new (
    id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
    open_at_login INTEGER NOT NULL DEFAULT 1,
    show_in_menu_bar INTEGER NOT NULL DEFAULT 1,
    follow_system_appearance INTEGER NOT NULL DEFAULT 1,
    theme_id TEXT NOT NULL DEFAULT 'bundled-raycast-dark',
    window_mode TEXT NOT NULL DEFAULT 'expanded',
    global_hotkey TEXT,
    favicon_provider TEXT,
    pop_to_root_timeout INTEGER NOT NULL DEFAULT 90,
    escape_key_behavior TEXT NOT NULL DEFAULT 'pop-back-or-close',
    page_navigation_keys TEXT NOT NULL DEFAULT 'square-brackets',
    use_system_proxy_settings INTEGER NOT NULL DEFAULT 0,
    additional_certificate_authorities TEXT NOT NULL DEFAULT '[]',
    window_presentation_mode TEXT NOT NULL DEFAULT 'mouse-screen',
    enforced_input_source_id TEXT,
    navigation_bindings TEXT NOT NULL DEFAULT 'emacs',
    window_capture_hotkey TEXT DEFAULT NULL,
    window_capture_copy_to_clipboard INTEGER NOT NULL DEFAULT 1,
    window_capture_show_in_finder INTEGER NOT NULL DEFAULT 0,
    window_capture_cleanshotx_overlay INTEGER NOT NULL DEFAULT 0,
    window_capture_custom_wallpaper TEXT DEFAULT NULL,
    root_search_sensitivity TEXT NOT NULL DEFAULT 'medium',
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    FOREIGN KEY (theme_id) REFERENCES themes(id),
    FOREIGN KEY (window_mode) REFERENCES window_modes(id)

CREATE TABLE settings_v2.general_settings_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT '0000000000GENERA1SETT1NGS0',
  open_at_login INTEGER NOT NULL DEFAULT 1,
  show_in_menu_bar INTEGER NOT NULL DEFAULT 1,
  appearance TEXT NOT NULL DEFAULT 'system',
  theme_dark_id TEXT,
  theme_light_id TEXT,
  window_mode TEXT NOT NULL DEFAULT 'expanded',
  global_hotkey TEXT,
  favicon_provider TEXT,
  pop_to_root_timeout INTEGER NOT NULL DEFAULT 90,
  escape_key_behavior TEXT NOT NULL DEFAULT 'pop-back-or-close',
  page_navigation_keys TEXT NOT NULL DEFAULT 'square-brackets',
  use_system_proxy_settings INTEGER NOT NULL DEFAULT 0,
  additional_certificate_authorities TEXT NOT NULL DEFAULT '[]',
  window_presentation_mode TEXT NOT NULL DEFAULT 'mouse-screen',
  enforced_input_source_id TEXT,
  navigation_bindings TEXT NOT NULL DEFAULT 'emacs',
  root_search_sensitivity TEXT NOT NULL DEFAULT 'medium',
  tidy_menu_bar INTEGER NOT NULL DEFAULT 0,
  builtin_hotkeys_preset TEXT NOT NULL DEFAULT 'improved',
  hyper_key_code TEXT DEFAULT NULL,
  hyper_key_include_shift INTEGER NOT NULL DEFAULT 1,
  hyper_key_caps_lock_action TEXT DEFAULT NULL,
  hyper_key_display_shortcut INTEGER NOT NULL DEFAULT 1,
  open_folders_in_tabs INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.cloud_sync_settings (
    id INTEGER NOT NULL DEFAULT 1 PRIMARY KEY CHECK (id = 1),
    enabled INTEGER NOT NULL DEFAULT 0,
    devices TEXT NOT NULL DEFAULT '[]',
    content TEXT NOT NULL DEFAULT '[]',
    connection TEXT NOT NULL DEFAULT '{}',
    enabled_at TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.themes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT UNIQUE NOT NULL,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.general_settings_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT '0000000000GENERA1SETT1NGS0',
  open_at_login INTEGER NOT NULL DEFAULT 1,
  show_in_menu_bar INTEGER NOT NULL DEFAULT 1,
  follow_system_appearance INTEGER NOT NULL DEFAULT 1,
  theme_id TEXT NOT NULL DEFAULT '0000000000THEMERAYDARK0000',
  window_mode TEXT NOT NULL DEFAULT 'expanded',
  global_hotkey TEXT,
  favicon_provider TEXT,
  pop_to_root_timeout INTEGER NOT NULL DEFAULT 90,
  escape_key_behavior TEXT NOT NULL DEFAULT 'pop-back-or-close',
  page_navigation_keys TEXT NOT NULL DEFAULT 'square-brackets',
  use_system_proxy_settings INTEGER NOT NULL DEFAULT 0,
  additional_certificate_authorities TEXT NOT NULL DEFAULT '[]',
  window_presentation_mode TEXT NOT NULL DEFAULT 'mouse-screen',
  enforced_input_source_id TEXT,
  navigation_bindings TEXT NOT NULL DEFAULT 'emacs',
  root_search_sensitivity TEXT NOT NULL DEFAULT 'medium',
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  FOREIGN KEY (theme_id) REFERENCES themes_new(id)

CREATE TABLE settings_v2.cloudsync_settings (
    id INTEGER NOT NULL DEFAULT 1 PRIMARY KEY CHECK (id = 1),
    enabled INTEGER NOT NULL DEFAULT 0,
    connection TEXT NOT NULL DEFAULT '{}',
    disabled_categories TEXT NOT NULL DEFAULT '[]',
    enabled_at TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.themes (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
) STRICT;

CREATE TABLE settings_v2.window_modes (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
) STRICT;

CREATE TABLE settings_v2.general_settings (
    singleton_key INTEGER NOT NULL DEFAULT 1 PRIMARY KEY CHECK (singleton_key),
    open_at_login INTEGER NOT NULL DEFAULT 1,
    show_in_menu_bar INTEGER NOT NULL DEFAULT 1,
    follow_system_appearance INTEGER NOT NULL DEFAULT 1,
    theme_id TEXT NOT NULL DEFAULT 'bundled-raycast-dark',
    window_mode TEXT NOT NULL DEFAULT 'expanded',
    global_hotkey TEXT,
    FOREIGN KEY (theme_id) REFERENCES themes(id),
    FOREIGN KEY (window_mode) REFERENCES window_modes(id)

CREATE TABLE settings_v2.internal_extensions (
    id TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1,
    meta TEXT
) STRICT;

create TABLE settings_v2.commands (
    id TEXT PRIMARY KEY,
    extension_id TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    favorited INTEGER NOT NULL DEFAULT 0,
    alias TEXT,
    hotkey TEXT,
    meta TEXT
) STRICT;ALTER TABLE settings_v2.general_settings ADD COLUMN page_navigation_keys TEXT NOT NULL DEFAULT 'square-brackets'; ALTER TABLE settings_v2.node_extensions ADD COLUMN device_generations TEXT NOT NULL DEFAULT '{}';
ALTER TABLE settings_v2.commands ADD COLUMN device_generations TEXT NOT NULL DEFAULT '{}';
ALTER TABLE settings_v2.commands RENAME COLUMN hotkey TO deprecated_hotkey;
ALTER TABLE settings_v2.commands ADD COLUMN macos_hotkey TEXT;
ALTER TABLE settings_v2.commands ADD COLUMN windows_hotkey TEXT;
CREATE TABLE settings_v2.node_extensions (
    id TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1,
    meta TEXT,
    oauthTokens TEXT,
    localStorage TEXT,
    storedValues TEXT
) STRICT;
-- Rename meta -> deprecated_meta (kept for node-backend migration bootstrapper to read from)

CREATE TABLE settings_v2.themes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL UNIQUE,
  appearance TEXT NOT NULL,
  background TEXT NOT NULL,
  background_secondary TEXT NOT NULL,
  foreground TEXT NOT NULL,
  accent TEXT NOT NULL,
  selection TEXT NOT NULL,
  loader TEXT NOT NULL,
  red TEXT NOT NULL,
  orange TEXT NOT NULL,
  yellow TEXT NOT NULL,
  green TEXT NOT NULL,
  blue TEXT NOT NULL,
  purple TEXT NOT NULL,
  magenta TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE emoji.emoji (
  id INTEGER NOT NULL PRIMARY KEY,
  symbol TEXT NOT NULL,
	name TEXT NOT NULL,
  supportsSkinTones INTEGER NOT NULL DEFAULT FALSE,
  category TEXT NOT NULL,
  unicodeVersion REAL,
  frecencyDate REAL,
  pinned REAL
) STRICT;

-- Alias table
CREATE TABLE emoji.aliases (
  emoji_id INTEGER NOT NULL,
  alias TEXT NOT NULL,
  FOREIGN KEY (emoji_id) REFERENCES emoji(id)

CREATE TABLE emoji.keyword (
  emoji_id INTEGER NOT NULL,
  keyword TEXT NOT NULL,
  FOREIGN KEY(emoji_id) REFERENCES emoji(id)

CREATE TABLE emoji.custom_keyword (
  emoji_id INTEGER NOT NULL,
	keyword TEXT NOT NULL,
	FOREIGN KEY(emoji_id) REFERENCES emoji(id)

CREATE TABLE emoji.checksum (
  id INTEGER NOT NULL PRIMARY KEY,
  checksum BLOB NOT NULL
) STRICT;

-- Emoji FTS tables for search
CREATE VIRTUAL TABLE emoji.keyword_FTS USING FTS5(
  emoji_id,
  keyword,
  content='',
  content_rowid='id'
);

CREATE TRIGGER emoji.keyword_FTS_ai AFTER INSERT ON emoji.keyword BEGIN
  INSERT INTO keyword_FTS(rowid, keyword) VALUES (NEW.emoji_id, NEW.keyword);

CREATE TRIGGER emoji.keyword_FTS_ad AFTER DELETE ON emoji.keyword BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.keyword);

CREATE TRIGGER emoji.keyword_FTS_au AFTER UPDATE ON emoji.keyword BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.keyword);

CREATE TRIGGER emoji.keyword_FTS_ai_custom AFTER INSERT ON emoji.custom_keyword BEGIN
  INSERT INTO keyword_FTS(rowid, keyword) VALUES (NEW.emoji_id, NEW.keyword);

CREATE TRIGGER emoji.keyword_FTS_ad_custom AFTER DELETE ON emoji.custom_keyword BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.keyword);

CREATE TRIGGER emoji.keyword_FTS_au_custom AFTER UPDATE ON emoji.custom_keyword BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.keyword);

CREATE TRIGGER emoji.keyword_FTS_ai_alias AFTER INSERT ON emoji.aliases BEGIN
  INSERT INTO keyword_FTS(rowid, keyword) VALUES (NEW.emoji_id, NEW.alias);

CREATE TRIGGER emoji.keyword_FTS_ad_alias AFTER DELETE ON emoji.aliases BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.alias);

CREATE TRIGGER emoji.keyword_FTS_au_alias AFTER UPDATE ON emoji.aliases BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.alias);

CREATE TRIGGER emoji.keyword_FTS_ai_name AFTER INSERT ON emoji.emoji BEGIN
  INSERT INTO keyword_FTS(rowid, keyword) VALUES (NEW.id, NEW.name);

CREATE TRIGGER emoji.keyword_FTS_ad_name AFTER DELETE ON emoji.emoji BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.id, OLD.name);

CREATE TRIGGER emoji.keyword_FTS_au_name AFTER UPDATE ON emoji.emoji BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.id, OLD.name);

CREATE TABLE app_index.app (
  id INTEGER NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  path TEXT NOT NULL,
  localizedName TEXT,
  raycastId TEXT NOT NULL UNIQUE,
  applicationId TEXT NOT NULL,
  contentType INTEGER NOT NULL DEFAULT 0
) STRICT;

-- Index for faster lookups by applicationId
CREATE INDEX app_index.app_application_id_idx ON app(applicationId);

CREATE INDEX app_index.app_content_type_idx ON app(contentType);

CREATE TABLE currencies (
  code TEXT NOT NULL PRIMARY KEY,
  usd_rate REAL NOT NULL,
  currency_type TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) strict, without rowid;

CREATE TRIGGER update_currencies_updated_at AFTER
UPDATE ON currencies FOR EACH ROW BEGIN
UPDATE currencies
SET
  updated_at = CURRENT_TIMESTAMP
WHERE
  code = OLD.code
  OR code = NEW.code;
END;

CREATE TABLE notes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  title TEXT,
  text TEXT NOT NULL,
  raw_content TEXT,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  deleted_at TEXT,
  last_accessed_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE org_transcription_styles (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  style_id TEXT NOT NULL,
  value TEXT NOT NULL,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE mcp_servers (
  id TEXT NOT NULL PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('stdio', 'http')),
  icon TEXT NOT NULL,
  title TEXT NOT NULL,
  mention_name TEXT NOT NULL,
  description TEXT,
  built_in INTEGER NOT NULL DEFAULT 0 CHECK (built_in IN (0, 1)),
  error_message TEXT,
  last_connected TEXT,
  created_at TEXT NOT NULL,
  oauth_json TEXT CHECK (oauth_json IS NULL OR json_valid(oauth_json)),
  updated_at TEXT NOT NULL,
  command TEXT,
  arguments_json TEXT CHECK (arguments_json IS NULL OR json_valid(arguments_json)),
  environment_json TEXT CHECK (environment_json IS NULL OR json_valid(environment_json)),
  url TEXT,
  headers_json TEXT CHECK (headers_json IS NULL OR json_valid(headers_json)),
  oauth_config_json TEXT CHECK (oauth_config_json IS NULL OR json_valid(oauth_config_json)),
  tools_json TEXT NOT NULL CHECK (json_valid(tools_json)),
  CHECK (
    (type = 'stdio' AND command IS NOT NULL AND url IS NULL) OR
    (type = 'http' AND url IS NOT NULL AND command IS NULL)

CREATE INDEX mcp_servers_type_idx ON mcp_servers(type);

CREATE INDEX mcp_servers_mention_name_idx ON mcp_servers(mention_name);

CREATE TABLE calculator_history (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  expression TEXT NOT NULL UNIQUE,
  result TEXT NOT NULL,
  calculation_type TEXT NOT NULL DEFAULT 'unknown',
  copy_count INTEGER NOT NULL DEFAULT 1,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE calculator_legacy_imports (
  migration_id TEXT NOT NULL,
  expression TEXT NOT NULL,
  PRIMARY KEY (migration_id, expression)

CREATE TABLE pending_tokens (
  token TEXT PRIMARY KEY,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;

CREATE TRIGGER update_pending_tokens_updated_at
AFTER UPDATE ON pending_tokens
FOR EACH ROW
BEGIN
  UPDATE pending_tokens
  SET updated_at = CURRENT_TIMESTAMP
  WHERE token = OLD.token;
END;

CREATE TABLE local_org_snippet_usage (
  snippet_id TEXT NOT NULL PRIMARY KEY,
  copy_count INTEGER NOT NULL DEFAULT 0,
  accessed_at TEXT NOT NULL DEFAULT(RAYDATE()),
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE local_org_snippet_tags (
  snippet_id TEXT NOT NULL PRIMARY KEY,
  tags TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE local_org_quicklink_tags (
  quicklink_id TEXT NOT NULL PRIMARY KEY,
  tags TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE screenshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    category TEXT NOT NULL CHECK (category IN ('ScreenCapture', 'ScreenRecording')),
    text TEXT,
    is_pinned INTEGER NOT NULL DEFAULT 0,
    pin_order INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    text_extracted_at TEXT
) STRICT;

CREATE INDEX idx_screenshots_path ON screenshots(path);

CREATE INDEX idx_screenshots_pinned ON screenshots(is_pinned, pin_order);

CREATE INDEX idx_screenshots_modified ON screenshots(modified_at DESC);

CREATE TABLE IF NOT EXISTS quicklinks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    link TEXT NOT NULL,
    icon TEXT NOT NULL,
    application_id TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    open_count INTEGER DEFAULT 0
) STRICT;

CREATE TRIGGER quicklinks_updated_at AFTER UPDATE ON quicklinks
FOR EACH ROW
WHEN (OLD.name != NEW.name OR
      OLD.link != NEW.link OR
      OLD.icon != NEW.icon)

CREATE TABLE raycastConfiguration (
  extension_id TEXT PRIMARY KEY,
  configuration TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL DEFAULT (RAYDATE())

CREATE TABLE user_defaults (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) strict, without rowid;

CREATE TRIGGER update_user_defaults_last_modified_at AFTER
UPDATE ON user_defaults FOR EACH ROW BEGIN
UPDATE user_defaults
SET
  last_modified_at = CURRENT_TIMESTAMP
WHERE
  key = OLD.key
  OR key = NEW.key;

CREATE TRIGGER quicklinks_updated_at AFTER UPDATE ON quicklinks
FOR EACH ROW
WHEN (OLD.name != NEW.name OR
      OLD.link != NEW.link OR
      OLD.icon != NEW.icon OR
      OLD.raw_content != NEW.raw_content)

CREATE TABLE focus_categories (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  category_id TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK (kind IN ('builtin', 'custom')),
  builtin_id TEXT,
  title TEXT NOT NULL,
  icon TEXT NOT NULL,
  website_hosts_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(website_hosts_json)),
  application_ids_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(application_ids_json)),
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  accessed_at TEXT NOT NULL DEFAULT(RAYDATE()),
  CHECK (
    (kind = 'builtin' AND builtin_id IS NOT NULL) OR
    (kind = 'custom' AND builtin_id IS NULL)

CREATE UNIQUE INDEX focus_categories_builtin_id_idx ON focus_categories(builtin_id) WHERE builtin_id IS NOT NULL;
CREATE INDEX focus_categories_kind_accessed_title_idx ON focus_categories(kind, accessed_at DESC, title COLLATE NOCASE);

CREATE INDEX focus_categories_title_idx ON focus_categories(title COLLATE NOCASE);

CREATE TABLE quicklinks_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL,
  link TEXT NOT NULL,
  raw_content TEXT NOT NULL DEFAULT '{"type":"doc","content":[{"type":"paragraph"}]}',
  icon TEXT NOT NULL,
  application_id TEXT,
  open_count INTEGER NOT NULL DEFAULT 0,
  open_with TEXT,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE router_quicklink_tag_new (
  quicklink_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  PRIMARY KEY (quicklink_id, tag),
  FOREIGN KEY (quicklink_id) REFERENCES quicklinks_new(id) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

CREATE TABLE router_quicklink_tag (
    quicklink_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (quicklink_id) REFERENCES quicklinks(id),
    PRIMARY KEY (quicklink_id, tag)

CREATE TRIGGER update_quicklinks_updated_at_on_tag_insert AFTER
INSERT ON router_quicklink_tag FOR EACH ROW
BEGIN
  UPDATE quicklinks
  SET
    updated_at = CURRENT_TIMESTAMP
  WHERE
    id = NEW.quicklink_id;
END;

CREATE TRIGGER update_quicklinks_updated_at_on_tag_delete AFTER
DELETE ON router_quicklink_tag FOR EACH ROW
BEGIN
  UPDATE quicklinks
  SET
    updated_at = CURRENT_TIMESTAMP
  WHERE
    id = OLD.quicklink_id;
END;

CREATE TABLE translate_custom_commands (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL,
  source_language TEXT NOT NULL DEFAULT 'auto',
  target_language TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE IF NOT EXISTS local_transcription_style_application_ids (
  style_id TEXT NOT NULL,
  application_id TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  PRIMARY KEY(style_id, application_id)

CREATE TABLE clipboard (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  text TEXT NOT NULL,
  file_path TEXT,
  image_hash TEXT,
  copy_count INTEGER NOT NULL DEFAULT 1,
  category TEXT DEFAULT 'text',
  rich_text_data BLOB,
  application_path TEXT,
  text_content TEXT,
  pinned DOUBLE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TRIGGER update_clipboard_last_modified_at AFTER
UPDATE ON clipboard FOR EACH ROW BEGIN
UPDATE clipboard
SET
  last_modified_at = CURRENT_TIMESTAMP
WHERE
  id = OLD.id;

CREATE TABLE notes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  title TEXT,
  text TEXT NOT NULL,
  raw_content TEXT,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT,
  last_accessed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT, WITHOUT ROWID;

CREATE TRIGGER update_notes_last_modified_at AFTER
UPDATE OF title, raw_content, text, pinned ON notes FOR EACH ROW BEGIN
UPDATE notes SET last_modified_at = CURRENT_TIMESTAMP WHERE id = OLD.id;
END;

CREATE TRIGGER update_snippets_last_modified_at AFTER
UPDATE ON snippets FOR EACH ROW 
WHEN (OLD.icon != NEW.icon OR 
      OLD.title != NEW.title OR 
      OLD.keyword != NEW.keyword OR 
      OLD.raw_content != NEW.raw_content OR 
      OLD.text != NEW.text OR
      OLD.pinned != NEW.pinned)

CREATE TABLE notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    text TEXT NOT NULL,
    raw_content TEXT,
    pinned REAL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;

CREATE TRIGGER update_notes_last_modified_at AFTER
UPDATE ON notes FOR EACH ROW BEGIN
UPDATE notes
SET
  last_modified_at = CURRENT_TIMESTAMP
WHERE
  id = OLD.id;
END;

CREATE TABLE snippets_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  icon TEXT NOT NULL,
  title TEXT NOT NULL,
  keyword TEXT,
  raw_content TEXT,
  text TEXT NOT NULL,
  copy_count INTEGER NOT NULL DEFAULT 0,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  accessed_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE router_snippet_tag_new (
  snippet_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  PRIMARY KEY (snippet_id, tag),
  FOREIGN KEY (snippet_id) REFERENCES snippets_new(id) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

CREATE TABLE apple_shortcuts (
  sort_order INTEGER NOT NULL PRIMARY KEY,
  shortcut_id TEXT,
  name TEXT NOT NULL,
  accepts_input INTEGER CHECK (accepts_input IN (0, 1)),
  folder_id TEXT,
  folder_name TEXT,
  image_path TEXT,
  updated_at TEXT NOT NULL DEFAULT (RAYDATE())

CREATE TABLE router_snippet_tag (
    snippet_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (snippet_id) REFERENCES snippets(id),
    PRIMARY KEY (snippet_id, tag)

CREATE TRIGGER update_snippets_last_modified_at_on_tag_insert AFTER
INSERT ON router_snippet_tag FOR EACH ROW
BEGIN
  UPDATE snippets
  SET
    last_modified_at = CURRENT_TIMESTAMP
  WHERE
    id = NEW.snippet_id;
END;

CREATE TRIGGER update_snippets_last_modified_at_on_tag_delete AFTER
DELETE ON router_snippet_tag FOR EACH ROW
BEGIN
  UPDATE snippets
  SET
    last_modified_at = CURRENT_TIMESTAMP
  WHERE
    id = OLD.snippet_id;
END;

CREATE TABLE windows_run_commands (
  id TEXT PRIMARY KEY DEFAULT (ULID()),
  alias TEXT NOT NULL,
  command TEXT NOT NULL,
  arguments TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  icon TEXT NOT NULL DEFAULT 'terminal',
  pinned REAL,
  times_executed INTEGER NOT NULL DEFAULT 0,
  last_executed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT (RAYDATE())

CREATE INDEX idx_windows_run_commands_alias ON windows_run_commands(alias);

CREATE INDEX idx_windows_run_commands_times_executed ON windows_run_commands(times_executed DESC);

CREATE INDEX idx_windows_run_commands_pinned_updated ON windows_run_commands(pinned, updated_at DESC);

CREATE TABLE windows_run_command_tag (
  command_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  FOREIGN KEY (command_id) REFERENCES windows_run_commands(id) ON DELETE CASCADE,
  PRIMARY KEY (command_id, tag)

CREATE INDEX idx_windows_run_command_tag_tag ON windows_run_command_tag(tag);

CREATE TABLE org_ai_commands (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  value TEXT NOT NULL,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE contacts (
  sort_order INTEGER NOT NULL PRIMARY KEY,
  contact_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  name TEXT,
  given_name TEXT,
  family_name TEXT,
  organization TEXT,
  phone_numbers TEXT,
  email_addresses TEXT,
  postal_addresses TEXT,
  image_data_available INTEGER NOT NULL DEFAULT 0 CHECK (image_data_available IN (0, 1)),
  updated_at TEXT NOT NULL DEFAULT (RAYDATE())

CREATE TABLE org_quicklinks (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  name TEXT NOT NULL,
  link TEXT NOT NULL,
  icon TEXT NOT NULL,
  raw_content TEXT NOT NULL DEFAULT '{"type":"doc","content":[{"type":"paragraph"}]}',
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE org_snippets (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  icon TEXT NOT NULL,
  title TEXT NOT NULL,
  keyword TEXT,
  text TEXT NOT NULL,
  raw_content TEXT,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE org_pack_sync_state (
  kind TEXT NOT NULL PRIMARY KEY,
  last_synced_at INTEGER NOT NULL DEFAULT 0
) STRICT, WITHOUT ROWID;
-- Migration to:
-- 1. Remove application_id column from quicklinks table
-- 2. Replace open_with column with platform-specific columns (open_with_macos, open_with_windows, open_with_ios)

CREATE TABLE quicklinks_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL,
  link TEXT NOT NULL,
  raw_content TEXT NOT NULL DEFAULT '{"type":"doc","content":[{"type":"paragraph"}]}',
  icon TEXT NOT NULL,
  open_count INTEGER NOT NULL DEFAULT 0,
  open_with_macos TEXT,
  open_with_windows TEXT,
  open_with_ios TEXT,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE router_quicklink_tag_new (
  quicklink_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  PRIMARY KEY (quicklink_id, tag),
  FOREIGN KEY (quicklink_id) REFERENCES quicklinks_new(id) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

CREATE TABLE snippets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    icon TEXT NOT NULL,
    title TEXT NOT NULL,
    keyword TEXT,
    raw_content TEXT,
    text TEXT NOT NULL,
    copy_count INTEGER NOT NULL DEFAULT 0,
    pinned REAL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    accessed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;

CREATE TRIGGER update_snippets_last_modified_at AFTER
UPDATE ON snippets FOR EACH ROW BEGIN
UPDATE snippets
SET
  last_modified_at = CURRENT_TIMESTAMP
WHERE
  id = OLD.id;

CREATE TABLE app_menu_bar_pins (
  app_id TEXT NOT NULL,
  menu_item_id TEXT NOT NULL,
  pinned REAL NOT NULL,
  PRIMARY KEY (app_id, menu_item_id)

CREATE INDEX app_menu_bar_pins_idx_app_pinned ON app_menu_bar_pins(app_id, pinned);

CREATE TABLE org_ai_agents (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  value TEXT NOT NULL,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE org_skills (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  organization_name TEXT NOT NULL,
  organization_handle TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  content TEXT NOT NULL,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE local_org_skill_settings (
  skill_id TEXT NOT NULL PRIMARY KEY,
  enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE INDEX calculator_legacy_imports_expression ON calculator_legacy_imports (expression);

CREATE TRIGGER calculator_legacy_name_written AFTER UPDATE OF custom_name ON calculator_history
BEGIN
  UPDATE calculator_legacy_imports SET name_pending = 0 WHERE expression = OLD.expression;
END;

CREATE TRIGGER calculator_legacy_pin_written AFTER UPDATE OF pinned ON calculator_history
BEGIN
  UPDATE calculator_legacy_imports SET pin_pending = 0 WHERE expression = OLD.expression;
END;

CREATE TRIGGER calculator_legacy_entry_deleted AFTER DELETE ON calculator_history
BEGIN
  UPDATE calculator_legacy_imports SET name_pending = 0, pin_pending = 0 WHERE expression = OLD.expression;
END;

CREATE TABLE local_org_snippet_keywords (
  snippet_id TEXT NOT NULL PRIMARY KEY,
  keyword TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE notes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  title TEXT,
  text TEXT NOT NULL,
  raw_content TEXT,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT, WITHOUT ROWID;

CREATE TABLE window_management_layout_groups (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL,
  icon_name TEXT,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE window_management_layouts (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  group_id TEXT NOT NULL REFERENCES window_management_layout_groups(id) ON DELETE CASCADE,
  position TEXT NOT NULL,
  size TEXT NOT NULL,
  offset TEXT NOT NULL,
  z_position INTEGER NOT NULL DEFAULT 0,
  source TEXT,
  display_index INTEGER,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE INDEX window_management_layouts_group_id ON window_management_layouts(group_id);

CREATE TABLE router_snippet_tag_new (
  snippet_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  PRIMARY KEY (snippet_id, tag),
  FOREIGN KEY (snippet_id) REFERENCES snippets(id) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

CREATE TABLE searchMobile (
  search_id TEXT PRIMARY KEY,
  frequency INTEGER NOT NULL DEFAULT 1,
  last_used_at TEXT NOT NULL DEFAULT (RAYDATE()),
  created_at TEXT NOT NULL DEFAULT (RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT (RAYDATE()),
  type TEXT,
  favorite REAL,
  alias TEXT,
  keywords TEXT
) WITHOUT ROWID;

CREATE INDEX searchMobile_favorite_idx ON searchMobile(favorite) WHERE favorite IS NOT NULL;
CREATE INDEX searchMobile_type_idx ON searchMobile(type);

CREATE INDEX searchMobile_last_used_at_idx ON searchMobile(last_used_at);

CREATE TABLE keyboardSearchMobile (
  search_id TEXT PRIMARY KEY,
  frequency INTEGER NOT NULL DEFAULT 1,
  last_used_at TEXT NOT NULL DEFAULT (RAYDATE()),
  created_at TEXT NOT NULL DEFAULT (RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT (RAYDATE()),
  type TEXT,
  favorite REAL,
  alias TEXT,
  keywords TEXT
) WITHOUT ROWID;

CREATE INDEX keyboardSearchMobile_favorite_idx ON keyboardSearchMobile(favorite) WHERE favorite IS NOT NULL;
CREATE INDEX keyboardSearchMobile_type_idx ON keyboardSearchMobile(type);

CREATE INDEX keyboardSearchMobile_last_used_at_idx ON keyboardSearchMobile(last_used_at);

CREATE TABLE frecency.root_search (
    item_id TEXT NOT NULL,
    frecency_date REAL,
    PRIMARY KEY (item_id)

CREATE VIRTUAL TABLE frecency.root_FTS USING FTS5(
  item_id,
  content='root_search'
);

CREATE TRIGGER frecency.root_FTS_ai AFTER INSERT ON frecency.root_search BEGIN
  INSERT INTO root_FTS(rowid, item_id) VALUES
   (NEW.rowid, NEW.item_id);

CREATE TRIGGER frecency.root_FTS_ad AFTER DELETE ON frecency.root_search BEGIN
  INSERT INTO root_FTS(root_FTS, rowid, item_id) VALUES ('delete', OLD.rowid, OLD.item_id);

CREATE TRIGGER frecency.root_FTS_au AFTER UPDATE ON frecency.root_search BEGIN
  INSERT INTO root_FTS(root_FTS, rowid, item_id) VALUES ('delete', OLD.rowid, OLD.item_id);

CREATE VIRTUAL TABLE frecency.root_FTS USING FTS5(
  item_id
);

CREATE TRIGGER frecency.root_FTS_ai AFTER INSERT ON frecency.root_search BEGIN
  INSERT INTO root_FTS(item_id) VALUES (NEW.item_id);

CREATE TRIGGER frecency.root_FTS_ad AFTER DELETE ON frecency.root_search BEGIN
  DELETE FROM root_FTS WHERE item_id = OLD.item_id;
END;

CREATE TRIGGER frecency.root_FTS_au AFTER UPDATE ON frecency.root_search WHEN OLD.item_id IS NOT NEW.item_id BEGIN
  DELETE FROM root_FTS WHERE item_id = OLD.item_id;
  INSERT INTO root_FTS(item_id) VALUES (NEW.item_id);

CREATE INDEX clipboard.index_entries_content_hash ON entries(content_hash);

CREATE TABLE clipboard.entries (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  workspace_id INTEGER NOT NULL DEFAULT 1,
  source_name TEXT NOT NULL,
  source_host INTEGER NOT NULL,
  source_url TEXT NOT NULL,
  copy_count INTEGER NOT NULL DEFAULT 1,
  pinned REAL,
  FOREIGN KEY(workspace_id) REFERENCES workspaces(id)

CREATE TABLE clipboard.items (
  id INTEGER NOT NULL,
  entry_id INTEGER NOT NULL,
  FOREIGN KEY (entry_id) REFERENCES entries(id),
  PRIMARY KEY (id, entry_id)

CREATE TABLE clipboard.representations (
  id INTEGER NOT NULL,
  item_id INTEGER NOT NULL,
  entry_id INTEGER NOT NULL,
  mime_type TEXT NOT NULL,
  content_type INTEGER NOT NULL,
  content TEXT NOT NULL,
  FOREIGN KEY (item_id, entry_id) REFERENCES items(id, entry_id),
  PRIMARY KEY (id, item_id)

CREATE TABLE clipboard.router_entry_category (
  entry_id INTEGER NOT NULL,
  category TEXT NOT NULL,
  FOREIGN KEY(entry_id) REFERENCES entries(id),
  PRIMARY KEY(entry_id, category)

CREATE TABLE clipboard.workspaces (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL
) STRICT;

-- Update an entry's "updated_at" field when it's updated
CREATE TRIGGER clipboard.update_entry_updated_at
AFTER UPDATE ON entries
WHEN old.updated_at <> current_timestamp
BEGIN
  UPDATE entries
    SET updated_at = CURRENT_TIMESTAMP
  WHERE id = OLD.id;
END;

CREATE VIRTUAL TABLE clipboard.representations_FTS USING FTS5(
  content,
  entry_title,
  content='representations',
  content_rowid='id'
);

CREATE TRIGGER clipboard.representations_FTS_ai AFTER INSERT ON clipboard.representations BEGIN
  INSERT INTO representations_FTS(rowid, content, entry_title)

CREATE TRIGGER clipboard.representations_FTS_ad AFTER DELETE ON clipboard.representations BEGIN
  INSERT INTO representations_FTS(representations_FTS, rowid, content) VALUES ('delete', OLD.id, OLD.content);

CREATE TRIGGER clipboard.representations_FTS_au AFTER UPDATE ON clipboard.representations BEGIN
  INSERT INTO representations_FTS(representations_FTS, content) VALUES ('delete', OLD.content);

CREATE TRIGGER clipboard.delete_item_representations
  AFTER DELETE ON items
  FOR EACH ROW
BEGIN
  DELETE FROM representations
  WHERE representations.item_id = OLD.id;
END;

CREATE TRIGGER clipboard.delete_entry_items
  AFTER DELETE ON entries
  FOR EACH ROW
BEGIN
  DELETE FROM items
  WHERE items.entry_id = OLD.id;
END;

CREATE TRIGGER clipboard.delete_entry_categories
  AFTER DELETE ON entries
  FOR EACH ROW
BEGIN
  DELETE FROM router_entry_category
  WHERE router_entry_category.entry_id = OLD.id;
END;

CREATE INDEX clipboard.representations_idx_entry_id_item_id ON representations(entry_id, item_id);

CREATE TRIGGER clipboard.delete_item_representations
  BEFORE DELETE ON items
  FOR EACH ROW
BEGIN
  DELETE FROM representations
  WHERE representations.item_id = OLD.id;
END;

CREATE TRIGGER clipboard.delete_entry_items
  BEFORE DELETE ON entries
  FOR EACH ROW
BEGIN
  DELETE FROM items
  WHERE items.entry_id = OLD.id;
END;

CREATE TRIGGER clipboard.representations_FTS_ai AFTER INSERT ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(rowid, content, entry_title)

CREATE TRIGGER clipboard.representations_FTS_ad BEFORE DELETE ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(representations_tri_FTS, rowid, content, entry_title)

CREATE TRIGGER clipboard.representations_FTS_au AFTER UPDATE ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(representations_tri_FTS, rowid, content, entry_title)

CREATE TABLE clipboard.filters (
    source_url TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1
) STRICT, WITHOUT ROWID;

-- Map a filter (by source_url) to the tags it applies.
CREATE TABLE clipboard.router_filter_tag (
    source_url TEXT NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (source_url) REFERENCES filters(source_url),
    PRIMARY KEY (source_url, tag)

CREATE INDEX clipboard.representations_idx_content_search
  ON representations(entry_id, content_search)

CREATE VIEW clipboard.representations_with_title AS SELECT id, content,
    (SELECT title FROM entries WHERE entries.id = representations.entry_id) AS entry_title FROM representations;

-- Create new FTS table based on representations with title using the
-- trigram tokenizer to enable substring search
CREATE VIRTUAL TABLE clipboard.representations_tri_FTS USING FTS5(
  content,
  entry_title,
  content='representations_with_title',
  content_rowid='id',
  tokenize='trigram'
);

CREATE TRIGGER clipboard.representations_tri_FTS_ai AFTER INSERT ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(rowid, content, entry_title)

CREATE TRIGGER clipboard.representations_tri_FTS_ad AFTER DELETE ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(representations_tri_FTS, rowid) VALUES ('delete', OLD.id);

CREATE TRIGGER clipboard.representations_tri_FTS_au AFTER UPDATE ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(representations_tri_FTS, content) VALUES ('delete', OLD.content);

CREATE TABLE clipboard.router_entry_tag (
    entry_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (entry_id) REFERENCES entries(id),
    PRIMARY KEY (entry_id, tag)

CREATE TRIGGER clipboard.update_entries_updated_at_on_tag_insert AFTER
INSERT ON router_entry_tag FOR EACH ROW
BEGIN
  UPDATE entries
  SET
    updated_at = CURRENT_TIMESTAMP
  WHERE
    id = NEW.entry_id;
END;

CREATE TRIGGER clipboard.update_entries_updated_at_on_tag_delete AFTER
DELETE ON router_entry_tag FOR EACH ROW
BEGIN
  UPDATE entries
  SET
    updated_at = CURRENT_TIMESTAMP
  WHERE
    id = OLD.entry_id;
END;

CREATE TRIGGER clipboard.delete_entry_tags
  AFTER DELETE ON entries
  FOR EACH ROW
BEGIN
  DELETE FROM router_entry_tag
  WHERE router_entry_tag.entry_id = OLD.id;
END;

CREATE INDEX clipboard.entries_idx_pinned ON entries(pinned);

CREATE INDEX clipboard.entries_idx_updated_at_id ON entries(updated_at DESC, id DESC);

CREATE INDEX clipboard.representations_idx_item_id ON representations(item_id);

CREATE TABLE screenshots.entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    category TEXT NOT NULL CHECK (category IN ('ScreenCapture', 'ScreenRecording')),
    text TEXT,
    is_pinned INTEGER NOT NULL DEFAULT 0,
    pin_order INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    text_extracted_at TEXT
) STRICT;

CREATE INDEX screenshots.idx_screenshots_path ON entries(path);

CREATE INDEX screenshots.idx_screenshots_pinned ON entries(is_pinned, pin_order);

CREATE INDEX screenshots.idx_screenshots_modified ON entries(modified_at DESC);

CREATE TABLE user_activity.user_activity_new (
    id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
    activity_type TEXT NOT NULL,
    user_activity_info_key TEXT REFERENCES user_activity_info(key) ON DELETE SET NULL,
    platform TEXT NOT NULL,
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    device TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE user_activity.ai_chat_activity_new (
    id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
    activity_type TEXT NOT NULL,
    source TEXT NOT NULL,
    chat_model TEXT NOT NULL,
    word_count INTEGER NOT NULL,
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    device TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE user_activity.user_focus_activity_new (
    id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
    source TEXT NOT NULL,
    date TEXT NOT NULL,
    duration REAL,
    pause_events TEXT,
    block_events TEXT,
    snooze_events TEXT,
    device TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT '',
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE user_activity.user_activity_info (
    key TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE user_activity.user_activity (
    activity_type TEXT NOT NULL,
    user_activity_info_key TEXT REFERENCES user_activity_info(key) ON DELETE SET NULL,
    platform TEXT NOT NULL,
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    device TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    PRIMARY KEY (device, updated_at)

CREATE TABLE user_activity.ai_chat_activity (
    activity_type TEXT NOT NULL,
    source TEXT NOT NULL,
    chat_model TEXT NOT NULL,
    word_count INTEGER NOT NULL,
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    device TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    PRIMARY KEY (device, updated_at)

CREATE TABLE user_activity.user_focus_activity (
    source TEXT NOT NULL,
    date TEXT NOT NULL,
    duration REAL,
    pause_events TEXT,
    block_events TEXT,
    snooze_events TEXT,
    device TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    PRIMARY KEY (device, updated_at)

CREATE TABLE node_extensions.tools (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    extension_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    icon TEXT,
    keywords TEXT, -- Stored as JSON array
    preferences TEXT, -- Stored as JSON array
    functionalities TEXT, -- Stored as JSON array
    confirmation INTEGER NOT NULL DEFAULT 0,
    input TEXT, -- Stored as JSON
    output TEXT, -- Stored as JSON
    instructions TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    digest TEXT, -- Stored as JSON
    FOREIGN KEY (extension_id) REFERENCES extensions(id) ON DELETE CASCADE
) STRICT;

CREATE TRIGGER node_extensions.update_tools_updated_at
AFTER UPDATE ON tools
FOR EACH ROW
BEGIN
  UPDATE tools
  SET updated_at = CURRENT_TIMESTAMP
  WHERE id = OLD.id;
END;

CREATE TABLE node_extensions.extensions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT,
    name TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    icon TEXT NOT NULL,
    keywords TEXT, -- Stored as JSON array
    license TEXT,
    author TEXT,
    owner TEXT,
    access TEXT,
    readme_url TEXT,
    source_url TEXT,
    ai TEXT, -- Stored as JSON
    preferences TEXT, -- Stored as JSON array
    local_sources TEXT,
    version TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    requires_download INTEGER NOT NULL DEFAULT 1
) STRICT;

CREATE TRIGGER node_extensions.update_extensions_updated_at
AFTER UPDATE ON extensions
FOR EACH ROW
BEGIN
  UPDATE extensions
  SET updated_at = CURRENT_TIMESTAMP
  WHERE id = OLD.id;
END;

CREATE TABLE node_extensions.commands (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    extension_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    title TEXT NOT NULL,
    subtitle TEXT,
    description TEXT NOT NULL,
    icon TEXT,
    keywords TEXT, -- Stored as JSON array
    mode TEXT NOT NULL,
    is_enabled INTEGER NOT NULL DEFAULT 1,
    preferences TEXT, -- Stored as JSON array
    arguments TEXT, -- Stored as JSON array
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    interval TEXT,
    ran_at TEXT,
    run_error TEXT,
    status_item TEXT, -- Stored as JSON
    interval_enabled INTEGER NOT NULL DEFAULT 0,
    custom_subtitle TEXT,
    assumed_view_kind TEXT,
    digest TEXT, -- Stored as JSON
    FOREIGN KEY (extension_id) REFERENCES extensions(id) ON DELETE CASCADE
) STRICT;

CREATE TRIGGER node_extensions.update_commands_updated_at
AFTER UPDATE ON commands
FOR EACH ROW
BEGIN
  UPDATE commands
  SET updated_at = CURRENT_TIMESTAMP
  WHERE id = OLD.id;
END;

CREATE INDEX node_extensions.idx_commands_extension_id ON commands(extension_id);

CREATE UNIQUE INDEX node_extensions.idx_extensions_extension_id ON extensions(extension_id);

CREATE UNIQUE INDEX node_extensions.idx_commands_extension_id_name ON commands(extension_id, name);

CREATE UNIQUE INDEX node_extensions.idx_tools_extension_id_name ON tools(extension_id, name);

CREATE TABLE node_extensions.widgets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  extension_id INTEGER NOT NULL REFERENCES extensions(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  icon TEXT,
  icon_variants TEXT CHECK (icon_variants IS NULL OR json_valid(icon_variants)),
  preferences TEXT CHECK (preferences IS NULL OR json_valid(preferences)),
  interval TEXT,
  digest TEXT CHECK (digest IS NULL OR json_valid(digest)),
  activated_at TEXT,
  preference_values TEXT CHECK (preference_values IS NULL OR json_valid(preference_values)),
  updated_at TEXT NOT NULL,
  UNIQUE (extension_id, name)

CREATE TABLE node_extensions.extension_install_history (
    extension_uuid TEXT PRIMARY KEY,
    first_installed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;

CREATE INDEX node_extensions.idx_extension_install_history_extension_uuid ON extension_install_history(extension_uuid);

CREATE TABLE IF NOT EXISTS %MIGRATION_TABLE_NAME%(
             version %VERSION_TYPE% PRIMARY KEY,
             name VARCHAR(255),
             applied_on VARCHAR(255),
             checksum VARCHAR(255));

CREATE TRIGGER IF NOT EXISTS entities_migration_guard_on_delete AFTER DELETE ON � BEGIN �] END;

CREATE TABLE IF NOT EXISTS %Q.'%q_stat'(id INTEGER PRIMARY KEY, value BLOB);```

### 2.3 Indexer content DB schema [O] (indexer.node, `index/src/db/schema.rs`)

```sql
CREATE TABLE documents (uri TEXT PRIMARY KEY, content_type TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'manual',
  text_content BLOB /* zstd-compressed */, metadata TEXT /* json: content_hash, extraction, is_non_local, page_count */,
  created_at TEXT NOT NULL, lastused_at INTEGER /* + modified_at added later */);
CREATE VIRTUAL TABLE documents_fts USING fts5(uri, text_content, content='', contentless_delete=1, detail=none);
CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN DELETE FROM documents_fts WHERE rowid = old.rowid; END;
-- plus embeddings / embedding_metadata tables (semantic, AI)
```

Content search ranks by bm25 plus prefix matching. Recency is `max(modified_at, lastused_at)`, where lastused comes from the `com.apple.lastuseddate#PS` xattr.

---

## 3. Native modules

### 3.1 data.darwin-arm64.node (30 MB, Rust/napi-rs 3.14) [O]

The bulk of the file is code: `__text` is 23 MB (SQLite + SQLCipher, sync agent, rustls, tokio, ICU).

It exports these classes:

- **Repositories**: `ClipboardRepository, SnippetsRepository, QuicklinksRepository, NotesRepository, EmojiRepository, FrecencyRepository, SettingsRepository, AppIndexRepository, CalculatorRepository, CurrenciesRepository, WindowManagementRepository, FocusCategoriesRepository, UserActivityRepository, UserDefaultsRepository, NodeExtensionsRepository, ScreenshotsRepository, ContactsRepository, AppleShortcutsRepository, AppMenuBarItemsRepository, WindowsRunCommandsRepository, TranslateCustomCommandsRepository, OrgPacksRepository, PendingTokensRepository, AiRepository, AiRunsRepository, AiToolUsageRepository, AiPickerUsageRepository`
- **Other classes**: `DatabaseClient, DatabaseSnapshot, SyncAgent, createCloudSyncConnection`
- **Enums**: `ContentType, ClipboardSourceHost, KeyboardShortcut*, HyperKeyCode, GeneralSettingsColumn, DatabaseKind, Platform, …`

Crates: `rusqlite(fork), serde_rusqlite, refinery, tokio, hyper 1, rustls 0.23 + rustls-platform-verifier, yawc (websocket), ring, ulid, uuid, time, regex, unicode-normalization/segmentation, zstd, bs58, nom`.

**Embedded dataset** [O]: one compact JSON array of **2,736 emoji/symbol records**, `{"s":symbol,"c":category,"n":name,"a":[aliases],"k":[keywords],"u":unicodeVersion}`. Categories and counts: smileys_people 559, animals_nature 160, food_drink 131, activity 85, travel_places 219, objects 266, symbols 224, flags 270, unicode_symbols 822. This seeds `emoji.db`; a checksum table detects reseeding.

There are no currency, unit or app datasets in data.node. Currencies are fetched from the Raycast API (`GET currencies`, `currencies/crypto`) into `main.currencies(code, usd_rate, currency_type)`.

Keyboard model [O]: `KeyboardShortcutV1::{LayoutDependent, LayoutIndependent, ModDoubleTap, MultiStep}`, `SingleKeyShortcut::{Key, Modifier, Modifiers}`, keys `caps_lock, left_/right_{control,shift,option,command}, f1–f24, Numpad*, Arrow*…`. Hotkeys are stored as JSON in `settings_v2.commands.macos_hotkey` / `windows_hotkey`.

### 3.2 indexer.darwin-arm64.node (14 MB, Rust) + "Raycast Content Indexer" (Mach-O arm64 helper) [O]

- **No tantivy.** Filename search uses Raycast's own **`minidex`** crate (git dep `minidex-17c333fe7363231a`).
  - It is an LSM-style segmented index: `memtable`, `wal` (`journal.wal`, `.flushing.wal`), `segmented_index` with background `compactor`, `tombstones` (incl. prefix tombstones), and an FST via the **`fst` 0.4.7** crate.
  - Search lives in `search/{matching,scoring,scratch}.rs` with a SIMD tokenizer.
  - Normalisation is "minidex normalization", where `café` matches `cafe`, with CJK segmentation.
- Crawling uses `walkdir`, `ignore`/`globset` (gitignore-aware, `CACHEDIR.TAG`, `!node_modules`, `*.tmp`), and `notify` (FSEvents with poll fallback, replays dropped events from FSEvents history). The volume watcher handles mount/unmount, there is a "churn hotspot" auto-exclusion, and low-disk/low-power pauses.
- **Content extraction** runs in a separate process ("Raycast Content Indexer", `extractionWorkerPath`) for crash isolation, with a strike/quarantine list. Extractors:
  - `oxidize-pdf` (PDF, JBIG2/DCT)
  - `zip` + `quick-xml` (docx/xlsx/pptx; `extraction/src/extractor/docx.rs`)
  - `rtf-parser`
  - `image`/`tiff`/`exr`/`png`/`zune-jpeg` + **Apple Vision OCR** (`objc2-vision`, `ocr/macos.rs`, `recognizeText`)
- Exported API [O]: `IndexerClient`, `classifyPaths`, `recognizeText`, enums `SearchKind, SearchSorting, WalkPace, EntrySource, IndexFilesState, NtfsScannerState`, `CONTENT_TYPE_{APP,ARCHIVE,AUDIO,DOCUMENT,IMAGE,NOT_APP_NOR_PREFERENCE,OTHER,PREFERENCE,TEXT,VIDEO}`.
- The indexer DB uses refinery + rusqlite FTS5 (schema in 2.3). The semantic queue/backfill is AI.

**Linux replacement:**

- Crawl with the `ignore` crate and watch with `notify` (inotify; for whole-disk watching use **fanotify**, as Tracker/plocate do).
- Use the `fst` crate for a filename index, or simply SQLite FTS5 with a trigram tokenizer. **plocate**/**fsearch** are reference designs.
- Extract content with `pdf-extract`/poppler (`pdftotext`), `zip`+`quick-xml`, and **tesseract** (`leptess`) for OCR.
- Alternatively, delegate to **GNOME LocalSearch/Tracker3** over D-Bus (SPARQL) or **KDE Baloo**.

### 3.3 Calculator [O]

- `calculator-worker.mjs` loads **`Calculator.node`**, a Swift NodeAPI wrapper (`node_swift_register`). It links `@rpath/libCalculator.dylib` and **SoulverCore.framework** (mac-only, proprietary).
  - Its API: `new Calculator({datePicker, locale, rates, remToPxRate, workHoursPerDay})`, then `.calculate / .calculateInBackground(expr) / .updateRates / .supportedCurrencies() / .takeMissingCurrencyRates()`.
- **`calculator-rs.darwin-arm64.node`** is Raycast's **own Rust re-implementation**. Exports: `Calculator, localeCalendarSamples, parseFlightDesignator`. Crates: `rust_decimal 1.43, jiff 0.2, icu_calendar 2.3`.
  - Modules `calculator/core/src/{lexer, tokens, parser, eval, engine, formula, units, currencies, dates, calendar, format, constants, inflation, places, place_expression, travel_time, flight, weather_expression, provider, config}.rs`.
- On macOS both engines run. JS writes mismatches to `LOGS_DIR/calculator-shadow.jsonl`, comparing `evaluation.type`, `description`, `request.metadata.type`, token types/subtypes, and numeric results with 1e-9 relative tolerance (`l2r`/`f2r`). On Windows calculator-rs is the engine.
- Config passed: `locale, datePicker, remToPxRate, workHoursPerDay, decimalSeparator, groupingSeparator, timeZone`.
- History: `calculator_history` with a cap of **4096 rows** (`deleteExceedingLimit(4096)`).

**Linux:** calculator-rs is not open source and is not built for Linux. Options:

- **libqalculate** (Qalculate!, the closest to Soulver: units, currencies, dates, natural-ish language), via FFI or by spawning `qalc -t`.
- **fend** (Rust crate, units/currency, embeddable).
- **numbat** (Rust, strong units).

Get currency rates from ECB / frankfurter.app or exchangerate.host, cached into a `currencies` table with the same schema.

### 3.4 Other modules [O]

- **fs-utils.darwin-arm64.node** (Rust): `checkVolumesAvailability, classifyScreenshot, getFilesystem, getVolumeName/Root/Type, isOnlineOnly (iCloud placeholders), isPackage (.app bundles), liteIsDirectory, liteMetadata, prepareModelImage, readDirectoryWithoutMaterializing, setHidden, VolumeEventWatcher`.
  - Linux equivalent: `statvfs`, `/proc/self/mountinfo`, udisks2 D-Bus for mounts, `image` crate.
- **process-utils.darwin-arm64.node**: `adoptChildProcesses` (reparenting extension child processes).
  - Linux equivalent: `prctl(PR_SET_CHILD_SUBREAPER)` + `PR_SET_PDEATHSIG`.
- **build/better_sqlite3.node**: better-sqlite3 built against SQLite3MultipleCiphers, used for the Classic importer only.
- **build/macos_export_certificate_and_key.node**: exports keychain certs for proxy/TLS (`additional_certificate_authorities`).
  - Linux equivalent: read `/etc/ssl/certs` and use `rustls-native-certs`.
- **mcp-client-sdk.cjs**: MCP client (AI, skip).

---

## 4. Root search ranking algorithm [O]

All of this is in `index.mjs`. Minified names are given so the code can be re-checked. The pipeline is:

1. Providers produce candidates.
2. `jYi.resolveCandidates` attaches `metadata = {alias (lowercased), frecency: score ?? 1, openedAt, favoriteOrder, fallbackOrder, searchTerms, …}`.
3. `IXi` builds sections.
4. `cXi` sorts within each section.

### 4.1 Sections [O]

- Empty query, in order: `announcements, updates, agents, calendar, walkthroughs, focus, development, favorites, <suggestions>, commands, apps, preferences, files`.
- With a query: `color, calculator, flight, weather, agents, translate, results, files, fallback-commands`.

Each command's `rootSearch` config has:

- `when`: `empty` | `searching` | `always`
- `matching`: `always` | `url` | `file-path` | normal
- `pinned` priority
- `alwaysMatching`

### 4.2 Text normalisation [O]

- `nf(s)` returns `{normalizedText: s.toLowerCase(), wordBoundaries}`. A boundary is marked at index n when char n-1 is `[a-z0-9]` and char n is `[A-Z]` (camelCase).
- Separator set `sf`: `\t \n space - . / ( ) [ ]`.
- Titles are transliterated to ASCII (`transliteratedSearchTerm`).
- `JYi`: if the query starts with `/`, the first `/` in the title is replaced with a space.

### 4.3 Fuzzy matcher `af(target, query, {literalQueryDots})` [O]

Returns `"exact"`, `"unmatched"`, or `{score, skipped}`.

1. If `target == query`, return `exact`.
2. Let `sepCount` be the number of separator chars in the query (`.` is not counted when `literalQueryDots`). Let `u = query.length - sepCount`. If `u > target.length`, return `unmatched`.
3. If `u > 2`, do a quick subsequence precheck: every non-separator query char must appear in order in the target. A separator in the query skips one separator in the target if one is present. If the precheck fails, return `unmatched`.
4. Run the DP with a two-row rolling matrix (`W7e`). Row = query char, column = target index. `d` is the first matched column of the previous row (initially -1). `p` is the number of rows matched so far.
   - For each query char `t` (row), search columns `e ∈ [d+1, target.length - (u-1-p))`.
     - A cell **matches** if `target[e]==t`, or if both are separators (a "sep-match").
     - **Per-match score**:
       - sep-match: 1
       - first row and `e==0`: 4
       - otherwise `X7e`: 3 if `e` is a word start (camelCase boundary, or `target[e-1]` is a separator) and `target[e]` is not a separator; else 2
     - **First row**: `cell = score`.
     - **Later rows**: `cell = max over r in [d, e) of prev[r] + score - (r == e-1 ? 0 : 1)`. A non-adjacent jump costs 1.
   - If the row matched anything, set `d =` its first matched column and `p++`.
   - If nothing matched:
     - when the query char is a separator, set `skipped++` and drop the row (unless it is the last row);
     - otherwise return `unmatched`.
5. Return `{score: max(last row), skipped}`. `of()` maps `exact` to +MAX_SAFE, `unmatched` to -MAX_SAFE, and a match to its score.

**Acceptance threshold** `rf(match, queryLen, sensitivity)` (setting `root_search_sensitivity`, default `medium`):

- `low`: any non-unmatched result passes.
- `medium`: `score >= 1.5*(queryLen - skipped - 2) + 4`.
- `high`: `score > 2*(queryLen - skipped)`.

### 4.4 Per-candidate ranking record `iXi` [O]

- `alias`: `J7e(alias, query.lower())`. `exact` if equal, `prefix` if the alias starts with the query and is longer, else `unmatched`.
- `isBoostedSearchTerm`: hard-wired query to command map `dXi`:
  - Notes "open" for `notes`
  - Focus "start" for `focus`
  - AI Chat for `ai` / `chat`
- `title` = `af(title, translitQuery, literalDots)`. `titleMatch` = `exact`, else `prefix` if the title or any alternate title starts with the query.
- `alternateTitles` = `af` on each, with the lowercased query.
- `subtitle` is matched only if it differs from the title.
- `keywords` (lazy) = the command keywords, plus `"title subtitle"` and `"subtitle title"` concatenations. An app's bundle ID is a keyword only when the query contains a `.`.
- `searchTerms` (lazy, `Y7e`): learned search terms, i.e. queries previously used to launch the item, stored in `frecency.root_search.search_terms`.
  - They count only if the item's frecency > 1 and it was opened within **17 days** (`fXi = 1,468,800,000 ms`).
  - For each stored term `s`: `exact` if `s == q`; `prefix` if `s` is longer and starts with `q`; `overbounds{count}` if `q` starts with `s`, and only if the leftover `q.length - s.length` is between 1 and 3.
  - The best is kept (exact > prefix > overbounds with larger count).
- `isMatching = alwaysMatching || alias != unmatched || rf(title) || any rf(alternate) || rf(subtitle) || any rf(keyword)`.
- **Title boost** `$Yi`/`eXi`, applied when the lowercased query is 3 or more chars with no whitespace:
  - If the title is not exact and the query occurs in the title as a whole word (bounded by start/end/separator/camelCase on both sides, `q7e`), raise the title score to at least `4 + (n-1)*2 + 0.5`.
  - An exact alternate title sets `titleMatch=exact`. Otherwise the title score becomes the max of the title and alternate-title scores.

### 4.5 Ordering `cXi` [O]

- **Empty query**:
  - First, items with a pin priority, ordered by `pinPriority` ascending, then `B4`.
  - Then the rest by `B4`.
- **Query present**: matched candidates go into 4 buckets, concatenated in this order:
  1. pinned matched, sorted by `pin` then `sXi`
  2. pinned always / file-path matches, sorted by `pin` then `B4`
  3. unpinned matched, sorted by `sXi`
  4. unpinned always-matching, sorted by `B4`

**`B4(a, b)` tiebreak**:

1. frecency descending
2. items with an alias first
3. type priority `VYi` descending:
   - application 5
   - view/no-view/AI-extension commands 4
   - quicklink 3
   - menu-bar command 3
   - preference/calendar event/file result/indexing 1
   - contact 0
4. runtime `sortHeuristic` ascending
5. extension title (collator)
6. title (`Intl.Collator(numeric:true, sensitivity:"base")`)

**`sXi(a, b)` main comparator**, evaluated in this order. Where a rule says "frecency desc", that is `b.frecency - a.frecency`.

1. `alias == exact` wins.
2. If some candidate in the bucket has an exact title (`hasExactTitle`) and some has an exact searchTerm: an exact searchTerm wins; if both are exact searchTerms, compare frecency desc.
3. `isBoostedSearchTerm` wins, unless the other item has frecency > 1 and higher frecency.
4. Contact-type items (priority 0) lose, unless they have higher frecency (>1) or a strong match (alias/title prefix/exact, subtitle exact, or searchTerm exact/prefix) that the other lacks.
5. If any exact title exists in the bucket:
   - both exact: compare searchTerm class (exact 3 > prefix 2 > overbounds 1 > none 0, then larger overbounds count), then frecency desc, then `B4`;
   - otherwise the exact title wins.
6. Exact searchTerm wins; if both, frecency desc then `B4`.
7. Exact subtitle wins; if both, frecency desc, then title score, then `B4`.
8. Alias `prefix` wins; then searchTerm `prefix` wins; if both prefix, frecency desc.
9. Overbounds comparison: when either count is 3 or more, the larger count wins. An overbounds match of count 3 or more beats none.
10. `max(titleScore, subtitleScore)` descending.
11. frecency descending.
12. title score descending.
13. type priority `VYi`.
14. `sortHeuristic`.
15. title collator.

### 4.6 Frecency [O, decoded from data.node arm64 code at 0x49d644 / 0x50ac04]

Each row in `frecency.root_search` stores `(item_id, frecency_date REAL, search_terms, opened_at)`. `frecency_date` is an **anchor time in seconds**: the score is an exponential decay relative to it. The constants found in code are 86400.0, 0.06931471805599453 (= ln2/10), 100.0 and 709.78 (the exp overflow guard).

```
λ = ln(2)/10   per day        (half-life = 10 days)
score(T)   = max(1, exp(min(709.78, λ * (anchor - T)/86400)))      // T = sampling time (s)
visit(t):  a  = max(anchor_old, t)                                   // NaN-safe
           s  = max(1, exp(min(709.78, λ*(a - t)/86400)))            // current score at t
           s2 = s + 100
           anchor_new = t + 86400 * ln(min(s2, DBL_MAX)) / λ   (if s2 >= 1, else t)
```

- So each launch adds **100** to the decayed score, and the score halves every **10 days**.
- Unvisited items have score 1 (the JS default `c?.score ?? 1`).
- The JS calls `frecency.visit(key, visitDate, searchTerm)`, which also appends the search term and sets `opened_at`.
- The same formula is used for emoji (`emoji.frecencyDate`, recents ordering) [O, same constants at 0x4b7f0c].
- AI tool and picker usage use the "same exponential decay", with `score`/`last_used_at` columns.
- The exact epoch of `frecency_date` (Unix vs 2001 reference) was not confirmed. The Classic importer passes `frecencyDate` through unchanged, but converts `openedAt` with `Date.UTC(2001,0,1) + s*1000` [I: Classic used the Apple 2001 epoch; v2 converts visit dates to seconds through an internal helper].

**Linux:** port 4.2–4.6 directly. It is about 300 lines in Rust or TS. Generic libraries such as `nucleo` or `fuzzy-matcher` would score differently and are not a substitute.

---

## 5. Clipboard history & snippets

### 5.1 Clipboard [O]

- **Capture**: the host watches the pasteboard and calls `clipboard.add({entry:{items:[{representations:[{content, contentType:"text"|"blob"|"url", mimeType}]}], source:{name,url(app path/bundle),host:"MacOS"|"Windows"|"iOS"}, observationId, categories?}})`.
  - `observationId` carries a host+sequence so stale observations are dropped.
  - Universal Clipboard capture is opt-in (`captureUniversalClipboard`, local).
- **Filtering**:
  - Per-app disabled list (`disabledApplications`). The default is Keychain Access.app and Passwords.app.
  - Organisation-disabled bundle IDs.
  - Empty single-text entries are discarded.
- **Dedup**:
  - `contentHash` = **MD5** over the item representations (`lT`).
  - When the hash matches an existing entry, it is updated in place. Representations are merged, categories recomputed, `copyCount++` (only when the observation is new), and `updatedAt` bumped. No new row is created.
- **Categories** (`Jin`), stored in `router_entry_category`:
  - file representation: `file` (plus `image` if the file is an image)
  - image data: `image`
  - text that is a URL: `link` (plus `email` for mailto)
  - colour literal: `color`
  - otherwise `text`
  - `text/uri-list` non-file URLs get a synthesised `text/plain` representation.
- **Large data**: text representations of **30,720 bytes or more** are written to `SUPPORT_DIR/clipboard/file-<md5>.<ext>` and stored as `contentType:"url"` (path). Other blobs are stored the same way (prefixes `file-`, `dyn-`). A maintenance task deletes orphaned cache files.
- **Retention** (`historyDuration`, synced; **default `P1W`**):
  - Values `P1D, P1W, P1M, P3M, P6M, P1Y, unlimited`.
  - Organisations can force `"<N>m"`, where N is a minute count (`organization_clipboard_history_retention_days` is mapped to minutes).
  - The maintenance task runs `deleteAllBeforeDate({date: now - duration, includePinned:false})`. **Pinned entries are kept.**
  - Telemetry buckets "beyondFreeRetention" [I: the free tier caps at 3 months].
- **Other**:
  - OCR on images (`textRecognitionEnabled`, `ocrLevel`, `getTextFromImage` via Vision, `level:"accurate"`) is stored into the representation's searchable content.
  - QR decode is done by the host.
  - There are tags (`router_entry_tag`), per-source-URL filters that auto-apply tags (`filters`, `router_filter_tag`), pins (fractional `pinned REAL` ordering, `movePinnedUp/Down`), and rename/edit.
- **Search**: FTS5 `representations_FTS` plus a **trigram** `representations_tri_FTS` over `content + entry_title`, giving substring search.
- **Paste**: `Q.host.clipboard.placeInClipboard({target:"frontmost"})`. The host writes the pasteboard, re-activates the previous app and synthesises Cmd+V. The option `preferPastingAsPlainText` controls whether rich formats are restored.

**Linux:**

- Watch the clipboard with `wl-paste --watch` / the `wlr-data-control` / `ext-data-control-v1` protocols (Wayland), or XFixes `SelectionNotify` (X11).
- Read all MIME targets to store each representation.
- Paste by setting the selection (`wl-copy`) and synthesising Ctrl+V via `ydotool`/uinput, or `wtype` (virtual-keyboard protocol). On X11 use `xdotool`.
- Get the source app from the focused window (compositor IPC / `_NET_ACTIVE_WINDOW`) to apply the app-disable list.
- Use tesseract for OCR and `rqrr` for QR codes.

### 5.2 Snippets & text expansion [O]

- **Storage**: `main.snippets(id ULID, icon, title, keyword UNIQUE-by-logic, raw_content (ProseMirror JSON), text, copy_count GCounter, pinned, created_at, updated_at, accessed_at)` plus `router_snippet_tag`.
- **Keyword uniqueness** is enforced in JS (`isKeywordAvailable`, "This keyword is already in use").
- **Expansion engine is in the native host.** The backend only pushes `host.snippets.register({snippetIds, keywords})` / `remove`. It does this on create/update/delete and after cloud sync (`Gma`), deduplicating and dropping empty keywords. When an expansion fires, the host or frontend resolves placeholders and pastes.
- **Expansion settings** (internal extension `snippets`):

  | Setting | Default | Notes |
  |---|---|---|
  | `expansionMode` | `Immediately` | also `AfterDelimiterKeeping`, `AfterDelimiterDiscarding` |
  | `expandWithinWords` | false | |
  | `injectionDelay` | `None` | |
  | `responseTime` | `Default` | |
  | `overrideSystemSnippets` | false | |
  | `completionSound` | | |
  | `disabledApplications` | | |
  | `paletteInjectionEnabled` | false | local |
  | `autoExpansionEnabled` | | |

- `snippets.autoSnippet({focusedElement})` is an AI/heuristic suggestion feature [I].

**Placeholder language** (`CY` parser, shared by Snippet, Quicklink, AI Command, AI Chat) [O]:

- **General syntax**: `{keyword option="value" option2='v' | modifier | modifier}`.
  - Keywords may contain letters, `.` and `-`.
  - Option values may be bare or quoted with `" ' ` (backtick) `“ ” ‘ ’`, with `\` escapes.
  - A newline aborts a placeholder.
  - `?` fallback chaining exists only behind the `enableFallback` flag (off by default).

| Placeholder | Options | Contexts |
|---|---|---|
| `{cursor}` | none, no modifiers | Snippets only; at most one |
| `{clipboard}` | `offset=N` (Nth previous history item) | all |
| `{uuid}` | — | not in AI command/chat |
| `{selection}` | — | not in snippets unless `enableSelectionInSnippets` |
| `{argument}` | `name=`, `default=`, `options="a, b, title: value"` (comma list with `\` escapes, optional `title:value`) | max **3 distinct** arguments; same `name` reuses position |
| `{date}` | `format="<pattern>"`, `locale=`, `offset="+1d -2h"` (`format` and `locale` are mutually exclusive) | not in AI |
| `{time}`, `{datetime}`, `{day}` | `locale=`, `offset=` | not in AI |
| `{snippet name="Title"}` | required `name` | nested snippets cannot themselves use `{snippet}`/`{argument}`/`{ai}`; no self-reference or cycles |
| `{calculator expression="..."}` | required `expression` | all |
| `{browser-tab}`, `{browser-tab.url}`, `{browser-tab.title}`, `{browser-tab.content}` | `selector="css"`, `format=text\|markdown\|html` (markdown not allowed with a selector) | **not** in Snippets/Quicklinks (AI only) |
| `{ai prompt="..."}` / `{ai command="Title"}` | one of the two | behind a flag; AI |

- **Modifiers** (pipe-chained): `uppercase`, `lowercase`, `trim`, `percent-encode`, `json-stringify`, `raw`.
- **Offset grammar**: `[+|-]<int><unit>`, with units `m` minute, `h`/`H` hour, `d`/`D` day, `M` month, `y`/`Y` year.
- **Deprecated forms that are still accepted**:
  - `{date "format" +1d}`: `date`/`time`/`datetime`/`day` followed by a quoted format and/or offsets.
  - In **Quicklinks**, any unknown `{word}` or `{word:default}` becomes an argument (`SZr`). So legacy `{query}`, `{Query}` and `{Search Term:default}` all act as positional arguments, still limited to 3.

**Linux:**

- **Expansion**:
  - Implement as an **evdev reader** (input group) or an **IBus/Fcitx5 input-method engine**, which is the most Wayland-friendly option.
  - Keep a rolling buffer of typed chars, trie-match the registered keywords, then delete the keyword with backspaces via uinput/`wtype` and paste the expansion.
  - Espanso is a good open-source reference (evdev + uinput, supports the same "after delimiter" modes).
- **Placeholder parser**: port the state machine above. `{date format=…}` uses Unicode/ICU-style patterns [I: Swift `DateFormatter` style]; map them with `icu4x` or `chrono` plus a translator.

---

## 6. Quicklinks [O]

- **Schema** (final): `main.quicklinks(id ULID, name, link, raw_content (ProseMirror JSON, default {"type":"doc","content":[{"type":"paragraph"}]}), icon, open_count GCounter, open_with_macos, open_with_windows, open_with_ios, created_at, updated_at)`, plus `router_quicklink_tag(quicklink_id, tag, updated_at)`.
- Earlier versions had `application_id`/`open_with`, which became per-platform "open with" app IDs.
- **API**: `quicklinks.list/getQuicklink/listLibrary/save/update/delete/deleteAll/move/updateOpenCount/getTags/pin/unpin/movePinnedUp/movePinnedDown`.
- Organisation-shared quicklinks are in `org_quicklinks` with per-user tags in `local_org_quicklink_tags`.
- **Placeholders**: the same `CY` parser with consumer `quicklink`.
  - Typical usage is `{argument name="query" default="…"}` or legacy `{query}` / `{anything:default}`.
  - Also usable: `{clipboard}`, `{selection}`, `{date …}`, `{uuid}`, `{calculator …}` and modifiers.
  - `{browser-tab*}` and `{cursor}` are rejected.
  - URL percent-encoding of argument values by default, with `| raw` to opt out, is [I]: the modifier exists and the documented behaviour matches, but the substitution step is in the frontend or host, not in index.mjs.
- **Root search**: dynamic command `quicklink`, type priority 3. Up to 3 arguments become inline argument fields. Quicklinks can be fallback commands.

**Linux:** open with `xdg-open` / `gio open`, or a specific `.desktop` app via `gtk-launch`/`gio launch` (stored in an `open_with_linux` column).

---

## 7. Other services, briefly

- **App discovery**:
  - `app_index.app(name, path, localizedName, raycastId, applicationId, contentType 0=App 1=Preference 2=Game, bundleName, alternateNames JSON, keywords JSON (CFBundleAlternateNames + kMDItemKeywords), executionAlias, executableName, anchor, user content type override)`.
  - Populated by the indexer + host `applications.getAllInstalled`.
  - **Linux:** parse `.desktop` files from `$XDG_DATA_DIRS/applications` (`freedesktop-desktop-entry` crate) using `Name`, `GenericName`, `Keywords`, `Exec`, `Icon`, and settings panels (gnome-control-center / systemsettings `.desktop` with `Categories=Settings`). Watch the directories with inotify.
- **Script commands** [O]:
  - Metadata regex `^(?:#|REM|::|//)\s*@raycast\.(\w+)\s+(.*)` (case-insensitive keys).
  - Required: `schemaVersion 1`, `title`, `mode`.
  - Modes: `fullOutput | compact | silent | inline` (inline requires `refreshTime`).
  - Optional keys: `packageName` (default: title-cased parent dir), `icon`, `iconDark`, `description`, `author`, `authorURL`, `currentDirectoryPath`, `needsConfirmation`, and `argument1..3` (JSON `{type, placeholder, optional, secure, percentEncoded, data}`).
  - The shebang is parsed, including the `/usr/bin/env -S` form. `.template.` files and online-only files are skipped.
  - This works as-is on Linux.
- **Window management**:
  - Layouts are stored as `(position, size, offset TEXT, z_position, source, display_index)` per group. Execution is done by the frontend/host via `setWindowBounds`.
  - **Linux:** compositor IPC (Hyprland `hyprctl`, sway IPC, KWin scripting D-Bus, GNOME Shell extension) or X11 EWMH (`wmctrl`/`xdotool`).
- **Emoji picker**:
  - FTS5 over name, aliases, keywords and custom keywords. Uses the same frecency anchor, pins and skin tones.
  - **Linux:** Unicode CLDR annotations / emojibase data.
- **System commands**: all go to host `system.*` / `media.*`. **Linux:** logind D-Bus (lock, sleep, logout, hibernate), MPRIS/playerctl, PipeWire `wpctl`, NetworkManager/rfkill, BlueZ, `xdg-desktop-portal` Settings for the dark-mode toggle.
- **Calendar**: host EventKit for local calendars plus Google/Outlook OAuth accounts through the Raycast API (`calendars.connectAccount`). **Linux:** Evolution Data Server D-Bus, or CalDAV (via `khal`/`vdirsyncer` data).
- **Focus**:
  - `focus_categories(kind builtin|custom, website_hosts_json, application_ids_json)`. Sessions are driven by the host (`raycastFocus.*`), and stats go to `user_activity.user_focus_activity`.
  - **Linux:** block apps by monitoring and killing processes, and block websites through the browser extension.
- **Settings**:
  - `settings_v2.general_settings` (singleton id `0000000000GENERA1SETT1NGS0`).
  - Per-built-in-extension JSON in `internal_extensions.{synced_meta, local_meta, macos_synced_meta, windows_synced_meta}`. Each preference is declared with `Cg({default, storage:"synced"|"local"|"platform"})`.
  - Per-command data in `settings_v2.commands`, including `alias` and `macos_hotkey`.
- **Hotkeys**: registered by the host (`hotkey.register` / `replaceCommandHotkeys`). **Linux:** `xdg-desktop-portal` GlobalShortcuts (KDE, GNOME 48+, Hyprland) or compositor binds that call a CLI/socket; XGrabKey on X11.
- **Import/export `.rayconfig`** [O]:
  - Container layout: `"RAYCFG3\n"` magic, `u32le` header length, gzip(JSON header), then a gzip payload stream.
  - With a password, the payload is encrypted with **AES-256-GCM**. The key is `scrypt(password, salt16, 32)` and the IV is 16 bytes. `{iv, salt}` are hex in the header, and the 16-byte auth tag is appended at the end.
  - Older classic exports used `aes-256-cbc`.
  - Payload sections cover clipboard, emoji, root-search frecency/aliases/hotkeys, snippets, quicklinks, notes, settings, etc. (`schemaVersion` per section).
- **Notes**: `main.notes(id ULID, title, text, raw_content ProseMirror JSON, pinned, created_at, updated_at, deleted_at (soft delete/trash, purgeOldDeletedNotes), last_accessed_at)`. Attachments are cached (`notes.saveAttachment/retrieveCachedAttachment`).

---

## 8. Caveats / unknowns

- The exact SQLite cipher configuration (SQLCipher v4 defaults vs sqlite3mc AES-256) used by data.node was **not** confirmed. Only "encrypted, keyed via `ATTACH … KEY ?`, 64-hex key" is observed. Using your own cipher choice is fine for a clone.
- The role of the `last_key` file was not determined (it was not read).
- The epoch of `frecency_date` (Unix seconds vs 2001 reference) was not confirmed. The formula is unaffected as long as `t` and `anchor` share an epoch.
- The final substitution step for placeholders (including quicklink URL encoding) happens outside `index.mjs`.
- **REA**: an attempt to open `data.darwin-arm64.node` in Hopper (through REA) timed out during initial analysis. `close_binary` reported `cleanup_incomplete`: the Hopper process (PID 3948) and `/tmp/rea-FRMFwj` were still present when this was written. The frecency constants were instead decoded with `objdump`. You may want to quit Hopper manually.

Working files (scratch):

- `…/scratchpad/work/schema.sql`: all DDL, including AI
- `…/scratchpad/work/schema-nonai.sql`
- `…/scratchpad/work/methods.txt`: all 735 RPC methods, including AI
- `…/scratchpad/work/data.dis`: data.node disassembly
