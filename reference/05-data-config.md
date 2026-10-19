# 05: Raycast 2.8.2 on-disk footprint, storage formats and config

Target: `/Applications/Raycast.app` (Raycast 2.8.2.0, bundle id `com.raycast.macos`, Team ID `SY64MV22J9`, internally named "Raycast X" / "raycast-x"). The install is fresh: all user data is timestamped 2026-10-19 12:43, so the data stores are mostly empty.

Legend: **[O]** = observed directly on disk, in a binary or in the JS bundle. **[I]** = inferred from code or strings, not verified at runtime.

Privacy: the record below covers schemas, layouts, key names and counts only. No clipboard, note, snippet, token or key material was read or copied. Every Raycast DB is encrypted, so no row data could be read anyway.

---

## 0. Architecture recap (relevant to storage)

| Component | Path in bundle | Role |
|---|---|---|
| `Contents/MacOS/Raycast` | Swift/AppKit host | Native UI host. Owns the Keychain and the DB key, Sentry-cocoa, NSUserDefaults, and the WKWebView frontend. [O] |
| `Contents/Frameworks/libraycast_host.dylib` | Rust | Host↔backend bridge. Sends the bootstrap JSON `{databaseKey, signatureSecret, releaseApiToken, posthogApiKey}` to the backend. [O] |
| `.../RaycastDesktopApp.bundle/Contents/Resources/backend/index.mjs` (7.1 MB) | Node ESM bundle | The backend (business logic, exporter, extension host, analytics, Sentry-JS). It runs on a Node runtime that is copied to `~/Library/Application Support/com.raycast.macos/node/runtime/node-v22.23.3-darwin-arm64/`. [O] |
| `backend/data.darwin-arm64.node` (29 MB) | Rust napi (`data/core`, `data/node`, `sync/agent`, `sqlite-encryption` crates; rusqlite + refinery) | **All local databases**: schema migrations, encryption, backups, Cloud Sync agent. [O] |
| `backend/build/better_sqlite3.node` | better-sqlite3 built with SQLite3MultipleCiphers | Used only to read **Raycast v1 ("Classic")** SQLCipher DBs during migration. [O] |
| `backend/indexer.darwin-arm64.node`, `Raycast Content Indexer`, `indexer-worker.mjs` | Rust | File search index ("minidex"). Also an optional semantic index (`semantic.db`, jina-clip-v2). [O] |
| `backend/calculator-rs*.node`, `Calculator.node`, `SoulverCore.framework` | | Calculator. [O] |
| `.../Resources/api/node_modules/@raycast/api` (index.js 740 KB), `api/template/` | | Extension runtime API and the new-extension template. Symlinked into `~/.config/raycast/extensions/node_modules`. [O] |
| `.../Resources/frontend/` | Vite-built JS/CSS | UI rendered in WKWebView (not Electron). [O] |
| `Contents/XPCServices/Raycast Accessibility.xpc`, `Raycast Pasteboard.xpc`; `Contents/Library/Helpers/Raycast Palette.app` | | Helpers. [O] |
| `Contents/Resources/Updater`, `UpdaterDaemon` | | Self-updater (SMAppService LaunchAgent and LaunchDaemon). [O] |

---

## 1. All Raycast locations on disk [O]

| Path | Size | Purpose |
|---|---|---|
| `~/Library/Application Support/com.raycast.macos/` | 120 MB (108 MB is the bundled Node runtime) | `SUPPORT_DIR`: DBs, key hash, index, node runtime, per-extension support dirs |
| `~/Library/Application Support/.com.raycast.macos.backups/` | 2.2 MB | Versioned DB backups (see §3.5) |
| `~/Library/Application Support/com.raycast.shared/HyperKey/pid` | 0 B dir + pid | Hyper Key helper PID file |
| `~/Library/Caches/com.raycast.macos/` | 152 KB | `CACHE_DIR`: `releases-changelog/changelog.json`, `WebKit/` (NetworkCache, HSTS, CacheStorage, AlternativeServices sqlite), `async.log` (empty), `clipboard/` (image cache, created on demand) |
| `~/Library/Caches/com.raycast.macos.pasteboard/async.log` | 0 B | Pasteboard XPC log stub |
| `~/Library/Caches/io.sentry/<sha1>/{session.current,envelopes/}`, `~/Library/Caches/SentryCrash/Raycast/{Data/CrashState.json,Reports/}`, `.../SentryCrash/Raycast Pasteboard/` | 16 KB | Sentry-cocoa offline queue and crash state |
| `~/Library/WebKit/com.raycast.macos/WebsiteData/` | 616 KB | WKWebView data: LocalStorage, IndexedDB, ResourceLoadStatistics (`observations.db`, `pcm.db`), MediaKeys, salts |
| `~/Library/Logs/com.raycast.macos/` | 52 KB | `raycast-x-YYYY-MM-DD HH.MM.SS±ZZZZ.log` (one per launch), `Raycast-Production-Backend-Fallback.log` |
| `~/Library/Preferences/com.raycast.macos.plist` | 4 KB | NSUserDefaults (keys in §6) |
| `~/.config/raycast/` | ~0 | `extensions/` (installed extensions; `node_modules` → symlink into the app's `api/node_modules`). The code also uses `ai/`, `skills/`, `node-compile-cache/`. Legacy `~/.config/raycast-x` is migrated into it, and an old v1 dir is renamed to `~/.config/raycast.v1-backup`. |
| Login Keychain: generic password `svce=com.raycast.macos`, `acct=database_key_backup` | | Backup copy of the DB key. Only the attributes were listed; the secret was not read. |
| Data-protection Keychain, access group `SY64MV22J9.com.raycast.shared` | | Primary DB key, plus other shared items (accounts `database_key`, `export_passphrase`, device-tag fallback seed). v1 migration reads `classic_database_key`, `classic_export_passphrase` and `classic_oauth_token`. Store credentials go under service `raycast-store_credentials` (`raycast-staging-…` / `raycast-development-…` for other envs). [O strings] |
| LaunchAgent `com.raycast.macos.updater` (`Contents/Library/LaunchAgents/Updater.plist`) and LaunchDaemon `com.raycast.macos.updater.daemon` | | Bundle-embedded (SMAppService). Nothing is installed in `~/Library/LaunchAgents`. |
| Not present | | `~/Library/Application Support/com.raycast-x.macos`, `~/Library/Containers/*raycast*`, `~/Library/Group Containers/*raycast*`, `~/Library/HTTPStorages/com.raycast.macos`, `~/Library/Saved Application State/*raycast*` |

### 1.1 `SUPPORT_DIR` tree (fresh install) [O]

```
com.raycast.macos/
├── main.db (+-wal,-shm)            2.9 MB WAL   ← primary DB; others are ATTACHed to it
├── ai.db                           3.2 MB WAL
├── app_index.db                    222 KB WAL
├── clipboard.db                    519 KB WAL
├── emoji.db                        812 KB WAL   (seeded emoji catalog)
├── frecency.db                     107 KB WAL
├── node_extensions.db              218 KB WAL
├── screenshots.db                  49 KB WAL
├── settings.db                     49 KB WAL    (older settings schema, superseded by settings_v2)
├── settings_v2.db                  1.2 MB WAL
├── user_activity.db                115 KB WAL
├── last_key                        64 bytes binary (hash of the DB encryption key, see §3.3)
├── SingleInstance.lock             text PID
├── clipboard/                      (image/file blobs for clipboard history; empty)
├── index/
│   ├── version                     "minidex-6"
│   ├── category-rules              "1"
│   └── db/{journal.wal,.minidex.lock}
└── node/
    ├── backend.pid                 text PID of the Node backend
    └── runtime/node-v22.23.3-darwin-arm64/bin/node   (113 MB, copied from bundle)
```
Paths the code references that do not exist yet [O code]: `extensions/<uuid|name>/` (per-extension supportPath), `sync_agent.db`, `semantic.db`, `index/{watch.json,semantic-queue.json,semantic-backfill.jsonl,semantic-behind}`, `ai-local-attachments/`, `note-attachments/`, `dictation-recordings/`, `dictation-session-context/`, `memory-history/`, `team-skills/`, `quotes/`, `cloud-sync/settings-snapshots/`, `updates/`, `update-marker.json`, `installer.dmg`, `.vm-database-key` (test override: 64 hex chars, mode 600), `.vm-auth-session.json` (VM test mirror of the OAuth token, disabled in production).

---

## 2. Database engine and encryption

### 2.1 Observations [O]
- None of the 11 `*.db` files starts with `SQLite format 3\0`. The first 16 bytes are random, and `sqlite3` reports "file is not a database" on read-only copies (inspected in a scratch copy that was then deleted).
- The `-wal` files have a **plaintext WAL header** (magic `377f0682`, page size 4096). Page 1 inside the WAL shows random bytes 0–15, **plaintext bytes 16–23** (`10 00 02 02 0c 40 20 20`: page size 4096, file format 2/2, **reserved bytes per page = 12**), and ciphertext after that.
- The Rust `data` module contains the SQLite compile-option and algorithm table `rc4|aes128|aes256|aes128ofb|aes256ofb|aes256gcm|AesGcm1` and the pragmas `key/hexkey/textkey/rekey/hexrekey/textrekey`, which is the **SQLite Encryption Extension (SEE)** signature. There are no SQLCipher `cipher_*` pragmas.
- The SQL strings used are `ATTACH DATABASE ?1 AS ?2 KEY ?3`, `pragma_update_key`, `pragma_rekey`, `vacuum_after_rekey`, `write_encryption_key_hash`, `write_default_key_marker`, "No database exists and no encryption key provided, using default key", "Rekeying database from default key to user-provided key", and `sqlite-encryption/src/lib.rs`.

### 2.2 Conclusion
- **[I, high confidence]** Raycast X DBs use **SEE with AES-256-OFB**: a 12-byte per-page nonce in the reserved area, with page-1 bytes 16–23 left in clear. These are SEE's default behaviours. SEE is proprietary, so a Linux clone cannot read these files directly and should not try. Migrate through `.rayconfig` export instead (§5).
- Raycast **v1 ("Classic")** DBs were **SQLCipher v4**. They are opened in `index.mjs` with `cipher='sqlcipher'`, `legacy=4`, `key='<hex>'`, where `hex = sha256(classic_database_key_from_keychain + <hard-coded app salt string>)`. [O] (The salt constant exists in `index.mjs` and is deliberately not reproduced here.)

### 2.3 Key management [O strings / I flow]
1. The host (`Raycast` Swift binary, `resolveDatabaseKey()`) reads a 32-byte key (64 hex) from the **data-protection Keychain, access group `SY64MV22J9.com.raycast.shared`**. It falls back to the login-keychain backup (`com.raycast.macos` / `database_key_backup`) and sets `raycast_databaseKeyBackedUp` in defaults. A `.vm-database-key` file overrides the key for tests.
2. If no key exists, it generates one ("Creating database key…"). DBs created before a key existed use an **embedded default key** and are rekeyed onto the real key ("Database uses the default key, creating a database key to rekey it onto").
3. The key is passed to the Node backend in the bootstrap payload (`databaseKey`), and from there to `new DatabaseClient(SUPPORT_DIR, encryptionKey, logger)` in the Rust napi module.
4. `last_key` (64 bytes) is **[I]** the stored key hash (`write_encryption_key_hash`). It is used to detect "Encryption key mismatch" and is copied with every backup.
5. Failure paths include `DatabaseKeyUnavailableAlert` ("Raycast is waiting for your keychain", "Allow Keychain access to start Raycast"), key-loss signalling, and `set_aside_unreadable_database` with restore from backup.
6. Logs redact keys with a regex for `ATTACH … KEY …` and `PRAGMA [hex|text][re]key=…` → `[REDACTED]`.

### 2.4 Connection model [O]
`main.db` is opened first. The other DBs are `ATTACH`ed with their schema name equal to the file stem: `ai`, `app_index`, `clipboard`, `emoji`, `frecency`, `node_extensions`, `screenshots`, `settings`, `settings_v2`, `user_activity`. Pragmas are `journal_mode=WAL`, `synchronous=NORMAL`, `foreign_keys=ON`, plus a custom `cache_size`. Custom SQL functions are `RAYDATE`, `RAYDATE_STEP`, `RAYCAST_LOWER`, `RAYACRONYM` and `RAYFIRSTLINE`. Migrations use **refinery** (`refinery_schema_history(version PK, name, applied_on, checksum)`, about 248 `V<n>__<name>` migrations), with a TEMP table `(database_name PK, is_new_database)` for migration context. There is FTS5 everywhere (unicode61 with remove_diacritics 2, plus trigram for clipboard). Cloud Sync adds `cloudsync_trg*` triggers and an `entities` table in `sync_agent.db`.

### 2.5 Schema
The full reconstructed schema (124 tables, about 107 indexes, about 60 triggers) is in the **Appendix**. It was built from the embedded migration SQL in `data.darwin-arm64.node` [I: union of CREATE plus ALTER ADD COLUMN, so table order and the exact final column set may differ slightly]. Key tables for a clone:

- **clipboard** (`clipboard.db`): `entries(id, title, created_at, updated_at, workspace_id, source_name, source_host, …)` → `items(id, entry_id)` → `representations(id, item_id, entry_id, mime_type, content_type, content)`. Also `router_entry_category`, `router_entry_tag`, `filters(source_url, enabled)`, `workspaces`, FTS5 `representations_FTS` and trigram `representations_tri_FTS`. Images are stored as `content_type=url` pointing into the `clipboard/` dir. MIME types include custom `application/vnd.raycast.{rtfd,ocr,url.title,color,font,…}`.
- **snippets / notes / quicklinks** (`main.db`): `snippets(id, icon, title, keyword, raw_content, text, copy_count, pinned, created_at, updated_at, accessed_at, last_modified_at)` plus `router_snippet_tag`; `notes(id, title, text, raw_content, pinned, created_at, updated_at, deleted_at, last_accessed_at, last_modified_at)`; `quicklinks(…, link, application_id, open_count, raw_content, open_with{,_macos,_windows,_ios})` plus `router_quicklink_tag`.
- **settings** (`settings_v2.db`): `general_settings` (hotkey, theme, window mode, pop-to-root, proxy, CA certs, navigation bindings, …), `commands` (per-command enabled, alias, `macos_hotkey`, `windows_hotkey`, favorite/fallback order, `synced_meta`/`local_meta`/`macos_synced_meta`/`windows_synced_meta` JSON), `node_extensions` (per-extension enabled, **`localStorage`**, **`oauthTokens`**, **`storedValues`**, meta JSON), `internal_extensions`, `themes`, `window_modes`, `cloudsync_settings`.
- **extensions registry** (`node_extensions.db`): `extensions(id, uuid, name, title, …, author, owner, version, …)`, `commands(…, mode, preferences JSON, arguments JSON, interval, …)`, `tools`, `widgets`, `extension_install_history`.
- **frecency** (`frecency.db`): `root_search(item_id, frecency_date)` plus FTS5 `root_FTS`.
- **user_defaults** (`main.db`): `user_defaults(key PK, value, created_at, last_modified_at)`. This holds `OAuthTokenResponse`, `CurrentUser`, `AnonymousId`, `InstallationDate`, `FirstKnownVersion`, `ScheduledExport*`, `ClassicMigration*`, `TosAccepted`, `NotesCurrentNoteId`, and others. **The Raycast account OAuth token lives here, inside the encrypted DB, not in the Keychain.** [O code]

---

## 3. Other file formats

### 3.1 Logs [O]
- Location: `~/Library/Logs/com.raycast.macos/raycast-x-<YYYY-MM-DD HH.MM.SS±ZZZZ>.log`, one file per launch. Other names in the binary are `raycast-x-hyperkey-*` and `raycast-x-performance*`.
- Each file starts with a "Raycast Report" header block (Process, Path, Identifier, Version, Date/Time, Launch Time, Hardware Model, OS Version, Memory, CPU, Architecture, Drive Capacity/Free, Time Awake Since Boot, Time Since Wake, plus flags such as `Use Single Web Process`, `Silent Restart`, `Launched at Login`).
- Line format: `[<level> HH:MM:SS.mmm] <emoji> <process> [<thread>] [<category>] <message> {json metadata}`. Levels are trace, debug, info, warning, error and fatal. Processes are `💻 macos-app`, `🔌 macos-node`, `🪟 frontend` and `🧰 macos-utils`. In this first launch's log (978 lines), the counts were about 221 macos-node, 108 frontend, 61 macos-app and 10 macos-utils, plus continuation lines.
- `Raycast-Production-Backend-Fallback.log` uses `[ISO8601] [level] message {json} (pid)` and is written when the backend logs before the IPC logger is up.
- Defaults that control logging: `raycast_errorReporting_{debugLoggingEnabled,logEmoji,logFileEnabled,logTraces,optOut,spotlightEnabled}`, `raycast_enablePerformanceLogs`, `raycast_EnableRootSearchLogs`.

### 3.2 Backups [O]
`~/Library/Application Support/.com.raycast.macos.backups/<appVersion>/<unixMillis>/{*.db,last_key}`, plus `<appVersion>/last_backup` (unix seconds) and the markers `.v2-clipboard-cache-migrated` and `.v2-app-support-migrated`. Backups are online SQLite backups. The code supports a `rekeyed_backup_copy`, and old backups and empty version dirs are cleaned up.

### 3.3 `last_key` [O size / I meaning]
A 64-byte non-text binary file, byte-identical to the copy in the backup. It is most likely a 64-byte hash of the key (for example SHA-512) used for mismatch detection. It is not the key itself, because the key lives in the Keychain.

### 3.4 Minidex file index [O]
`index/version = "minidex-6"`, `index/db/journal.wal`, and a lock file. This is a custom Rust format used by the native indexer and is not SQLite.

### 3.5 Scheduled exports [O code]
`.rayconfig` files named `Raycast-X-<YYYY-MM-DD HH.MM.SS>.rayconfig`, retained for 14 days, max 8 kept. The schedule state is in user_defaults `ScheduledExport*`, and the passphrase is in the Keychain (`export_passphrase`).

---

## 4. Extensions on disk

### 4.1 Layout [O code: `nx()`, `ix()`, `rx()` in index.mjs; no extensions installed yet]
```
~/.config/raycast/extensions/
├── node_modules -> /Applications/Raycast.app/.../Resources/api/node_modules   (@raycast/api, react, react-reconciler, …)
└── <uuid | name>/                       # store extension: uuid; dev/local: name
    ├── package.json                     # manifest (same schema as https://www.raycast.com/schemas/extension.json)
    ├── <commandName>.js                 # one bundled CJS file per command (built by `ray build`)
    ├── tools/<toolName>.js              # AI tools
    ├── widgets/<widgetName>.js          # widgets
    ├── assets/                          # icons/images (environment.assetsPath)
    ├── cli.pid, dev.log                 # only while `ray develop` is running
~/Library/Application Support/com.raycast.macos/extensions/<uuid | name>/      # environment.supportPath
    └── com.raycast.api.cache/           # Cache API storage
        ├── journal                      # text: line1 "1" (version); then "<key with spaces→_> <id> <sizeBytes>" per entry, LRU order
        └── <id>                         # one file per value (utf-8 string)
```
- Store installs arrive as a zip bundle that must contain `package.json` at the root. Size, expanded size and entry-count limits are enforced, and the bundle is extracted to a temp dir and then moved into place. There is an `ExtensionIntegrityCheckEnabled` default. [O]
- The Cache default capacity is 10 MB per extension (`1e7`) with LRU eviction. A backend-side variant uses a 1 GB capacity in `CACHE_DIR`. [O]
- **LocalStorage** is **not a file**. It is a JSON object stored in `settings_v2.node_extensions.localStorage` for the extension's id, so it is encrypted at rest. "Clear Local Storage and Cache" resets that column to `{}` and trashes `<supportPath>/com.raycast.api.cache`. [O]
- **Preferences** live in `settings_v2.node_extensions.*_meta` and `settings_v2.commands.*_meta` as JSON. Routing is: `password` → `local_meta` (never synced, never exported), `file`/`directory` → `macos_synced_meta`, everything else → `synced_meta` (Cloud Sync). [O code `Rb()`]
- **OAuth (PKCE) tokens** for extensions are stored in `settings_v2.node_extensions.oauthTokens`. `storedValues` holds misc state. [O]
- The extension manifest (template `api/template/dist/package.json`) includes `$schema`, `name`, `title`, `description`, `icon`, `author`, `owner`, `license`, `categories`, `commands[] {name, title, subtitle, description, mode: view|no-view|menu-bar, interval, keywords, arguments[], preferences[]}`, `tools[]`, `preferences[]`, `dependencies` (`@raycast/api ^2.6.3`, `@raycast/utils ^2.2.7`), and scripts `ray develop|build|lint|publish`. [O]
- `environment` fields exposed to extensions: `supportPath`, `assetsPath`, `extensionName`, `commandName`, `commandMode`, `launchType`, `raycastVersion`, `ownerOrAuthorName`, `isDevelopment`, `appearance`, `theme`, `textSize`. [O]

---

## 5. `.rayconfig` export/import format [O, index.mjs]

### 5.1 v2/X container (current, `schemaVersion` 3; importer accepts 1, 2 and 3)
```
offset 0   : magic  "RAYCFG3\n"        (8 bytes ASCII)
offset 8   : uint32 LE headerLen        (1 ≤ headerLen ≤ 1 MiB)
offset 12  : header = gzip(JSON)        (headerLen bytes)
then       : payload = gzip(JSON stream)            ← unencrypted
             or AES-256-GCM(gzip(JSON stream))      ← encrypted
last 16 B  : GCM auth tag               (only if header.encryption present)
```
- Header JSON: `{exportedAt (ISO), appVersion, osName, osVersion, osArch, schemaVersion: 3, encryption?: {iv: hex(16 bytes), salt: hex(16 bytes)}}`.
- KDF: `key = scrypt(password, salt, 32)` using Node's default scrypt parameters (N=16384, r=8, p=1). Cipher: `aes-256-gcm`, 16-byte IV, 16-byte tag appended at EOF. The pipeline is gzip → encrypt.
- Writes go to `<file>.<6 random bytes hex>.part`, then rename.
- Payload is one top-level JSON object streamed per category key: `ai`, `clipboardHistory`, `emoji`, `focusCategories`, `mcpServers`, `nodeExtensions`, `notes`, `quicklinks`, `settings`, `snippets`, `userActivity` (labelled "Raycast Wrapped"), `windowLayouts`. Each category value carries its own `schemaVersion`.
  - `clipboardHistory`: `{clipboardEntries:[{title, items:[{representations:[{content, contentType: text|blob|url, mimeType}]}], categories[], tags[], source?{name,url,host:MacOS|Windows|iOS}, pinned?, copyCount?, contentHash (md5 of mimeType+content), createdAt?, updatedAt?}], schemaVersion:1}`. Image entries whose file URL is missing are skipped on import.
  - `emoji`: `{emojis:[{symbol, customKeywords[], frecencyDate?, pinned?}]}`.
  - `nodeExtensions`: `{extensions:[{uuid, name, author, owner, version}]}`. Import re-downloads these from the Store; extension code is not embedded.
  - `settings`: `{general, commands[], internalExtensions[], nodeExtensions[], frecency[], themes[], anonymousId, installationDate, firstKnownVersion, …}`. **Password-type preferences are stripped.**
  - `ai`: `{chats, requests, messages, transcriptions, modes, commands, transcriptionStyles, folders, models}`.
  - `notes`: `{notes[], images?, schemaVersion}`. `snippets`: `{snippets[], packSnippets?}`. `quicklinks`: `{quicklinks[], packQuicklinks?, openWithPlatforms?}`. `focusCategories`: `{focusCategories:[{title, icon, websiteHosts[], applicationIds[]}]}`.
- Import is selective by category. It pauses Cloud Sync and records restore claims in `ai.sync_restore_*`. Deep link: opening a `.rayconfig` file triggers import.

### 5.2 Classic (Raycast v1) `.rayconfig` (import only)
- If the first two bytes are `1f 8b`, the file is plain gzip JSON.
- Otherwise the layout is `IV(16 bytes) || AES-256-CBC(gzip(JSON))` with `key = SHA-256(password)`.
- The JSON is streamed with top-level keys, then mapped to the categories above.

### 5.3 Classic DB import
This path reads v1 SQLCipher DBs directly (tables such as `aiChats`, `aiChatMessages`, `aiCommands`, `aiChatPresets`, `clipboard`, `emojis`, `focusCategories`, …) using the keychain key described in §2.2. Clipboard history is capped at 50,000 rows.

---

## 6. Preferences plist (`com.raycast.macos.plist`) [O]

- **Present on this machine** (values not recorded): `LifetimeActivityState`, `raycast_AnonymousId`, `raycast_databaseKeyBackedUp`, `raycast_OnboardingCompleted`, `raycast_ShowWindowsImmediately`, `raycast_WelcomeTosAccepted`, `raycast_WindowCacheMode_v2`, and 2 `NSWindow Frame NSSpellChecker…` keys.
- **All `raycast_*` keys in the binary (56):** AIChatAlwaysOnTop, AlwaysShowWelcomeWindowOnStart, AnonymousId, apiCustomBackendURL, apiCustomDictationURL, apiCustomFrontendURL, apiEnvironment, BackendHangDetectorEnabled, databaseKeyBackedUp, debug_simulatedKeychainUnavailableSeconds, DeviceTagFallbackSeed, DisableAsyncOverflowScrolling, DisableWritingTools, EnableAppleShortcutsBatchedFetch, EnableBackgroundWebContentRunningBoardThrottling, EnableMainWindowRepaintRecovery, enablePerformanceLogs, enablePerformanceMetrics, EnableRootSearchLogs, EnableRootSearchPerformanceTracing, EnableSeparatedWebContentExperiment, EnableWebKitProcessRecovery, errorReporting_{debugLoggingEnabled, logEmoji, logFileEnabled, logTraces, optOut, spotlightEnabled}, HasUsedSearchMenuBarItems, HyperKeySecureInputMode, InternalAiChatWindowCacheDuration, internalExtensionSettingsUpdated, InternalLogoVariant, InternalNotesWindowCacheDuration, NSThemeFrame_*, OnboardingCompleted, OnboardingSkipped, PaletteCaretPositionEnabled, ShowWindowsImmediately, SimulateWedgedServiceManagement, TidyMenuBarSupported, useEmbeddedNode, userDefaultsDidChange, WebContentMemoryCleanupMode, WebContentProcessMode, WebKitLifetimeActivityState, WebKitRenderUpdatesNear60Fps, WelcomeResumeStep, WelcomeResumeUserType, WelcomeTosAccepted, window_cachedPosition_*, WindowCacheMode_v2, windowCaptureSaveInExtensionMetadataFolder.
- **Env vars:** `RAYCAST_API_ENVIRONMENT` (production|staging|custom), `RAYCAST_ENABLE_UI_TESTING`.
- **URL schemes:** `raycast://`, `raycast-x://`, `com.raycast://`.

---

## 7. Crash reporting, telemetry and network endpoints (to drop or replace in a clone) [O]

| What | Where | Endpoint |
|---|---|---|
| Sentry (native, sentry-cocoa + SentryCrash) | `MacOS/Raycast` | DSN `(Raycast Sentry DSN, omitted)`. Local queue in `~/Library/Caches/io.sentry`, `~/Library/Caches/SentryCrash/{Raycast,Raycast Pasteboard}` |
| Sentry (backend JS, `@sentry/node`) | `index.mjs` (configured by the host: `enabled, release, userId, sampleRate, tracesSampleRate, spotlight`) | Same org. Extension crashes become Sentry envelopes with password prefs scrubbed, rate-limited once per day |
| Product analytics | PostHog SDK, `host: https://e.raycast.com/` (self-proxied). The key arrives in the bootstrap as `posthogApiKey` | Events such as `export_settings_data` and `Database Size Measured` (clipboard cache size, DB size), plus feature-state observations, trial nudges and identify-by-user |
| Opt-out | `raycast_errorReporting_optOut` | |
| Other Raycast services | `backend.raycast.com`, `oauth.raycast.com`, `www.raycast.com`, `dictation-api.raycast.com`, `*.raycast-releases.com` (updates), `releases.raycast.com`, `manual.raycast.com`, `developers.raycast.com`, `ray.so` | Account, AI, Cloud Sync (WebSocket sync agent), Store, updates |
| Third-party | `api.met.no`, `photon.komoot.io`, `timeapi.io` (weather, geo and time-zone lookups, used by the calculator and by AI), `duckduckgo.com`, `icons.duckduckgo.com`, `www.google.com` (bang list and favicons) | From `InternetAccessPolicy.plist` |

The bootstrap secrets passed from host to backend are `databaseKey`, `signatureSecret`, `releaseApiToken` and `posthogApiKey`. A clone needs only the first, and should generate it locally.

---

## 8. Proposed XDG-compliant Linux layout for the clone

App id example: `raycast-clone` (substitute your own name).

| Raycast macOS | Linux clone | Notes |
|---|---|---|
| `~/Library/Preferences/com.raycast.macos.plist` (UI/host flags) | `$XDG_CONFIG_HOME/raycast-clone/config.toml` | Only user-editable, non-secret host flags (log level, telemetry off, window mode, env). Real settings stay in the DB, as in the original. |
| `~/.config/raycast/extensions/<uuid>/` | `$XDG_DATA_HOME/raycast-clone/extensions/<uuid>/` | Extension code is data, not config. If you want to run Raycast's own `ray` CLI and dev flow unmodified, keep a compatibility symlink `~/.config/raycast → $XDG_DATA_HOME/raycast-clone`. Keep `extensions/node_modules` → the shipped `@raycast/api` shim. |
| `~/.config/raycast/{ai,skills}` | `$XDG_CONFIG_HOME/raycast-clone/{ai,skills}/` | User-authored config |
| `~/.config/raycast/node-compile-cache` | `$XDG_CACHE_HOME/raycast-clone/node-compile-cache/` | |
| `SUPPORT_DIR/*.db` | `$XDG_DATA_HOME/raycast-clone/db/{main,ai,clipboard,emoji,frecency,app_index,node_extensions,screenshots,settings,user_activity}.db` | Keep the ATTACH-by-stem design. Use **SQLCipher 4** or **SQLite3MultipleCiphers** (open source) instead of SEE. Optionally plain SQLite plus full-disk encryption. |
| `SUPPORT_DIR/last_key` | `$XDG_DATA_HOME/raycast-clone/db/key.check` | Store an HMAC or hash of the key for mismatch detection, never the key |
| `SUPPORT_DIR/extensions/<id>/` (supportPath, Cache API) | `$XDG_DATA_HOME/raycast-clone/extension-support/<id>/` with `com.raycast.api.cache/{journal,<id>}` | Keep the journal format byte-compatible with `@raycast/api` |
| `SUPPORT_DIR/clipboard/`, `note-attachments/`, `ai-local-attachments/`, `dictation-recordings/` | `$XDG_DATA_HOME/raycast-clone/{clipboard,notes/attachments,ai/attachments,dictation}/` | |
| `SUPPORT_DIR/index/` (file index), `semantic.db` | `$XDG_CACHE_HOME/raycast-clone/index/` | Rebuildable, so it belongs in cache |
| `SUPPORT_DIR/node/runtime/` | Use system `node` (≥ 22) or `$XDG_DATA_HOME/raycast-clone/runtime/node-vXX/` | |
| `SingleInstance.lock`, `node/backend.pid`, `HyperKey/pid` | `$XDG_RUNTIME_DIR/raycast-clone/{instance.lock,backend.pid,…}` plus D-Bus name `dev.<you>.RaycastClone` for single-instance | |
| `~/Library/Caches/com.raycast.macos/{releases-changelog,clipboard,WebKit}` | `$XDG_CACHE_HOME/raycast-clone/…` (WebKitGTK/Tauri/Electron cache dirs go here too) | |
| `~/Library/WebKit/com.raycast.macos/WebsiteData` | `$XDG_DATA_HOME/raycast-clone/webview/` | |
| `~/Library/Logs/com.raycast.macos/*.log` | `$XDG_STATE_HOME/raycast-clone/logs/raycast-<timestamp>.log` (rotate by count/age), optionally also journald | Keep the key-redaction regex |
| `.com.raycast.macos.backups/<ver>/<ms>/` | `$XDG_STATE_HOME/raycast-clone/backups/<ver>/<ms>/` | |
| Scheduled `.rayconfig` exports | `$XDG_DATA_HOME/raycast-clone/exports/` (or the user-chosen dir) | |
| Keychain `SY64MV22J9.com.raycast.shared` / `database_key`, `database_key_backup`, `export_passphrase` | **libsecret / Secret Service** items with attributes `{application: "raycast-clone", kind: "database_key" \| "export_passphrase" \| "store_credentials"}`, label "Raycast Clone database key" | Fallback when no Secret Service (headless or TTY): a `0600` key file at `$XDG_DATA_HOME/raycast-clone/db/.database-key` (64 hex chars, mirroring `.vm-database-key`), or systemd-creds |
| Extension `oauthTokens`, password preferences, account OAuth token | Keep them in the encrypted DB (like the original), **or** move them to Secret Service under `{application, extension: <id>, kind: oauth\|pref, name}` | Moving them is safer on Linux because a DB key in a keyring is only as strong as the keyring |
| Updater LaunchAgent and LaunchDaemon | Not needed (use the distro package or an AUR PKGBUILD). Autostart via `$XDG_CONFIG_HOME/autostart/raycast-clone.desktop` or a systemd `--user` unit | |
| URL schemes `raycast://` | `.desktop` file with `MimeType=x-scheme-handler/raycast;x-scheme-handler/raycast-clone;` plus `application/x-rayconfig` for `.rayconfig` | |
| Sentry, PostHog (`e.raycast.com`) | Remove. Offer an optional local-only crash dump in `$XDG_STATE_HOME/raycast-clone/crashes/` | |

**Interop recommendation:** implement the `RAYCFG3` reader (§5.1: gzip header, scrypt(N=16384, r=8, p=1, 32 bytes), AES-256-GCM, gzip JSON stream) and the Classic reader (§5.2) so that users can move their data from macOS Raycast into the clone. Direct DB reads are not feasible because the files are SEE-encrypted with a Keychain-held key.

---

## 9. Method notes
- Shell tools only (`strings`, `grep`, `dd`, `python3 -I`, `plutil`, `codesign -d`, `security dump-keychain` attribute listing filtered to account and service names). REA tools were not needed and no REA sessions were opened.
- The DBs were copied to `scratchpad/dbcopy/` and opened read-only there, where they failed as expected because of encryption. The copy dir has been deleted. Raycast was not launched or modified.
- Schema extraction: `scratchpad/parse_sql.py` and `scratchpad/summarize.py` over `data.darwin-arm64.node`. Intermediate output is in `scratchpad/work/` (binary strings and schema JSON only, no user data).

---

## Appendix A: Reconstructed schema (from embedded migrations) [I]

Format: `column:TYPE[flags]`. PK = primary key, NN = NOT NULL, FK->table, GEN = generated. "+ADD" lists columns added by later `ALTER TABLE` migrations, which may already appear in a rebuilt `_new` definition. The `main` section mixes current tables with some legacy, import-only ones (`clipboard`, `screenshots`, `*_id_mapping`, `ai_backfill_*`). The `settings` schema is the pre-v2 settings DB.


### `ai`
- **ai_event_subscriptions**: subscription_id:TEXT[PK], session_id:TEXT[NN], target_run_id:TEXT, owner_kind:TEXT[NN], owner_run_id:TEXT, description:TEXT[NN], note:TEXT, spec:TEXT[NN], lane:TEXT[NN], created_at:INTEGER[NN], expires_at:INTEGER, ended_at:INTEGER, end_reason:TEXT, matched_count:INTEGER[NN], self_excluded_count:INTEGER[NN], last_matched_at:INTEGER
  - idx: ai_event_subscriptions_session (session_id, created_at); ai_event_subscriptions_active (expires_at)
- **ai_events**: seq:INTEGER[PK], source:TEXT[NN], event_id:TEXT[NN], event_type:TEXT[NN], version:INTEGER[NN], subject:TEXT[NN], session_id:TEXT, run_id:TEXT, trust:TEXT[NN], causation_seq:INTEGER, correlation_id:TEXT, wake_depth:INTEGER[NN], summary:TEXT[NN], data:TEXT[NN], occurred_at:INTEGER[NN], recorded_at:INTEGER[NN]
  - idx: UNIQUE ai_events_source_event_id (source, event_id); ai_events_type_seq (event_type, seq); ai_events_session_seq (session_id, seq); ai_events_recorded_at (recorded_at)
- **ai_inbox**: inbox_id:INTEGER[PK], session_id:TEXT[NN], target_run_id:TEXT, event_seq:INTEGER[NN], subscription_id:TEXT, lane:TEXT[NN], coalesce_key:TEXT, state:TEXT[NN], bound_command_id:TEXT, bound_at:INTEGER, delivered_run_id:TEXT, disposed_reason:TEXT, created_at:INTEGER[NN], expires_at:INTEGER, settled_at:INTEGER
  - idx: ai_inbox_session_open (session_id, inbox_id); ai_inbox_bound_command (bound_command_id); ai_inbox_event_seq (event_seq); ai_inbox_subscription (subscription_id, state); ai_inbox_settled_at (settled_at); UNIQUE ai_inbox_subscription_event (subscription_id, event_seq)
- **ai_picker_usage**: kind:TEXT[NN], item_id:TEXT[NN], score:REAL[NN], use_count:INTEGER[NN], last_used_at:INTEGER[NN]
  - idx: ai_picker_usage_kind_last_used_at (kind, last_used_at DESC)
- **ai_run_admitted_commands**: command_id:TEXT[PK], run_id:TEXT[NN], fingerprint:TEXT[NN], admitted_at:INTEGER[NN]
  - idx: ai_run_admitted_commands_admitted_at (admitted_at)
- **ai_run_deferred_admissions**: command_id:TEXT[PK,NN], session_id:TEXT, kind:TEXT[NN], priority:INTEGER[NN], fingerprint:TEXT[NN], command_json:TEXT[NN], state:TEXT[NN], lease_epoch:TEXT, lease_until:INTEGER, run_id:TEXT, error_json:TEXT, requeues:INTEGER[NN], enqueued_at:INTEGER[NN], updated_at:INTEGER[NN]
  - idx: ai_run_deferred_admissions_order (state, priority DESC, enqueued_at ASC)
- **ai_run_events**: run_id:TEXT[NN], cursor:INTEGER[NN], protocol_version:INTEGER[NN], timestamp:INTEGER[NN], payload:TEXT[NN]
- **ai_run_inputs**: command_id:TEXT[PK], run_id:TEXT[NN], sequence:INTEGER[NN], delivery:TEXT[NN], text:TEXT[NN], attachments:TEXT[NN], accepted_at:INTEGER[NN], applied_at:INTEGER, abandoned_at:INTEGER, abandon_reason:TEXT
  - +ADD: origin TEXT
  - idx: UNIQUE ai_run_inputs_run_id_sequence (run_id, sequence); ai_run_inputs_pending (run_id, applied_at, abandoned_at)
- **ai_run_late_tool_results**: run_id:TEXT[NN], call_id:TEXT[NN], tool_name:TEXT[NN], result_json:TEXT[NN], late_by_ms:INTEGER[NN], recorded_at:INTEGER[NN]
- **ai_run_outbox**: id:INTEGER[PK,NN], kind:TEXT[NN], run_id:TEXT[NN], payload_json:TEXT[NN], state:TEXT[NN], attempts:INTEGER[NN], created_at:INTEGER[NN], updated_at:INTEGER[NN]
  - idx: ai_run_outbox_pending (state, run_id)
- **ai_run_recovery**: run_id:TEXT[PK,NN], session_id:TEXT, reason_kind:TEXT[NN], reason_code:TEXT, domain:TEXT[NN], prerequisite:TEXT, wake_at:INTEGER, attempt:INTEGER[NN], reason_json:TEXT[NN], updated_at:INTEGER[NN], ownership_epoch:TEXT[NN]
  - idx: ai_run_recovery_wake_at (wake_at)
- **ai_runs**: run_id:TEXT[PK], session_id:TEXT, session_source:TEXT, parent_run_id:TEXT, protocol_version:INTEGER[NN], phase:TEXT[NN], state:TEXT[NN], created_at:INTEGER[NN], updated_at:INTEGER[NN], last_cursor:INTEGER[NN], recovery_attempts:INTEGER[NN], projected_at:INTEGER
  - +ADD: continues_run_id TEXT, superseded_at INTEGER, superseded_by_command_id TEXT
  - idx: ai_runs_phase_updated_at (phase, updated_at); ai_runs_created_at (created_at); ai_runs_session_id_created_at (session_id, created_at); ai_runs_parent_run_id (parent_run_id); ai_runs_pending_projection (session_source, projected_at, phase, created_at)
- **ai_runtime_owner**: id:INTEGER[PK], epoch:TEXT[NN], acquired_at:INTEGER[NN]
- **ai_sessions**: session_id:TEXT[PK], agent_id:TEXT[NN], created_at:INTEGER[NN], agent_state:TEXT, agent_state_revision:INTEGER[NN], updated_at:INTEGER[NN], pinned:REAL, folder_id:TEXT[FK->folders], origin:TEXT[NN], archived_at:TEXT, deleted_at:TEXT
  - +ADD: wake_depth INTEGER, stop_fence_seq INTEGER, pinned REAL, folder_id TEXT
  - idx: ai_sessions_organized (session_id); ai_sessions_folder_updated_at (folder_id, updated_at DESC, session_id DESC); ai_sessions_recent_updated_at (updated_at DESC, session_id DESC); ai_sessions_pinned (pinned ASC, session_id DESC); ai_sessions_updated_at (updated_at, session_id)
- **ai_tool_usage**: tool_name:TEXT[PK,NN], extension_id:TEXT, score:REAL[NN], use_count:INTEGER[NN], last_used_at:INTEGER[NN]
  - idx: ai_tool_usage_last_used_at (last_used_at DESC)
- **ai_turn_projection_legacy_requests**: request_id:TEXT[PK], run_id:TEXT[NN]
  - idx: ai_turn_projection_legacy_requests_run_id (run_id)
- **ai_turn_projections**: run_id:TEXT[PK], session_id:TEXT[NN], summary:TEXT[NN], body:TEXT[NN], created_at:INTEGER[NN], updated_at:INTEGER[NN], parent_run_id:TEXT, body_zstd:BLOB
  - +ADD: superseded_at INTEGER, superseded_by_command_id TEXT, search_indexed_at INTEGER
  - idx: ai_turn_projections_session (session_id, created_at, run_id); ai_turn_projections_uncompressed (updated_at); ai_turn_projections_search_pending (updated_at)
- **ai_turn_search_text**: id:INTEGER[PK], run_id:TEXT[NN], item_index:INTEGER[NN], session_id:TEXT[NN], kind:TEXT[NN], text:TEXT[NN]
  - idx: ai_turn_search_text_session (session_id, run_id, item_index)
- **chat_message_search**: id:INTEGER[PK], message_id:TEXT[NN], chat_id:TEXT[NN]
- **chat_message_search_backfill**: id:INTEGER[PK], next_message_id:TEXT, total_messages:INTEGER, processed_messages:INTEGER[NN], completed_at:INTEGER
- **chat_message_search_fts** (VIRTUAL fts5): text, content='', contentless_delete=1, detail=none, prefix='1, tokenize='unicode61
- **chat_messages**: id:TEXT[PK,NN], chat_id:TEXT[NN], request_id:TEXT[NN], role:TEXT[NN], content:TEXT[NN], status:TEXT[NN], failure_reason:TEXT, model_id:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
  - idx: idx_chat_messages_request_id_created_at_id (request_id, created_at, id); idx_chat_messages_created_at_chat_id_id (created_at, chat_id, id); idx_chat_messages_chat_id_request_id_created_at_id (chat_id, request_id, created_at, id)
- **chat_requests**: id:TEXT[PK,NN], chat_id:TEXT[NN], feedback:TEXT, created_at:TEXT[NN], updated_at:TEXT[NN]
  - idx: idx_chat_requests_chat_id_created_at_id (chat_id, created_at, id)
- **chats**: id:TEXT[PK,NN], title:TEXT, model_id:TEXT, source:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN], creativity:TEXT, reasoning_effort:TEXT, pinned:REAL, system_instructions:TEXT, mode_id:TEXT, additional_tools:TEXT, dynamic_tool_loading:INTEGER, archived_at:TEXT, dynamic_skill_loading:INTEGER, folder_id:TEXT[FK->folders], parent_chat_id:TEXT, parent_message_id:TEXT, yolo_mode:INTEGER
  - +ADD: tool_confirmation_mode TEXT, pinned_at TEXT, mode_id TEXT, yolo_mode INTEGER, dynamic_tool_loading INTEGER, creativity TEXT, reasoning_effort TEXT, archived_at TEXT, additional_tools TEXT, parent_chat_id TEXT, parent_message_id TEXT, dynamic_skill_loading INTEGER, system_instructions TEXT, folder_id TEXT, pinned REAL
  - -DROP: pinned_at
  - idx: idx_chats_source_archived_updated_nanos_id (source, archived_at, RAYDATE_UNIX_NANOS(updated_at); idx_chats_source_archived_folder_pinned_id (source, archived_at, folder_id, pinned, id DESC); idx_chats_source_folder_archived_updated_id (source, folder_id, archived_at, updated_at DESC, id DESC); idx_chats_source_archived_updated_id (source, archived_at, updated_at DESC, id DESC); idx_chats_source_parent_chat_updated_id (source, parent_chat_id, updated_at DESC, id DESC); idx_chats_deleted_at_id (julianday(deleted_at); idx_chats_source_folder_archived_updated_nanos_id (source, folder_id, archived_
- **command_tag**: command_id:TEXT[NN], tag:TEXT[NN], updated_at:TEXT[NN]
- **command_tag_backup**: command_id:TEXT[NN], tag:TEXT[NN], updated_at:TEXT[NN]
- **commands**: id:TEXT[PK,NN], name:TEXT[NN], icon:TEXT, kind:TEXT[NN], model_id:TEXT, creativity:TEXT, prompt_template:TEXT, application_id:TEXT, highlight_edits:INTEGER[NN], reasoning_effort:TEXT, created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: routing_preference TEXT, reasoning_effort TEXT
  - idx: idx_commands_extension_id (extension_id); UNIQUE idx_commands_extension_id_name (extension_id, name)
- **default_models**: id:TEXT[PK,NN], model_id:TEXT[NN], updated_at:TEXT[NN]
- **folders**: id:TEXT[PK,NN], name:TEXT[NN], icon:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: instructions TEXT, working_directory TEXT, memory TEXT, memory_last_updated_at TEXT, memory_last_processed_at TEXT, memory_enabled INTEGER
  - idx: idx_folders_lower_name (LOWER(name)
- **models**: id:TEXT[PK,NN], name:TEXT[NN], model:TEXT[NN], provider:TEXT[NN], provider_name:TEXT[NN], provider_brand:TEXT[NN], data:TEXT[NN], updated_at:TEXT[NN], archived_at:TEXT
  - +ADD: archived_at TEXT, disabled_at TEXT
- **modes**: id:TEXT[PK,NN], name:TEXT[NN], icon:TEXT, model_id:TEXT, temperature:REAL, system_instructions:TEXT, additional_tools:TEXT, reasoning_effort:TEXT, created_at:TEXT[NN], updated_at:TEXT[NN], creativity:TEXT
  - +ADD: creativity TEXT
  - -DROP: temperature
- **scheduled_messages**: id:TEXT[PK,NN], name:TEXT[NN], icon:TEXT, prompt:TEXT[NN], prompt_mention_format:TEXT, model_id:TEXT, trigger:TEXT[NN], end:TEXT[NN], target:TEXT[NN], enabled:INTEGER[NN], run_count:INTEGER[NN], created_at:TEXT[NN], last_executed_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: reasoning_effort TEXT, routing_preference TEXT, pending_manual_run TEXT
- **sync_restore_claims**: origin:TEXT[NN], primary_key:TEXT[NN], import_seq:INTEGER[NN], capture_cutoff:INTEGER
- **sync_restore_imports**: seq:INTEGER[PK], import_id:TEXT[NN], restored_at:INTEGER[NN], owner_user_id:TEXT, capture_epoch:TEXT
- **transcription_style_tag**: transcription_style_id:TEXT[NN], tag:TEXT[NN], updated_at:TEXT[NN]
- **transcription_style_tag_backup**: transcription_style_id:TEXT[NN], tag:TEXT[NN], updated_at:TEXT[NN]
- **transcription_styles**: id:TEXT[PK,NN], name:TEXT[NN], icon:TEXT, kind:TEXT[NN], model_id:TEXT, creativity:TEXT, reasoning_effort:TEXT, prompt_template:TEXT, application_ids_json:TEXT[NN], website_hosts_json:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **transcriptions**: id:TEXT[PK,NN], source:TEXT[NN], source_identifier:TEXT, value:TEXT[NN], started_at:TEXT[NN], ended_at:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: application_name TEXT, application_path TEXT, word_count INTEGER, duration INTEGER, raw_value TEXT
  - idx: idx_transcriptions_status_started_at (status, started_at)

### `app_index`
- **app**: id:INTEGER[PK,NN], name:TEXT[NN], path:TEXT[NN], localizedName:TEXT, raycastId:TEXT[NN], applicationId:TEXT[NN], contentType:INTEGER[NN]
  - +ADD: bundleName TEXT, alternateNames TEXT, keywords TEXT, executionAlias TEXT, executableName TEXT, anchor TEXT, userContentType INTEGER
  - idx: app_application_id_idx (applicationId); app_content_type_idx (contentType)

### `clipboard`
- **entries**: id:INTEGER[PK], title:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN], workspace_id:INTEGER[NN], source_name:TEXT[NN], source_host:INTEGER[NN], source_url:TEXT[NN], copy_count:INTEGER[NN], pinned:REAL
  - +ADD: content_hash TEXT, title_search TEXT
  - idx: index_entries_content_hash (content_hash); entries_idx_pinned (pinned); entries_idx_updated_at_id (updated_at DESC, id DESC); idx_screenshots_path (path); idx_screenshots_pinned (is_pinned, pin_order); idx_screenshots_modified (modified_at DESC)
- **filters**: source_url:TEXT[PK], enabled:INTEGER[NN]
- **items**: id:INTEGER[NN], entry_id:INTEGER[NN]
- **representations**: id:INTEGER[NN], item_id:INTEGER[NN], entry_id:INTEGER[NN], mime_type:TEXT[NN], content_type:INTEGER[NN], content:TEXT[NN]
  - +ADD: trigger_update INTEGER, content_search TEXT
  - idx: representations_idx_entry_id_item_id (entry_id, item_id); representations_idx_content_search (entry_id, content_search); representations_idx_item_id (item_id)
- **representations_FTS** (VIRTUAL FTS5): content, entry_title, content='representations', content_rowid='id'
- **representations_tri_FTS** (VIRTUAL FTS5): content, entry_title, content='representations_with_title', content_rowid='id', tokenize='trigram'
- **router_entry_category**: entry_id:INTEGER[NN], category:TEXT[NN]
- **router_entry_tag**: entry_id:INTEGER[NN], tag:TEXT[NN]
- **router_filter_tag**: source_url:TEXT[NN], tag:TEXT[NN]
- **workspaces**: id:INTEGER[PK], title:TEXT[NN]

### `emoji`
- **aliases**: emoji_id:INTEGER[NN], alias:TEXT[NN]
- **checksum**: id:INTEGER[PK,NN], checksum:BLOB[NN]
- **custom_keyword**: emoji_id:INTEGER[NN], keyword:TEXT[NN]
- **emoji**: id:INTEGER[PK,NN], symbol:TEXT[NN], name:TEXT[NN], supportsSkinTones:INTEGER[NN], category:TEXT[NN], unicodeVersion:REAL, frecencyDate:REAL, pinned:REAL
- **keyword**: emoji_id:INTEGER[NN], keyword:TEXT[NN]
- **keyword_FTS** (VIRTUAL FTS5): emoji_id, keyword, content='', content_rowid='id'

### `frecency`
- **root_FTS** (VIRTUAL FTS5): item_id, content='root_search'
- **root_search**: item_id:TEXT[NN], frecency_date:REAL
  - +ADD: search_terms TEXT, opened_at TEXT

### `main`
- **ai_backfill_message_assignment**: message_id:TEXT[PK,NN], chat_id:TEXT[NN], request_seq:INTEGER[NN]
- **ai_backfill_ordered_messages**: message_id:TEXT[PK,NN], chat_id:TEXT[NN], role:TEXT[NN], status:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN], row_num:INTEGER[NN]
- **ai_backfill_request_map**: chat_id:TEXT[NN], request_seq:INTEGER[NN], request_id:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **ai_backfill_request_rows**: sort_order:INTEGER[PK], chat_id:TEXT[NN], request_seq:INTEGER[NN], request_id:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **app_menu_bar_pins**: app_id:TEXT[NN], menu_item_id:TEXT[NN], pinned:REAL[NN]
  - idx: app_menu_bar_pins_idx_app_pinned (app_id, pinned)
- **apple_shortcuts**: sort_order:INTEGER[PK,NN], shortcut_id:TEXT, name:TEXT[NN], accepts_input:INTEGER, folder_id:TEXT, folder_name:TEXT, image_path:TEXT, updated_at:TEXT[NN]
- **calculator_history**: id:TEXT[PK,NN], expression:TEXT[NN], result:TEXT[NN], calculation_type:TEXT[NN], copy_count:INTEGER[NN], pinned:REAL, created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: custom_name TEXT
- **calculator_legacy_imports**: migration_id:TEXT[NN], expression:TEXT[NN]
  - +ADD: name_pending INTEGER, pin_pending INTEGER
  - idx: calculator_legacy_imports_expression (expression)
- **clipboard**: id:INTEGER[PK], text:TEXT[NN], file_path:TEXT, image_hash:TEXT, copy_count:INTEGER[NN], category:TEXT, rich_text_data:BLOB, application_path:TEXT, text_content:TEXT, pinned:DOUBLE, created_at:DATETIME[NN], last_modified_at:DATETIME[NN]
- **contacts**: sort_order:INTEGER[PK,NN], contact_id:TEXT[NN], kind:TEXT[NN], name:TEXT, given_name:TEXT, family_name:TEXT, organization:TEXT, phone_numbers:TEXT, email_addresses:TEXT, postal_addresses:TEXT, image_data_available:INTEGER[NN], updated_at:TEXT[NN]
- **currencies**: code:TEXT[PK,NN], usd_rate:REAL[NN], currency_type:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **focus_categories**: id:TEXT[PK,NN], category_id:TEXT[NN], kind:TEXT[NN], builtin_id:TEXT, title:TEXT[NN], icon:TEXT[NN], website_hosts_json:TEXT[NN], application_ids_json:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN], accessed_at:TEXT[NN]
  - idx: UNIQUE focus_categories_builtin_id_idx (builtin_id); focus_categories_kind_accessed_title_idx (kind, accessed_at DESC, title COLLATE NOCASE); focus_categories_title_idx (title COLLATE NOCASE)
- **keyboardSearchMobile**: search_id:TEXT[PK], frequency:INTEGER[NN], last_used_at:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN], type:TEXT, favorite:REAL, alias:TEXT, keywords:TEXT
  - idx: keyboardSearchMobile_favorite_idx (favorite); keyboardSearchMobile_type_idx (type); keyboardSearchMobile_last_used_at_idx (last_used_at)
- **local_org_quicklink_tags**: quicklink_id:TEXT[PK,NN], tags:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **local_org_skill_settings**: skill_id:TEXT[PK,NN], enabled:INTEGER[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **local_org_snippet_keywords**: snippet_id:TEXT[PK,NN], keyword:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **local_org_snippet_tags**: snippet_id:TEXT[PK,NN], tags:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **local_org_snippet_usage**: snippet_id:TEXT[PK,NN], copy_count:INTEGER[NN], accessed_at:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **local_transcription_style_application_ids**: style_id:TEXT[NN], application_id:TEXT[NN], position:INTEGER[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **mcp_servers**: id:TEXT[PK,NN], type:TEXT[NN], icon:TEXT[NN], title:TEXT[NN], mention_name:TEXT[NN], description:TEXT, built_in:INTEGER[NN], error_message:TEXT, last_connected:TEXT, created_at:TEXT[NN], oauth_json:TEXT, updated_at:TEXT[NN], command:TEXT, arguments_json:TEXT, environment_json:TEXT, url:TEXT, headers_json:TEXT, oauth_config_json:TEXT, tools_json:TEXT[NN]
  - idx: mcp_servers_type_idx (type); mcp_servers_mention_name_idx (mention_name)
- **notes**: id:TEXT[PK,NN], title:TEXT, text:TEXT[NN], raw_content:TEXT, pinned:REAL, created_at:TEXT[NN], updated_at:TEXT[NN], deleted_at:TEXT, last_accessed_at:TEXT[NN], last_modified_at:TEXT[NN]
  - +ADD: last_accessed_at_is_placeholder INTEGER, caret_position INTEGER, deleted_at TEXT
- **org_ai_agents**: id:TEXT[PK,NN], organization_id:TEXT[NN], pack_id:TEXT[NN], agent_id:TEXT[NN], value:TEXT[NN], remote_updated_at:INTEGER[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **org_ai_commands**: id:TEXT[PK,NN], organization_id:TEXT[NN], pack_id:TEXT[NN], command_id:TEXT[NN], value:TEXT[NN], remote_updated_at:INTEGER[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **org_pack_sync_state**: kind:TEXT[PK,NN], last_synced_at:INTEGER[NN]
- **org_quicklinks**: id:TEXT[PK,NN], organization_id:TEXT[NN], pack_id:TEXT[NN], name:TEXT[NN], link:TEXT[NN], icon:TEXT[NN], raw_content:TEXT[NN], remote_updated_at:INTEGER[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: open_with_macos TEXT, open_with_windows TEXT, open_with_ios TEXT, tags TEXT, pinned REAL
- **org_skills**: id:TEXT[PK,NN], organization_id:TEXT[NN], organization_name:TEXT[NN], organization_handle:TEXT[NN], pack_id:TEXT[NN], skill_id:TEXT[NN], name:TEXT[NN], description:TEXT[NN], content:TEXT[NN], remote_updated_at:INTEGER[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: activation_mode TEXT, package_format TEXT, package_sha256 TEXT, package_file_count INTEGER, package_uncompressed_size INTEGER, package_contains_scripts INTEGER, package_byte_size INTEGER, package_content_type TEXT
- **org_snippets**: id:TEXT[PK,NN], organization_id:TEXT[NN], pack_id:TEXT[NN], icon:TEXT[NN], title:TEXT[NN], keyword:TEXT, text:TEXT[NN], raw_content:TEXT, remote_updated_at:INTEGER[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: value_created_at REAL, tags TEXT, pinned REAL
- **org_transcription_styles**: id:TEXT[PK,NN], organization_id:TEXT[NN], pack_id:TEXT[NN], style_id:TEXT[NN], value:TEXT[NN], remote_updated_at:INTEGER[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **pending_tokens**: token:TEXT[PK], attempts:INTEGER[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
- **quicklink_id_mapping**: old_id:INTEGER[PK,NN], new_id:TEXT[NN]
- **quicklinks**: id:INTEGER[PK], name:TEXT[NN], link:TEXT[NN], icon:TEXT[NN], application_id:TEXT, created_at:TEXT[NN], updated_at:TEXT[NN], open_count:INTEGER, raw_content:TEXT[NN], open_with:TEXT, open_with_macos:TEXT, open_with_windows:TEXT, open_with_ios:TEXT
  - +ADD: raw_content TEXT, open_count_crdt TEXT, open_with TEXT, pinned REAL
  - -DROP: open_count
- **raycastConfiguration**: extension_id:TEXT[PK], configuration:TEXT[NN], updated_at:TEXT[NN]
- **router_quicklink_tag**: quicklink_id:TEXT[NN], tag:TEXT[NN], updated_at:TEXT[NN]
- **router_snippet_tag**: snippet_id:TEXT[NN], tag:TEXT[NN], updated_at:TEXT[NN]
- **screenshots**: id:INTEGER[PK], name:TEXT[NN], path:TEXT[NN], category:TEXT[NN], text:TEXT, is_pinned:INTEGER[NN], pin_order:INTEGER, created_at:TEXT[NN], modified_at:TEXT[NN], text_extracted_at:TEXT
  - idx: idx_screenshots_path (path); idx_screenshots_pinned (is_pinned, pin_order); idx_screenshots_modified (modified_at DESC)
- **searchMobile**: search_id:TEXT[PK], frequency:INTEGER[NN], last_used_at:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN], type:TEXT, favorite:REAL, alias:TEXT, keywords:TEXT
  - idx: searchMobile_favorite_idx (favorite); searchMobile_type_idx (type); searchMobile_last_used_at_idx (last_used_at)
- **snippet_id_mapping**: old_id:INTEGER[PK,NN], new_id:TEXT[NN]
- **snippets**: id:TEXT[PK,NN], icon:TEXT[NN], title:TEXT[NN], keyword:TEXT, raw_content:TEXT, text:TEXT[NN], copy_count:INTEGER[NN], pinned:REAL, created_at:TEXT[NN], updated_at:TEXT[NN], accessed_at:TEXT[NN], last_modified_at:TEXT[NN]
  - +ADD: copy_count_crdt TEXT
  - -DROP: copy_count
- **translate_custom_commands**: id:TEXT[PK,NN], name:TEXT[NN], source_language:TEXT[NN], target_language:TEXT[NN], created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: output_behavior TEXT
- **user_defaults**: key:TEXT[PK,NN], value:TEXT[NN], created_at:TEXT[NN], last_modified_at:TEXT[NN]
- **window_management_layout_groups**: id:TEXT[PK,NN], name:TEXT[NN], icon_name:TEXT, created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: ignore_gap INTEGER, other_windows TEXT
- **window_management_layouts**: id:TEXT[PK,NN], group_id:TEXT[NN,FK->window_management_layout_groups], position:TEXT[NN], size:TEXT[NN], offset:TEXT[NN], z_position:INTEGER[NN], source:TEXT, display_index:INTEGER, updated_at:TEXT[NN]
  - +ADD: source_macos TEXT, source_windows TEXT
  - -DROP: source
  - idx: window_management_layouts_group_id (group_id)
- **windows_run_command_tag**: command_id:TEXT[NN], tag:TEXT[NN]
  - idx: idx_windows_run_command_tag_tag (tag)
- **windows_run_commands**: id:TEXT[PK], alias:TEXT[NN], command:TEXT[NN], arguments:TEXT[NN], description:TEXT[NN], icon:TEXT[NN], pinned:REAL, times_executed:INTEGER[NN], last_executed_at:TEXT, created_at:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: shell TEXT
  - idx: idx_windows_run_commands_alias (alias); idx_windows_run_commands_times_executed (times_executed DESC); idx_windows_run_commands_pinned_updated (pinned, updated_at DESC)

### `node_extensions`
- **commands**: id:INTEGER[PK], extension_id:INTEGER[NN], name:TEXT[NN], title:TEXT[NN], subtitle:TEXT, description:TEXT[NN], icon:TEXT, keywords:TEXT, mode:TEXT[NN], is_enabled:INTEGER[NN], preferences:TEXT[FK->TEXT], arguments:TEXT, updated_at:TEXT[NN], interval:TEXT, ran_at:TEXT, run_error:TEXT, status_item:TEXT, interval_enabled:INTEGER[NN], custom_subtitle:TEXT, assumed_view_kind:TEXT, digest:TEXT
  - +ADD: icon_variants TEXT
  - -DROP: ran_at, run_error, status_item, interval_enabled, custom_subtitle, assumed_view_kind, is_enabled
  - idx: idx_commands_extension_id (extension_id); UNIQUE idx_commands_extension_id_name (extension_id, name)
- **extension_install_history**: extension_uuid:TEXT[PK], first_installed_at:TEXT[NN]
  - idx: idx_extension_install_history_extension_uuid (extension_uuid)
- **extensions**: id:INTEGER[PK], uuid:TEXT, name:TEXT[NN], title:TEXT[NN], description:TEXT[NN], icon:TEXT[NN], keywords:TEXT, license:TEXT, author:TEXT, owner:TEXT, access:TEXT, readme_url:TEXT, source_url:TEXT, ai:TEXT, preferences:TEXT[FK->TEXT], local_sources:TEXT, version:TEXT, updated_at:TEXT[NN], requires_download:INTEGER[NN]
  - +ADD: model_provider_digest TEXT, icon_variants TEXT
  - -DROP: extension_id
  - idx: UNIQUE idx_extensions_extension_id (extension_id)
- **tools**: id:INTEGER[PK], extension_id:INTEGER[NN], name:TEXT[NN], title:TEXT[NN], description:TEXT[NN], icon:TEXT, keywords:TEXT, preferences:TEXT[FK->TEXT], functionalities:TEXT, confirmation:INTEGER[NN], input:TEXT, output:TEXT, instructions:TEXT, updated_at:TEXT[NN], digest:TEXT
  - +ADD: icon_variants TEXT
  - idx: UNIQUE idx_tools_extension_id_name (extension_id, name)
- **widgets**: id:INTEGER[PK], extension_id:INTEGER[NN,FK->extensions], name:TEXT[NN], title:TEXT[NN], description:TEXT[NN], icon:TEXT, icon_variants:TEXT, preferences:TEXT[FK->TEXT], interval:TEXT, digest:TEXT, activated_at:TEXT, preference_values:TEXT, updated_at:TEXT[NN]

### `screenshots`
- **entries**: id:INTEGER[PK], name:TEXT[NN], path:TEXT[NN], category:TEXT[NN], text:TEXT, is_pinned:INTEGER[NN], pin_order:INTEGER, created_at:TEXT[NN], modified_at:TEXT[NN], text_extracted_at:TEXT
  - idx: index_entries_content_hash (content_hash); entries_idx_pinned (pinned); entries_idx_updated_at_id (updated_at DESC, id DESC); idx_screenshots_path (path); idx_screenshots_pinned (is_pinned, pin_order); idx_screenshots_modified (modified_at DESC)

### `settings`
- **extension_settings**: extension_id:TEXT[NN], setting_key:TEXT[NN], setting_value:BLOB[NN], frecency_date:REAL
- **general**: setting_key:TEXT[PK], setting_value:BLOB[NN], frecency_date:REAL
- **shortcuts**: target:TEXT[PK], alias:TEXT, hotkey:TEXT

### `settings_v2`
- **cloud_sync_settings**: id:INTEGER[PK,NN], enabled:INTEGER[NN], devices:TEXT[NN], content:TEXT[NN], connection:TEXT[NN], enabled_at:TEXT, updated_at:TEXT[NN]
  - +ADD: disabled_categories TEXT
- **cloudsync_settings**: id:INTEGER[PK,NN], enabled:INTEGER[NN], connection:TEXT[NN], disabled_categories:TEXT[NN], enabled_at:TEXT, updated_at:TEXT[NN]
- **commands**: id:TEXT[PK,NN], extension_id:TEXT[NN], enabled:INTEGER[NN], alias:TEXT, deprecated_hotkey:TEXT, deprecated_meta:TEXT, custom_subtitle:TEXT, assumed_view_kind:TEXT, favorite_order:REAL, fallback_order:REAL, status_item:TEXT, synced_meta:TEXT, local_meta:TEXT, macos_synced_meta:TEXT, windows_synced_meta:TEXT, updated_at:TEXT[NN], macos_hotkey:TEXT, windows_hotkey:TEXT, device_generations:TEXT[NN]
  - +ADD: status_item TEXT, assumed_view_kind TEXT, fallback_order REAL, favorite_order REAL, device_generations TEXT, macos_hotkey TEXT, windows_hotkey TEXT, synced_meta TEXT, local_meta TEXT, macos_synced_meta TEXT, windows_synced_meta TEXT, updated_at TEXT, custom_subtitle TEXT
  - -DROP: favorited
  - idx: idx_commands_extension_id (extension_id); UNIQUE idx_commands_extension_id_name (extension_id, name)
- **general_settings**: id:TEXT[PK,NN], open_at_login:INTEGER[NN], show_in_menu_bar:INTEGER[NN], follow_system_appearance:INTEGER[NN], theme_id:TEXT[NN], window_mode:TEXT[NN], global_hotkey:TEXT, favicon_provider:TEXT, pop_to_root_timeout:INTEGER[NN], escape_key_behavior:TEXT[NN], page_navigation_keys:TEXT[NN], use_system_proxy_settings:INTEGER[NN], additional_certificate_authorities:TEXT[NN], window_presentation_mode:TEXT[NN], enforced_input_source_id:TEXT, navigation_bindings:TEXT[NN], window_capture_hotkey:TEXT, window_capture_copy_to_clipboard:INTEGER[NN], window_capture_show_in_finder:INTEGER[NN], window_capture_cleanshotx_overlay:INTEGER[NN], window_capture_custom_wallpaper:TEXT, root_search_sensitivity:TEXT[NN], updated_at:TEXT[NN], appearance:TEXT[NN], theme_dark_id:TEXT, theme_light_id:TEXT, tidy_menu_bar:INTEGER[NN], builtin_hotkeys_preset:TEXT[NN], hyper_key_code:TEXT, hyper_key_include_shift:INTEGER[NN], hyper_key_caps_lock_action:TEXT, hyper_key_display_shortcut:INTEGER[NN], open_folders_in_tabs:INTEGER[NN], singleton_key:INTEGER[PK,NN]
  - +ADD: show_favorites_in_compact_mode INTEGER, builtin_hotkeys_preset TEXT, window_presentation_mode TEXT, use_system_proxy_settings INTEGER, use_system_certificate_authorities INTEGER, additional_certificate_authorities TEXT, ui_zoom REAL, favicon_provider TEXT, pop_to_root_timeout INTEGER, tidy_menu_bar INTEGER, root_search_sensitivity TEXT, open_folders_in_tabs INTEGER, window_activation_behavior TEXT, enforced_input_source_id TEXT, escape_key_closes_window INTEGER, navigation_bindings TEXT, escape_key_behavior TEXT, use_spotlight_gesture INTEGER, page_navigation_keys TEXT, window_capture_hotkey TEXT, window_capture_copy_to_clipboard INTEGER, window_capture_show_in_finder INTEGER, window_capture_cleanshotx_overlay INTEGER, window_capture_custom_wallpaper TEXT, hyper_key_code TEXT, hyper_key_include_shift INTEGER, hyper_key_caps_lock_action TEXT, hyper_key_display_shortcut INTEGER
  - -DROP: window_capture_hotkey, window_capture_copy_to_clipboard, window_capture_show_in_finder, window_capture_cleanshotx_overlay, window_capture_custom_wallpaper, use_system_certificate_authorities, root_search_sensitivity, favicon_provider_old
- **internal_extensions**: id:TEXT[PK,NN], enabled:INTEGER[NN], deprecated_meta:TEXT, enabled_fallback_command_ids:TEXT, synced_meta:TEXT, local_meta:TEXT, macos_synced_meta:TEXT, windows_synced_meta:TEXT, updated_at:TEXT[NN], meta:TEXT
  - +ADD: enabled_fallback_command_ids TEXT, synced_meta TEXT, local_meta TEXT, macos_synced_meta TEXT, windows_synced_meta TEXT, updated_at TEXT
- **node_extensions**: id:TEXT[PK,NN], enabled:INTEGER[NN], deprecated_meta:TEXT, oauthTokens:TEXT, localStorage:TEXT, storedValues:TEXT, enabled_fallback_command_ids:TEXT, synced_meta:TEXT, local_meta:TEXT, macos_synced_meta:TEXT, windows_synced_meta:TEXT, updated_at:TEXT[NN], uninstalled:INTEGER[NN], device_generations:TEXT[NN], meta:TEXT, model_provider_enabled:INTEGER, model_provider_state:TEXT
  - +ADD: model_provider_enabled INTEGER, model_provider_state TEXT, model_provider_setup_pending INTEGER, uninstalled INTEGER, enabled_fallback_command_ids TEXT, device_generations TEXT, synced_meta TEXT, local_meta TEXT, macos_synced_meta TEXT, windows_synced_meta TEXT, updated_at TEXT
- **themes**: id:TEXT[PK,NN], name:TEXT[NN], updated_at:TEXT[NN], appearance:TEXT[NN], background:TEXT[NN], background_secondary:TEXT[NN], foreground:TEXT[NN], accent:TEXT[NN], selection:TEXT[NN], loader:TEXT[NN], red:TEXT[NN], orange:TEXT[NN], yellow:TEXT[NN], green:TEXT[NN], blue:TEXT[NN], purple:TEXT[NN], magenta:TEXT[NN], created_at:TEXT[NN]
- **window_modes**: id:TEXT[PK], name:TEXT[NN]

### `temp`
- **chat_message_search_query** (VIRTUAL fts5): text, tokenize='unicode61
- **chat_message_search_query_vocab** (VIRTUAL fts5vocab): 'temp', 'chat_message_search_query', 'instance'

### `user_activity`
- **ai_chat_activity**: id:TEXT[PK,NN], activity_type:TEXT[NN], source:TEXT[NN], chat_model:TEXT[NN], word_count:INTEGER[NN], timezone_offset_minutes:INTEGER[NN], device:TEXT[NN], platform:TEXT[NN], updated_at:TEXT[NN]
  - +ADD: platform TEXT
- **user_activity**: id:TEXT[PK,NN], activity_type:TEXT[NN], user_activity_info_key:TEXT[FK->user_activity_info], platform:TEXT[NN], timezone_offset_minutes:INTEGER[NN], device:TEXT[NN], updated_at:TEXT[NN]
- **user_activity_info**: key:TEXT[PK], title:TEXT[NN], updated_at:TEXT[NN]
- **user_focus_activity**: id:TEXT[PK,NN], source:TEXT[NN], date:TEXT[NN], duration:REAL, pause_events:TEXT, block_events:TEXT, snooze_events:TEXT, device:TEXT[NN], platform:TEXT[NN], timezone_offset_minutes:INTEGER[NN], updated_at:TEXT[NN]
  - +ADD: platform TEXT, timezone_offset_minutes INTEGER

Triggers: ai.chat_message_search_ad, ai.chat_message_search_ai, ai.chat_message_search_au, ai.clear_chat_parent_link_on_parent_delete, ai.delete_chat_messages, ai.mirror_chat_organization_ai, ai.mirror_chat_organization_au, ai.mirror_chat_organization_folder_ai, ai.nullify_chat_folder_on_folder_delete, ai.update_commands_updated_at_on_tag_delete, ai.update_commands_updated_at_on_tag_insert, ai.update_transcription_styles_updated_at_on_tag_delete, ai.update_transcription_styles_updated_at_on_tag_insert, calculator_legacy_entry_deleted, calculator_legacy_name_written, calculator_legacy_pin_written, clipboard.delete_entry_categories, clipboard.delete_entry_items, clipboard.delete_entry_tags, clipboard.delete_item_representations, clipboard.representations_FTS_ad, clipboard.representations_FTS_ai, clipboard.representations_FTS_au, clipboard.representations_tri_FTS_ad, clipboard.representations_tri_FTS_ai, clipboard.representations_tri_FTS_au, clipboard.update_entries_updated_at_on_tag_delete, clipboard.update_entries_updated_at_on_tag_insert, clipboard.update_entry_updated_at, emoji.keyword_FTS_ad, emoji.keyword_FTS_ad_alias, emoji.keyword_FTS_ad_custom, emoji.keyword_FTS_ad_name, emoji.keyword_FTS_ai, emoji.keyword_FTS_ai_alias, emoji.keyword_FTS_ai_custom, emoji.keyword_FTS_ai_name, emoji.keyword_FTS_au, emoji.keyword_FTS_au_alias, emoji.keyword_FTS_au_custom, emoji.keyword_FTS_au_name, entities_migration_guard_on_delete, entities_migration_guard_on_update, frecency.root_FTS_ad, frecency.root_FTS_ai, frecency.root_FTS_au, node_extensions.update_commands_updated_at, node_extensions.update_extensions_updated_at, node_extensions.update_tools_updated_at, quicklinks_updated_at, update_clipboard_last_modified_at, update_currencies_updated_at, update_notes_last_modified_at, update_pending_tokens_updated_at, update_quicklinks_updated_at_on_tag_delete, update_quicklinks_updated_at_on_tag_insert, update_snippets_last_modified_at, update_snippets_last_modified_at_on_tag_delete, update_snippets_last_modified_at_on_tag_insert, update_user_defaults_last_modified_at
