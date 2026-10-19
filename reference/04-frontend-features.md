# 04 — Raycast 2.8.2 Frontend: UI, Built-in Feature Catalog, Settings, Theming, State

Scope: static analysis only of
`F = /Applications/Raycast.app/Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources/frontend`
(Vite/React build, 1366 files) and `../backend/index.mjs` (7.4 MB Node bundle). Nothing was launched or modified.
No source maps ship (`//# sourceMappingURL=` comments point to missing `.map` files). REA was not needed (no REA sessions opened, none to close) — plain `grep`/Python regex over minified chunks was sufficient.

Legend: **[O]** = observed verbatim in the bundle. **[I]** = inferred from code shape, naming, or partial evidence.

---

## 0. Key source files (evidence index)

| What | File (in F unless noted) |
|---|---|
| Built-in extension + command catalog (declarative) | `internal-extensions-DTEJ6vg9.js` (174 KB) — identical catalog duplicated in `backend/index.mjs` |
| AI extension catalog (excluded) | `ai-extension-R40i_hUJ.js` |
| Custom WM commands (Resize/Move Window, Custom Window Command) | `main-window-DnJ2PGxd.js` (`qb({key:...})`) |
| Root search section model | `backend/index.mjs` (`yv`/`vv` section tables, `VXi`/`HXi` order arrays) |
| Default keyboard shortcut table | `shortcuts-CslcL67B.js` |
| General settings defaults | `vn={appearance:\`system\`,...}` in a shared chunk (grep `uiZoom:1,hyperKeyIncludeShift`) |
| Settings page definitions | `*-settings-page-definition-*.js` (28 files) + General page inside `settings-window-rhdHXTOI.js` |
| Settings routes | `settings-routes-CaSK800e.js` |
| Theme model + bundled themes | `contrast-improvement-C3QOPKP9.js` (also bundles colorjs.io), `theming-init-WqRr99XU.js` |
| Design tokens | `css-C58pR_1e.css` (`.scaled-tokens`, `.theme-root`, `:root`) |
| IPC transport | `register-query-client-CHYpWjSJ.js` (class using `window.webkit.messageHandlers.ipcRequest`) |
| Service container | `services-CI1JjB8Y.js`, `main-window-services-DAD40LhQ.js` |
| Toast / HUD stores | `toast-store-yMR5z_cG.js`, `hud-store-D8l7mVGu.js` |
| Icons | `command-*.png`, `extension-*.png/svg`, `window-manager-*-24.svg` (≈100 WM glyphs) |

Windows (HTML entry points) [O]: `main-window.html`, `settings-window.html`, `notes-window.html`, `theme-studio-window.html`, `welcome-window.html`, `feedback-window.html`, `ai-chat-window.html` (AI, excluded), `pro-walkthrough-window.html`, `auxiliary-window-prewarm.html`.

Important context [O]: this 2.x frontend is **cross-platform (macOS + Windows)**. Every extension/command carries an `availability` field: `{macos:'production'}` (alias `nt`/`y` in the bundle = macOS-only), `{windows:'production'}` (alias `rt`/`x` = Windows-only), `internal`, or all. Several classic Raycast v1 commands do **not** exist as built-ins in 2.8.2 — see §1.Z.

---

## 1. Complete built-in extension / command catalog

### 1.A How the catalog is defined [O]

Each extension is declared with a factory (minified `f(...)` in the frontend, `s_(...)` in the backend):

```js
f({ key:'applications', title:'Applications', description:'…', icon, availability?,
    settings: w({ preferences:{ hotkeyBehavior: u({default:'toggle', storage:'synced'}), … } }),
    commands: { uninstall: p({title, description, type:'view-command'|'no-view-command'|'ai-extension-command',
                               icon, keywords, fallbackStatus:'available', suggestionPriority, availability,
                               rootSearch:{when:'searching', matching:'url', section}, settings:l({preferences:{…label/type…}})})
                 .actions([{name:'primary', actions:[d({handler:{target:'frontend'|'backend', key:'…'} | {type:'navigation', path:'/…'}})]},
                           S.favorites, S.deeplink, S.configure, S.delete]) },
    dynamicCommands: { application: b({title:e=>e.payload.name, subtitle, keywords, args, rootSearch:{section:'apps'}}).actions([...]) } })
```

- **commands** = static commands (show in root search, can have alias/hotkey).
- **dynamicCommands** = per-instance items generated at runtime (each app, each quicklink, each system-settings pane, each WM layout…). IDs are `commandId + separator + instanceId` (`extension-command-ids-*.js`). Node (store) extension commands use `c:n:<extId>::-::<commandName>` (`node-command-ids-*.js`).
- Storage scopes for preferences [O]: `synced` (Cloud Sync), `local` (this device), `platform` (OS-specific).
- Handler targets [O]: `frontend` (React/host), `backend` (Node), `navigation` (router path), `custom-view`.
- Shared action groups [O] (`ai-extension-*.js`): `favorites` = Add to Favorites / Remove from Favorites / Move Favorite Up / Move Favorite Down; `deeplink` = Copy Deeplink / Configure Deeplink…; `configure` = Configure Command… / Configure Extension / Reset Ranking; `delete` = Disable Command.

### 1.B Extension list (37 non-AI + 1 AI) [O]

| key | Title | Description | Platform |
|---|---|---|---|
| apple-shortcuts | Apple Shortcuts | Search and run the Shortcuts in your Mac instantly. | macOS |
| applications | Applications | Quickly launch your installed applications. | all |
| browser | Browser | Provide more context to AI Commands and Chat. | all (AI-adjacent) |
| calculator | Calculator | Calculate numbers and expressions. | all |
| calendar | Calendar | Check your schedule and join conference calls. | macOS |
| clipboard-history | Clipboard History | Search for text, images, links and colors you copied earlier and paste it again. | all |
| contacts | Contacts | Search and manage your contacts. | macOS |
| developer | Developer | Create and manage Raycast extensions. | all |
| dictation | Dictation | Speech to text anywhere | all (AI-backed transcription) |
| dictionary | Dictionary | Look up definitions for words. | macOS |
| emoji-picker | Emoji & Symbols | Search emoji & symbols from Raycast. | all |
| file-search | File Search | Search for files and folders on your computer. | all |
| raycast-focus | Raycast Focus | Manage focus sessions and categories. | all |
| games | Games | Quickly launch your installed games. | Windows |
| mcp | MCP | Connect external tools and data sources using MCP. | all (AI — exclude) |
| navigation | Navigation | (Switch Windows / Search Menu Bar Items) | all |
| notes | Raycast Notes | Create and manage your notes. | all |
| organizations | Raycast for Teams | Manage your Raycast organizations. | all (cloud) |
| preferences | System Settings / Windows Settings | Manage your preferences (one dynamic command per settings pane) | all |
| quicklinks | Quicklinks | Create links to open your frequently used websites and apps. | all |
| raycast-account | Account | Manage your Raycast Account. | all (cloud) |
| raycast-core | Raycast | A set of core commands provided out of the box. | all |
| raycast-debug | Debug | Dev/internal builds only | internal |
| raycast-settings | Raycast Settings | Shortcuts to various Raycast Settings. | all |
| raycast-wrapped | Raycast Wrapped | View your Raycast year in review | all |
| screen-awareness | Screen Awareness | Capture context from your screen and send it to AI | AI — exclude |
| screenshots | Screenshots | Search and manage your screenshots. | all |
| script-commands | Script Commands | Run script commands from configured directories | all |
| snippets | Snippets | Quick access to short snippets of text, code, etc. | all |
| system | System Actions | A set of system commands provided out of the box. | all |
| translator | Translator | Quickly translate text between languages. | all (cloud API) |
| trial-nudges | Trial Nudges | Contextual nudges for the Raycast Pro trial. | all (commercial — skip) |
| typing-practice | Typing Practice | Practice your typing easily | all |
| urls | URL | Set of URL-related commands (Open in Browser when query is a URL). | all |
| web-searches | Web Searches | Google / DuckDuckGo / Bing search (fallbacks). | all |
| window-management | Window Management | Move and resize your application windows. | all |
| windows-run | Run | Improved Windows Run dialog. | Windows |
| windows-taskbar | Taskbar | Customizable taskbar behaviour. | Windows |
| **ai** | AI | AI that works with your OS | **EXCLUDED** |

### 1.C Per-extension commands, behavior, settings

(Full machine-extracted dump in Appendix A; this section is the curated version. "Platform" column omitted when all.)

**Applications** [O]
- Dynamic `application` per installed app (root section "Applications"). Actions: Open Application; New Application Window (Win); Open Recent Files… (Win); Run as Administrator / Run as Different User (Win); Show in Finder/File Explorer; Show Info in Finder (mac); Show Package Contents (mac); Show Advanced Options (Win); favorites group; Copy Path / Copy Name / Copy Bundle Identifier (mac); Configure…; Treat as Game (Win); Reset Ranking; Hide Application (⌘⇧H); Quit Application (⇧⌘Q); Force Quit Application.
- `Uninstall Applications` (view; mac) — list apps and uninstall (`/extensions/applications/uninstall-applications`).
- `Manage Auto Quits` (mac) — opens settings; auto-quit apps after idle.
- Settings: Hotkey Action `hotkeyBehavior` (default `toggle`), Search Scopes (`userSearchScopes`, `disabledDefaultSearchScopes`), Deep Search `recursiveSearch` (up to 3 levels), Auto Quit rules (`autoQuitRules`, `autoQuitDefaultIntervalMinutes`=3, options 1/3/5/10/15 min), `quitAppsClosedToTray`=true.

**Calculator** [O]
- `Calculator` (inline root-search result, section "Calculator"): math, unit/currency/time-zone conversions; Rust calculator native module in backend (`calculator-rs.darwin-arm64.node`, `Calculator.node`).
- `Color` — preview a typed color, copy in various formats (root section "Color").
- `Flight Tracker` — typed flight number → route/status/delay (root section "Flight"; d3 world maps `world-countries-*.js`).
- `Weather` — forecast for queried location (root section "Weather"; weather SVG icon set).
- `Calculator History` (view) — 3 months history.
- Settings: `enableColorDetection`, `enableFlightTracker`, `enableWeather`, `enableSyntaxHighlighting` (all true), `remToPxRate`=16, `workHoursPerDay`=8.
- `Ask Calculator` — AI (exclude).

**Calendar** (mac) [O]
- `My Schedule` (view) — upcoming events from enabled calendars; join meeting links (Zoom/Meet/Teams/Slack/Jitsi/Skype icons present).
- `Create Event` (view; `/extension/calendar/create-event`, also edit-event).
- Dynamic `event` — upcoming events appear in root search section "Calendar Events".
- Settings: Enabled Calendars (`disabledCalendars`), `eventDisplayTolerance`=600 s, `defaultCalendarApplication`, `defaultGoogleBrowserApplication`.

**Clipboard History** [O]
- `Clipboard History` (view) — searchable list of text/images/links/colors/files with detail pane; filters view; edit entry content; pin.
- `Paste Sequentially` — pastes items one by one; pref `addNewLine` (default true).
- `Reset Paste Sequence`.
- Settings: Keep history for `historyDuration` (`P1D`,`P1W` default,`P1M`, 3 months, …), Text Recognition (OCR) `textRecognitionEnabled`=true, Recognition Mode `ocrLevel` (fast/accurate), `captureUniversalClipboard` (mac), Disabled Applications.

**Contacts** (mac) [O] — `Search Contacts` (view); dynamic `contact` (if `showInRootSearch`). Settings: Sort By `sortOrder`=`last-name`.

**Developer** [O] — `Import Extension`, `Create Extension`, `Manage Extensions`, `Extension Diagnostics`. Settings: `useNodeProductionEnvironment`=false, `autoReloadOnSave`=true, `keepWindowVisibleDuringDevelopment`=false, `disablePopToRootSearch`=false, `openRaycastInDevelopmentMode`=true.

**Dictation** [O, AI-backed → treat as optional; can rebuild with local Whisper] — Dictate; Dictate to AI (AI—exclude); Dictate to Note; Get Last Transcription; Add Word to Vocabulary; Finish/Cancel Dictation; Dictation History; Custom Instructions; Vocabulary; Create Style / Search Styles; Get Started with Dictation; dynamic transcription styles. Settings: language `auto`, output action `paste` (paste / copy / …), context-aware paste, auto submit + submit key/keyword, sounds, mute while recording, auto styling, app context, microphone priority.

**Dictionary** (mac) [O] — `Define Word` (view; macOS Dictionary). Keywords: lexicon, thesaurus, glossary, spell.

**Emoji & Symbols** [O] — `Search Emoji & Symbols` (grid view; custom keywords editor). Settings: Column Count `columnCount`=8, Emoji Skin Tone `skinTone`=`none`, Primary Action `primaryAction`=`paste` (paste / copy), Save AI-generated custom keywords.

**File Search** [O] — `Search Files` (view, master-detail with preview/QuickLook), `Quick Look` (Win), `Open in Finder/File Explorer`, indexing status item, dynamic results in root ("Files", "Recently Used Files"). Settings: Search Scopes, Ignore Patterns (respects .gitignore/.ignore/.rayignore), Excluded Automatically, Content Search, Include Hidden Files, Use ignore files, Index Network & Removable Drives, Keep Files from Removed Volumes, NTFS scanner (Win), Reset to Defaults; launcher-level "Include Files in Root Search" / "Include File Content…". Backend uses an indexer native module + `ripgrep` binary (Contents/Resources/ripgrep) [O].

**Raycast Focus** [O] — Start / Toggle / Pause / Resume / Complete / Edit Focus Session; Search / Create / Import Focus Categories; dynamic `session`. Blocks apps & websites (allow/block lists). Settings: Snooze Duration (`snoozeDurationMs`=180000), Play Sound=true, Restore Terminated Apps=false, Allow all Websites when allowlist empty=false. Root section "Focus Session".

**Games** (Win) — Game Launcher (Steam, Epic, Xbox, Riot…), Game Mode (disable Raycast hotkeys when game foreground).

**Navigation** [O] — `Switch Windows` (view; all apps' windows; actions incl. close/minimize/fullscreen via `ipc.host.navigation.*`), `Search Menu Bar Items` (mac; menu items of frontmost app).

**Raycast Notes** [O] — `Raycast Notes` (opens separate floating Notes window), `Search Notes`, `Create Note`. Separate `notes-window.html` with ProseMirror-based rich text editor, find/replace bar, format bar, recently-deleted menu. Settings: Show Notes Toggle in Menu Bar=false, Escape Key Loses Focus (`escapeKeyBehavior`=`closesWindow`), Zoom=1.

**Quicklinks** [O] — `Create Quicklink` (pref Autofill from current app or clipboard=true), `Create Quicklink` ephemeral variant shown when query is a URL, `Search Quicklinks`, `Import Quicklinks`, `Export Quicklinks`, dynamic `quicklink` (with `{argument}` placeholders → inline args). Settings: Show Link Previews=true, Prefer Existing Tabs=false, Pass Selected Text as Argument=false, Warning before delete.

**Raycast (core)** [O] — Install Update; Release Notes / Changelog; Check for Updates; Check for Extension Updates; Force Update All Extensions; Quit Raycast; Settings (`⌘,`); Show Onboarding; Reset Raycast Window Position; **Confetti** (pref Use seasonal holiday confetti); Toggle Bounce Animation (mac); Toggle Performance Logs; **Show Theme Studio**; **Switch Theme** (view `/switch-theme`); Open Manual; Send Feedback; **Store** (`/store`, extension store browse/install); Share Raycast; Copy Raycast Version; Copy/Reveal Raycast Logs; Create Memory Dump (Win); **Capture Window** (screenshot a Raycast window; pref Copy to clipboard); **Open Camera** (mac; camera preview; pref Play shutter sound); **Export Settings & Data** / **Import Settings & Data** (encrypted, passphrase); Migrate from Raycast v1 (mac); affiliate/pro/announcement/upgrade items (commercial — skip). Settings: `showWhatsNew`, scheduled export (`scheduledExportFrequency`=`none`, `scheduledExportAutoDelete`=`never`, location, skip on battery=true), weather location/units, widget layout.

**Raycast Settings** [O] — one command per settings page: Account, General, Launcher, Shortcuts, Keyboard, Cloud Sync, Advanced, Organizations, Internal, About (each with search keywords, see Appendix A).

**Screenshots** [O] — `Search Screenshots` (grid, OCR text search, categories), `Paste Latest Screenshot`. Settings: Search Scopes, Column Count=3, Include All Media=false, Text Recognition=true, Recognition Mode, Allow cloud-file OCR (Win), Storage Duration=`unlimited`.

**Script Commands** [O] — `Search Script Commands`, `Create Script Command` (from template), `Reload Script Commands`; script outputs view (`/extension/script-commands/output`). Settings: Script Folders (`searchDirectories`).

**Snippets** [O] — `Create Snippet`, `Search Snippets`, `Import Snippets`, `Export Snippets`, `Auto Snippet` (internal). Text expansion engine with keyword triggers; dynamic placeholders: `clipboard`, `cursor`, `date`, `time`, `datetime`, `day`, `uuid`, `selection`, `argument`, `snippet` (nested), `browser-tab` [O]. Settings: Enable Snippet Expansion=true, Expansion Mode (`Immediately` default, or delayed/word-boundary), Expand within Words=false, Override System Snippets=false, Injection Delay (`None`/Short/Long/Extra Long…), Response Time (`Default`/Quick/Instant/Delayed/Extended…), Completion Sound (macOS system sounds Basso…Tink), Disabled Applications, Warning before delete, pinned tags bar.

**System Actions** [O] (platform per command)
| Command | Platform |
|---|---|
| Dismiss Notifications; Eject All Disks; Toggle Hidden Files; Toggle Mute; Toggle Stage Manager; Turn Volume Up/Down; Unhide All Hidden Apps | macOS |
| Open Trash/Recycle Bin; Empty Trash/Recycle Bin; Hide All Apps Except Frontmost; Lock Screen; Log Out; Quit All Apps (pref Show Warning); Set Volume / to 0/25/50/75/100%; Play/Pause; Next Track; Previous Track; Show Desktop; Show Screen Saver; Restart; Shut Down; Sleep; Sleep Displays; Toggle System Appearance (Dark Mode) | all (some listed with no availability key) |
| Quit All Apps Except Frontmost; Quit the Active App; Manage Wi-Fi Connections; Manage Bluetooth Devices; Volume Mixer; Set Sound Output/Input Device; Toggle Active App Mute; Turn Active App Volume Up/Down; Hibernate; Toggle WiFi; Toggle Airplane Mode; Toggle Camera Mute; Toggle Energy Saver; Toggle HDR; Toggle Night Light; Toggle Microphone Mute | Windows |
Destructive ones (Shut Down, Restart, Log Out, Empty Trash, Quit All) show a confirmation alert in the main window [O: `"shut-down":async()=>{mi.open({…title:'Shut Down',description:'Are you sure you want to shut down?'…`]. Settings: `favoriteNetworks`, `favoriteDeviceIds`.

**System Settings (key `preferences`)** [O] — dynamic `preference` per settings pane (root section "System Settings"); actions Open System Setting, Show in Finder, Copy Path, Copy Name.

**Translator** [O] — `Translate` (view), inline `Translate to <lang>` root-search item (section "Translate"), user-defined `customTranslate` commands. Settings: Primary Action `copy`, Use Selected Text as Source=false, Default Source/Target Language. (Uses Raycast cloud/AI translation → on Linux use a local or 3rd-party API.)

**Typing Practice** [O] — `Start Typing Practice` (WPM results view).

**URL** [O] — `Open in Browser` (shown when query is URL). **Web Searches** [O] — Google Search, DuckDuckGo Search, Bing (default fallback commands).

**Window Management** [O] — commands (all platforms unless noted):
- Maximize; Restore; Minimize; Minimize on This Display; Maximize Height; Maximize Width; Almost Maximize; Reasonable Size ("60% of the screen, max 1024x900"); Resize Window (exact W×H); Center; Center Half.
- Halves: Left Half, Right Half, Top Half, Bottom Half.
- Thirds: First Third, Center Third, Last Third, First Two Thirds, Center Two Thirds, Last Two Thirds, Top Third, Middle Third, Bottom Third, Top Two Thirds, Bottom Two Thirds, Top Center Two Thirds, Bottom Center Two Thirds.
- Fourths: First Fourth, Second Fourth, Third Fourth, Last Fourth, First Three Fourths, Center Three Fourths, Last Three Fourths, Top First/Second/Third/Last Fourth, Top Three Fourths, Bottom Three Fourths.
- Quarters: Top Left / Top Right / Bottom Left / Bottom Right Quarter.
- Sixths: Top Left / Top Center / Top Right / Bottom Left / Bottom Center / Bottom Right Sixth.
- Move: Move Left / Right / Top / Bottom (Top/Bottom have pref Center Window=true), Move Window (exact coordinates).
- Displays: Move to Previous Display / Move to Next Display (prefs Wrap Around Displays=true, Keep Aspect Ratio=true).
- Spaces/desktops: Move to Previous/Next Space (mac; "Desktop" on Win), Switch to Previous/Next Space (mac; pref Animate Switching=false); Windows-only: Switch Desktops (view), Open Desktop (by index) and Open Desktop 1…10, Move to Desktop (by index) and Move to Desktop 1…10, Close Desktop / Close Active Desktop, Rename Desktop / Rename Active Desktop.
- mac-only: Make Smaller (to 25%), Make Larger, Toggle Fullscreen, Toggle Grid Overlay (grid placement).
- Win-only: Toggle Always on Top, Focus Next/Previous App Window.
- Custom: Create Command, Create Layout (multi-app layouts), Save Current Layout, Import Commands & Layouts, dynamic `layoutGroup` per saved command/layout; Resize Window / Move Window / Custom Window Command (deeplink, `main-window` `qb(...)`).
- Settings: Window Gap `innerGap`=0, Screen Gap `outerGap`=0, Cycling `cycleMode`=`sizes` ("Cycle ½, ⅔, and ⅓") or `displays` ("Cycle Displays"), Respect Stage Manager=false, Auto Close Empty Desktops (Win), Presets (apply hotkeys from other WM apps), System Spaces Shortcuts.
- Icons: `window-manager-<action>-24.svg` for every action (left-half, top-left-sixth, almost-maximize, reasonable-size, move-to-desktop-1..10, etc.) [O].

**Windows-only** (skip for Linux but note equivalents): Run (`windows-run`: Open Run, Execute Run Command, Search/Create Run Commands with aliases, shell selection) — a Linux equivalent "Run shell command / $PATH binaries" is cheap and useful. Taskbar (`windows-taskbar`: custom taskbar window with widgets).

**Debug / Trial Nudges / Organizations / Account / Wrapped** — internal or cloud/commercial; skip or stub.

### 1.D AI — EXCLUDED [O]
`ai` extension: AI Chat, Quick AI, Show AI Credit Usage, Show Claude/ChatGPT/Copilot Usage, Manage Models, Profile, Memory, Import Memory, Create/Search/Import AI Commands, Automations, Agents (AI modes), Team Skills, Send Selected Text/Focused Window/Screen/Screen Area to AI, Quick Fix, Ask AI Chat/Memory/Terminal/Location/Selected Text/Weather/Agents/Automations, dynamic AI commands/modes/remote tools. Also every `aiExtension` "Ask X" command in other extensions (Ask Calendar, Ask Clipboard, Ask Finder, Ask Snippets, Ask Quicklinks, Ask Notes, Ask Store, Ask Manual, Ask Feedback, Ask Raycast Settings, …), the MCP extension, Screen Awareness, Browser extension (AI context), Dictate to AI, Investigate Raycast Logs, Remote (iPhone AI chat) page.

### 1.Z Features NOT present as built-ins in 2.8.2 [O by absence]
Grepping frontend + backend found **no** built-in: Kill Process, Color Picker (only the calculator "Color" preview), Spotify/Music control (only generic Play/Pause/Next/Previous media keys), Reminders, Hotkey cheat-sheet, Lorem Ipsum, "Floating Notes" (replaced by Raycast Notes window), Search Menu Items exists only as "Search Menu Bar Items" (mac). These are store (Node) extensions in Raycast's ecosystem; a clone could add them as first-party extensions.

---

## 2. Main launcher UI anatomy

### 2.1 Window
- Size [O, `css-C58pR_1e.css`]: `--main-window-width: 750*spx`, `--main-window-expanded-height: 475*spx`, header `66*spx` (macOS; 64 on Windows), footer `42*spx` (macOS; 44 default). Window corner radius `--radius-window` 8px base, 26px on macOS 26 (Tahoe), 20px on macOS 27. `spx = 1px * --zoom` (interface size scale).
- Window modes [O]: `windowMode: 'expanded' | 'compact'` (default expanded). Compact = only the search bar; results expand when typing; optional "Show Favorites in Compact Mode" row of favorite icons (`compact-favorites__*`, `compact-command-item__*` CSS modules) [O].
- Presentation [O]: `windowPresentationMode` = Screen containing mouse (default) / Screen with active window / Primary screen. `windowActivationBehavior` = Move to Active Space (default) / Switch Space.
- Global hotkey default [O]: `⌥ Space` (`globalHotkey:{modifiers:[Alt], key: Space}`); Hyper Key support (Caps Lock/any modifier/F-key → ⌃⌥⇧⌘, quick-press action Escape/trigger key, include Shift, Secure Input compatibility).
- Pop to root after close [O]: `popToRootTimeout` default 90 s; options Immediately/5/15/30/60/90/120/180 s.
- Escape [O]: `escapeKeyBehavior` = "Navigate back or close window" (default) / "Close window and pop to root"; `escapeKeyClosesWindow`=true for secondary windows.

### 2.2 Search bar (header)
- Root placeholder [O]: "Search for apps and commands…". Each view sets its own placeholder ("Search snippets…", "Search windows…", "Search Store for Extensions…", …).
- `search-field-ui` component [O] has a `WidthSizer` → the text measures its width so **inline argument inputs** (`argument-list`, `search-arguments` CSS modules) can sit right after the typed command name. Arguments come from command definitions (`args:[{type:'text', name:'input', placeholder:'Input…'}]` e.g. Apple Shortcuts accepting input; quicklink `{argument}` placeholders; script command arguments) [O]. Tab moves between argument fields [I].
- Left side: back button (navigation-bar-ui `backButton`) when inside a pushed view; Raycast logo in root (`root-search-view__searchbarLogo`) [O]; loading bar under the header (`navigation-bar-ui__loaderClassic`/`loaderGlow`) [O].
- Right side: optional dropdown/filter accessory (`toggleFilter` ⌘P) [O].
- Search history: ↑ in empty root restores recent searches ("Search History" setting) [O].

### 2.3 Root list sections [O, backend section tables]
Empty query (order `VXi`): Announcements, Updates, Recent AI Chats (AI), Calendar Events, "Welcome to Raycast" walkthroughs, Focus Session, Development, **Favorites** (ordered by `favoriteOrder`), **Suggestions** (frecency `sort:'suggestions'`), **Commands**, Applications, System Settings, Recently Used Files.
Searching (order `HXi`): Color, Calculator, Flight Tracker, Weather, Recent AI Chats, Translate, **Results** (rank-sorted unified list), Files, **`Use "<query>" with…`** (fallback commands, ordered by `fallbackOrder`).
- Ranking: frecency + "Root Search Sensitivity" (low/medium/high, default high) [O]; "Reset Ranking" action [O].
- Root search API [O]: `ipc.backend.rootSearch.search/getItem/handleAction/activateEmptyQuery/getAllAliases/getCommandDeeplink`.

### 2.4 List items & accessories
- Standard row: icon (app icon / command PNG / SF-like glyph from `icons-*.svg` sprite), title, subtitle (extension name or app disambiguator) [O], right-side accessories: alias tag, hotkey (`visual-shortcut`), type label, tags/text/date/icon accessories (`command-list-item-accessory`, `node-tag-item`) [O for components; I for exact ordering]. Running-app indicator (`showAppIsRunningIndicators`) [O].
- Detail/metadata pane (master-detail layout, `master-detail-layout__*`) used by Clipboard History, File Search, Snippets, Quicklinks [O].
- Grid views (emoji 8 cols, screenshots 3 cols; `column-count-radio-group`) [O].
- Empty/error states with illustrations (`empty-state-*`, `error-state-*`) [O].

### 2.5 Action panel (⌘K)
- `toggleActionPanel: ⌘K` [O]. Popover menu (`menu.namespace`, `action-menu`, `use-action-panel`) with its own search field, sections (primary / favorites / copy / configure / app-management / deeplink / delete), each action showing its shortcut.
- Primary action = ↵, secondary = ⌘↵, tertiary = ⌥↵ (mac) / ⌃⇧↵ (win), quaternary = ⌘⌥↵, quinary = ⌘⌃↵ [O].
- `toggleAboutPanel: ⌘⇧K` (extension/command info panel) [O].

### 2.6 Footer / action bar
- `ActionBarUI.Root/Left/Center/Right/ToastWrapper` (`<footer>`) [O]. Left: current context icon/title or toast; right: primary action title + ↵, separator, "Actions ⌘K" [O for `PrimaryActions` + `Actions` strings; layout I].
- Toasts render inside the footer when the main window is visible and not compact; otherwise they're converted to a HUD [O: `toast-store` → `open(e){ … isVisible && !isCompact ? set(e) : hud.open(e) }`]. Toast has variants (success/failure/warning, animated loading), primary/secondary actions, `toggleToast ⌘T` to focus toast actions [O].
- HUD [O]: separate store; small pill overlay shown after window hides (e.g. "Copied to Clipboard").
- Alerts/dialogs [O]: `alert-store` / `dialog-store`, centered confirm dialogs (destructive variant).

### 2.7 Navigation stack
- TanStack Router route tree inside the main window (`getParentRoute` ×129, `window.mainRouter.navigate(...)`) [O]. Views are routes like `/extension/clipboard-history`, `/extension/snippets/create`, `/extensions/$extensionId/$commandId` (Node extension views), `/store/$extensionId`. Back = ⌘[ or Esc; forward = ⌘] [O]. Pop to root = ⌘Esc (mac) / ⇧Esc (win) [O].

### 2.8 Default keyboard shortcuts [O, `shortcuts-CslcL67B.js`; mac / win]
| Name | macOS | Windows |
|---|---|---|
| primary | ↵ | ↵ |
| secondary | ⌘↵ | Ctrl↵ |
| tertiary | ⌥↵ | Ctrl⇧↵ |
| quaternary | ⌘⌥↵ | Ctrl Alt↵ |
| quinary | ⌘⌃↵ | Alt⇧↵ |
| toggleActionPanel | ⌘K | Ctrl K |
| toggleAboutPanel | ⌘⇧K | Ctrl⇧K |
| copy | ⌘⇧C, ⌘C | Ctrl⇧C, Ctrl C |
| copySecondary / Tertiary / Quaternary | ⌘⌥C / ⌘⌃C / ⌘⌥⇧C | … |
| paste / pasteSecondary / pasteTertiary | ⌘V / ⌘⇧V / ⌘⌥V | |
| edit / editSecondary | ⌘E / ⌘⇧E | |
| new / newSecondary | ⌘N / ⌘⇧N | |
| open / openSecondary / openTertiary | ⌘O / ⌘⇧O / ⌘⌥O | |
| openLinkSecondary | ⌘⇧L | |
| duplicate | ⌘D | — |
| move | ⌘⌥⇧M | |
| clear / clearSecondary / … | ⌃X / ⌘⇧X / ⌃⇧X / ⌃⌥X | Ctrl D / Ctrl⇧D / Ctrl Alt D / Alt⇧D |
| favorite | ⌘⇧F | Ctrl⇧F |
| moveUp / moveDown (reorder) | ⌘⌥↑ / ⌘⌥↓ | |
| hide | ⌘⇧H | |
| info / infoSecondary | ⌘I / ⌘⇧I | |
| pin | ⌘. | |
| showHidden | ⌘⇧. | |
| quit / secondaryQuit | ⌘Q / ⌘⇧Q | |
| refresh / refreshSecondary | ⌘R / ⌘⇧R | |
| save / saveSecondary | ⌘S / ⌘⇧S | |
| goBack / goForward | ⌘[ / ⌘] (alt: ⌘⌥← / ⌘⌥→) | |
| nextSection / prevSection | ⌘↓ / ⌘↑ | |
| nextPage / prevPage | ⌥↓ / ⌥↑ | |
| numberHotkey0-9 | ⌘0…⌘9 (jump to item / favorites) | |
| toggleQuickLook | ⌘Y | |
| zoomIn / zoomOut / zoomDefault | ⌘+ / ⌘= ; ⌘− ; ⌘0 | |
| disableCommand | ⌃⇧⌘D | Alt⇧D |
| configureCommand / configureExtension | ⌘⇧, / ⌘⌥, | |
| openSettings | ⌘, | |
| popToRoot | ⌘Esc | ⇧Esc |
| toggleFilter / Secondary | ⌘P / ⌘⇧P | |
| toggleToast | ⌘T | |
| search / secondarySearch | ⌘F / ⌘⇧F | |
| copyDeeplink | ⌘⇧C | |
| reportBug / requestFeature | ⌘⌥B / ⌘⌥F | |
| openGuide | ⌘⇧/ | |
| focusSettingsSidebar / Main | ⌘⌃S / ⌘⌃M | |
| AI-only (exclude): sendToAiChat ⌘J, changeModel ⌘⇧M, startDictating ⌃M, etc. | | |
Navigation bindings [O]: Emacs (⌃B ⌃F ⌃P ⌃N, default) or Vim Motions (⌃H ⌃L ⌃K ⌃J). Page navigation keys: Square Brackets (default) or Arrow Keys.

### 2.9 Fallback commands
Commands with `fallbackStatus:'available'` can be put in the "Use "<q>" with…" section (Settings → Launcher → Fallback Commands; "Manage Fallback Commands" button) [O]. Default fallbacks [I from Raycast behavior + web-searches extension]: Google Search, plus File Search / Search Snippets / Search Quicklinks / Translate etc. are eligible. Fallback ordering stored as `fallbackOrder` metadata [O].

### 2.10 Other main-window surfaces [O]
Store browser + extension detail + version history; Node extension runtime views (`node-command-view`, `node-form-view`, `node-detail-view`, preferences form, OAuth view, exception view); Camera view; Confetti (host `ipc.host.raycast.confetti`); Window shake (`shakeMainWindow`); Welcome/Onboarding window; Theme switcher.

### 2.11 Linux rebuild suggestions (UI)
- Use **Tauri 2** (WebKitGTK) or **Electron** hosting a React 19 + TanStack Router/Query app — mirrors the original architecture exactly (React in a WebView, host+Node backend over IPC). For a lighter build: GTK4/libadwaita (Rust `relm4`) or Qt/QML.
- Launcher window: undecorated, transparent, always-on-top, 750×475 (scaled), center on monitor under pointer; on Wayland use `gtk-layer-shell`/`wlr-layer-shell` (overlay layer, keyboard exclusive) because regular toplevels can't self-position; on X11 use override-redirect/`_NET_WM_STATE_ABOVE`.
- Global hotkey: Wayland has no general API → use XDG `GlobalShortcuts` portal (KDE/GNOME 48+), or compositor binding (Hyprland `bind = ALT, SPACE, exec, raycast-clone toggle`), with a CLI/D-Bus `toggle` entrypoint. X11: `XGrabKey`.
- Implement section/ranking logic server-side (backend) like Raycast does; frontend only renders `sections[]`.
- Action panel: Radix/Ariakit popover or cmdk (`cmdk` gives search + keyboard nav for free).
- Toast→HUD fallback: HUD as a separate small layer-shell surface.

---

## 3. Settings window

Sidebar groups [O, `settings-routes`]: Account `/account`, General `/general`, Launcher `/launcher`, Widgets `/widgets`, Shortcuts `/shortcuts`, Keyboard `/keyboard`, Cloud Sync `/cloud-sync` (+ `/content`, `/devices`), Advanced `/advanced`, Organizations `/organizations`, Internal `/internal`, About `/about`, Remote `/remote` (AI iPhone — exclude), and **Extensions** `/extensions` + `/extensions/<extensionId>` per built-in extension (AI, Apple Shortcuts, Applications (+`/auto-quit`), Browser, Calculator, Calendar (+`/enabled-calendars`), Clipboard History (+`/filters`), Contacts, Developer, Dictation (+`/microphone`,`/personalization`,`/advanced`), Dictionary, Emoji Picker, File Search, Games, MCP, Navigation, Notes, Organizations, System Settings, Quicklinks, Raycast core, Raycast Focus, Raycast Settings, Screenshots, Script Commands, Snippets, System, Translator, Typing Practice, Window Management, Windows Run). Each page has a sidebar search (`settings-sidebar-search`, `searchEntries` with keywords per row) [O].

### 3.1 General [O, from `settings-window-*.js` + defaults object]
| Row | Key / default | Options |
|---|---|---|
| Follow System Appearance | `appearance:'system'` | system / light / dark |
| Theme (fixed) / Light Theme / Dark Theme | `themeLightId`, `themeDarkId` (fallback to bundled when not Pro) | list of installed themes |
| Theme Studio | button "Edit or create themes for Raycast" | |
| Interface Size | `uiZoom: 1` | Default (1) / Large (1+Δ) / Larger (1+2Δ) |
| Window Mode | `windowMode:'expanded'` | Default (expanded) / Compact |
| Show Favorites in Compact Mode | `showFavoritesInCompactMode: true` | |
| Open at Login | `openAtLogin: true` | |
| Show In Menu Bar | `showInMenuBar: true` | |
| Automatically Show the Taskbar | (Win) | |
| Raycast Hotkey | `globalHotkey: ⌥Space` | recorder |

### 3.2 Launcher [O]
Behavior: Show Raycast on (`windowPresentationMode`), Pop to Root Search (`popToRootTimeout`), Root Search Sensitivity (`rootSearchSensitivity` low/medium/high, default high), Search History (reset). Customize Search: Include Files in Root Search, Include File Content search results in Root Search, Include Contacts in Root Search, Include Agents (AI). Fallback Commands section (orderable list).

### 3.3 Shortcuts / Extensions table [O for components, I for column layout]
`shortcuts-settings-view` + `extensions-section`: tree table Extension → Commands with columns Name, Type, **Alias** (`command-alias-input`), **Hotkey** (`command-hotkey-input`, conflict dot `hotkey-conflict-dot`), Enabled checkbox; per-command preferences in a side pane (`extension-command-preferences`). Backend calls: `settings.getAllCommandSettings/updateCommandSettings(Batch)/getHotkeyConflicts/getCommandHotkeyConflict`. Uninstall extension dialog ("Uninstall but Keep Settings" / "Uninstall and Delete Settings").

### 3.4 Keyboard [O]
Escape Key Behavior; Escape Key Closes Window; Auto-switch Input Source (`enforcedInputSourceId`); Navigation Bindings (emacs/vim-motions); Page Navigation Keys (square-brackets/arrow-keys); Built-in Hotkeys Preset (`improved` default / `classic` "Classic User"); Hyper Key (none/Caps Lock/L-R ⌃⇧⌥⌘/F1–F12), Quick Press (trigger key / Escape), Include Shift, Secure Input Compatibility, Replace Hyper Key Modifiers with ✦.

### 3.5 Advanced [O]
Window Activation Behavior; Favicon Provider (None/DuckDuckGo/Google, default `''`=Raycast?); Tidy Menu Bar; Open Folders in Tabs (Win); Run Accessibility Helper Elevated (Win); Diagnostics Services; Export (Export Passphrase, Scheduled Backup, Backup Location, Auto-Delete, Skip on Battery); Connection (Use System Proxy Settings, Additional Certificate Authority).

### 3.6 Cloud Sync / Account / Organizations / About / Internal [O]
Cloud Sync: enabled, Synced Devices, Synced Content (per-category), Delete data. Account: Manage Account, Sign In/Out, Subscription, Credits, Upgrade. About: Raycast Updates, Open Changelog, Website, Slack Community, Send Feedback (+ diagnostics section). Internal: Palette helper, caret inspector, web content process mode, 60 FPS cap, cache durations, Clear Cache.

### 3.7 Per-extension pages
See Appendix B (verbatim titles + descriptions from every `*-settings-page-definition-*.js`).

### 3.8 Linux rebuild suggestions (settings)
Separate decorated window (normal toplevel), left sidebar + content, same router. Store settings as JSON (synced vs local split); expose the same declarative `preferences` schema per extension and auto-render forms (checkbox/dropdown/text/file-picker/hotkey-recorder). Hotkey recorder must handle Wayland (portal-assigned shortcuts) vs X11.

---

## 4. Theming

### 4.1 Theme data model [O, `contrast-improvement-*.js`]
```ts
type Theme = {
  id: string; name: string; isBundled?: boolean;
  appearance: 'light' | 'dark';
  background: Hex; backgroundSecondary: Hex; foreground: Hex;
  accent: Hex; selection: Hex; loader: Hex;
  red: Hex; orange: Hex; yellow: Hex; green: Hex; blue: Hex; purple: Hex; magenta: Hex;
}
```
Bundled themes (verbatim):
| id | name | app. | background | bgSecondary | foreground | accent | selection | loader | red | orange | yellow | green | blue | purple | magenta |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bundled-raycast-dark | Raycast Dark | dark | #000000 | #000000 | #FFFFFF | #4FA3F8 | #FFFFFF | #FFFFFF | #FF6363 | #FF9217 | #FFC531 | #59D499 | #56C2FF | #A485FF | #CF2F98 |
| bundled-raycast-light | Raycast Light | light | #FFFFFF | #FFFFFF | #000000 | #138AF2 | #000000 | #000000 | #B12424 | #C75D07 | #F8A300 | #006B4F | #138AF2 | #6A3DEC | #9A1B6E |
| bundled-sky | Sky | dark | #0E1C3F | #173036 | #D7F0F4 | #4FA3F8 | #6688FF | #47FFFF | #ED5959 | #ED8659 | #EDD559 | #47FF91 | #1A9FFF | #7759ED | #ED59B2 |
| bundled-sunset | Sunset | dark | #451A08 | #0A3943 | #FADDD1 | #4FA3F8 | #7698EF | #47E0FF | #ED5959 | #ED8659 | #EDD559 | #59ED7A | #30BBE8 | #7759ED | #ED59B2 |
| bundled-midnight | Midnight | dark | #070034 | #11005B | #FAF0FF | #4FA3F8 | #B1A7FF | #F4C4FF | #F84141 | #FFC100 | #FEFF7F | #63BA89 | #6AB7FB | #C58AFA | #FF5DB3 |
| bundled-dawn | Dawn | light | #FFF1F7 | #D0C1FF | #120032 | #4FA3F8 | #602AFF | #5A00FF | #E14848 | #E5753C | #B7B400 | #00AC5D | #4F80FF | #9454FF | #D756BF |
| bundled-overcast | Overcast | light | #D9F9FF | #C7E0FC | #002369 | #4FA3F8 | #0075FF | #0019FF | #EE5050 | #FA8542 | #EBA200 | #30B475 | #5271D8 | #B35AEB | #DD43A7 |
| bundled-noon | Noon | light | #FFE7C6 | #FCBFA5 | #1E003C | #4FA3F8 | #7B46FF | #6100FF | #DA4C4C | #D76F33 | #D49200 | #09B664 | #5876D8 | #A543E3 | #C4228B |

- Non-Pro users are forced back to Raycast Dark/Light [O: `theming-init` resets `themeDarkId/themeLightId` when `!has_pro_features`]. Accent may follow the OS accent (`--accent: var(--color-system-accent, var(--theme-accent))`) [O].
- Contrast handling [O]: colorjs.io is bundled; `--<color>-contrast` and `--<color>-on-tint-10/20` variables are computed to guarantee a minimum contrast ratio against the backgrounds.
- Theme CRUD [O]: `ipc.backend.themes.getAll/getById/create/update/delete`; live updates via `ipcNotification.settings.subscribeUpdateTheme`; host gets `setAppearance` and `previewThemeBackgroundColors`.

### 4.2 Theme → CSS variables [O, `css-C58pR_1e.css`]
Raw: `--bg`, `--bg-secondary`, `--fg`, `--theme-accent`/`--accent`, `--selection`, `--loader`, `--red --orange --yellow --green --blue --purple --magenta`.
Alpha ramps for each: `-0, -5, -10, -20, -40, -60, -80` via `rgb(from var(--x) r g b / N%)`.
Semantic tokens (`.theme-root`):
```
--color-text-primary: var(--fg)          --color-text-secondary: var(--fg-60)
--color-text-tertiary: var(--fg-40)      --color-text-quaternary: var(--fg-20)
--color-text-disabled / placeholder: var(--fg-40)   --color-text-selection: var(--fg-20)
--color-text-link: var(--accent)
--color-border-primary: var(--fg)  --color-border-secondary: var(--fg-20)  --color-border-tertiary: var(--fg-5)
--color-border-separator: var(--fg-10)  --color-border-token: var(--fg-20)  --color-border-token-selected: var(--fg-40)
--color-border-field: var(--fg-20)  --color-border-focus-ring: fg @30%
--color-surface-token: var(--fg-10)  --color-surface-list-hover: var(--fg-5)  --color-surface-list-selection: var(--fg-10)
--color-surface-control: var(--fg-10)  --color-surface-inner-panel: #ffffff1a  --color-surface-input-field: #ffffff0d
--color-surface-action-bar: #ffffff0d  --color-window-bg: var(--bg-40)  --color-window-bg-secondary: var(--bg-secondary-40)
--color-panel-background: var(--color-window-bg-secondary)  --color-panel-overlay: #ffffff1a
--color-brand: #ff6363   --<color>-transparent: var(--<color>-10)
```
Note `--color-window-bg` is the theme background at **40% alpha** → the window is translucent over an OS blur (vibrancy / Liquid Glass on macOS 26) [O].
Other token names [O]: `--color-bg-max`, `--color-fg-max`, `--color-panel-backdrop`, `--color-surface-*`, `--color-swatch-*`, `--color-token-{primary,secondary,tertiary,string,highlight}` (syntax highlight), `--color-window-base`, `--color-window-backdrop-os-windows`.

### 4.3 Design tokens [O]
- Scale: `--spx: calc(1px * var(--zoom,1))`; every size is `round(calc(N * var(--spx)), 1px)`.
- Font: **InterVariable** (`InterVariable.woff2`, italic) with features `liga calt kern ss03`; mono **JetBrains Mono**. Base font-size `--font-size-13`. Scale: 8, 11, 13, 16, 18, 24. Weights 400/500/600/700.
- Spacing: 2, 4, 6, 8, 12, 16, 24, 32, 40, 48, 56. Icons: 12, 16, 22, 32.
- Radius: 2, 4, 6, 8, 10, 12, 16, 18, 20, 26, full. Window 8 (default) / 26 (macOS 26) / 20 (macOS 27).
- Blur: 6/12/24/36 px (or 15/35/60/120 variant). Easing: ease-out-expo `cubic-bezier(.16,1,.3,1)`, ease-out-back `cubic-bezier(.34,1.56,.64,1)`.
- Shadows: `--shadow-panel` = inset 1px fg-20 border + `0 8px 10px -6px #0000001a, 0 20px 25px -5px #0003`.
- Focus ring 1–2px `--color-border-focus-ring`. Hairline `--half-pixel` .5px on retina.
- Window sizes: main 750×475; header 66/64, footer 42/44; default secondary window header 52 (40 on Win), footer 52/44; AI chat header 44; notes footer 48.

### 4.4 Theme Studio [O, `theme-studio-window-*.js`]
Separate window: left list "Installed Themes" (bundled are read-only: "Editing this theme is not allowed. Please duplicate to modify."), editor with Theme Name, Theme Appearance, **Primary Colors** (Background, Background Secondary, Foreground, Selection, Loader, Accent), **Support Colors** (Red, Orange, Yellow, Green, Blue, Purple, Magenta), color editor (Hex, Hue/Saturation/Lightness sliders, Toggle Hue Clamping, Copy/Paste Color), wallpaper picker (Solid/Gradient/presets: Apple, Banana, Corals, Flower, Gelato, Paper Slice, Summer Dress), live **Theme Studio Preview** of a mock launcher (List, Grid, Form, Dropdown, Toolbar, Text Field, Text Area…). Actions: Create New, Duplicate, Delete, Save, Revert/Discard, Set as Light/Dark Theme, Copy as JSON, Copy as URL (`https://themes.ray.so`), Install theme from URL (deeplink) with "already exists" dialog.

### 4.5 Linux rebuild suggestions (theming)
Keep the 15-field theme JSON (compatible with ray.so theme URLs). Generate CSS variables at runtime exactly as above (CSS `rgb(from …)` relative color syntax requires WebKitGTK ≥ 2.44 / Chromium ≥ 119; otherwise precompute alpha ramps in JS). Blur-behind: KDE `org_kde_kwin_blur`, Hyprland `layerrule = blur`, GNOME needs an extension → fall back to opaque `--bg`. Follow light/dark via `org.freedesktop.appearance color-scheme` portal setting.

---

## 5. Frontend state management, libraries, transport

### 5.1 Libraries [O unless marked]
| Concern | Library / evidence |
|---|---|
| UI | **React 19.2.1** (`react-*.js`, `react-dom-*.js`), JSX runtime |
| Routing | **TanStack Router** (`getParentRoute` ×129 main / ×23 settings, `routeTree`, `$param` paths, `useSearch`) — memory history per window [I] |
| Server state | **TanStack Query** (`useQuery`, `useInfiniteQuery`, `useMutation`, `useQueries`, `queryOptions`, `infiniteQueryBehavior` chunks; `staleTime`, `gcTime`, `invalidateQueries` ×201; `query-keys-*.js`) |
| Client state | **Custom observable stores** — class with `subscribe/notify` + `useSyncExternalStore` (toast/hud/alert/dialog/hyper-key stores), and a store factory `g('Name',{context, actions:{update, …}})` exposing `peek()`, `select(sel).subscribe`, `actions.*` (raycastSettingsStore, authStore, windowStateStore, systemAppsStore, keyboardLayoutStore, appFlagsStore) — no zustand/jotai/redux found. Cross-window sync via BroadcastChannel (`Failed to send message on channel`) [O]. immer present (8 chunks). |
| DI | Service container `services-*.js`: `applicationsStore, aiCatalog, performanceLogger, indexStore, ipcNotificationCenter, ipcClient, ipcNotification, queryClient, appFlagsStore, authStore, nodeExtensionUI, mcpOAuthUI, windowStateStore, raycastSettingsStore, keyboardLayoutStore, systemAppsStore`; main window adds `mainRouter, photon, formDrafts, viewTti`. |
| Animation | `motion` (Framer Motion successor; `AnimatePresence` chunk) |
| Rich text | ProseMirror (Notes editor, AI composer) |
| Markdown | `marked` + `lowlight` (highlight.js) + mermaid + KaTeX |
| Colors | colorjs.io (bundled) |
| Dates | date-fns (`addMonths`, `startOfDay`, `isTomorrow` chunks) |
| Validation | zod (IPC response schemas `safeParse(…, 'response')`) |
| Charts/maps | d3 + world-atlas topojson (flight tracker) |
| Telemetry | Sentry (debug IDs in every chunk), product analytics |
| Fonts | InterVariable, JetBrains Mono |

### 5.2 Transport (frontend ⇄ host ⇄ backend) [O]
```js
class IpcClient {
  constructor(handlers, perf) { window.ipcRequest = this.handleRequest; window.ipcNotification = this.handleNotification; }
  async request(method, data, destination, timeoutMs, sentryTrace) {
    const res = await window.webkit.messageHandlers.ipcRequest.postMessage({
      method, data: JSON.stringify(data), destination, timeout: timeoutMs/1000, sentryTrace });
    return zodParse(res);              // JSON string reply via WKScriptMessageHandlerWithReply
  }
}
```
- The page posts to the native host (Swift app + `libraycast_host.dylib`, Rust); `destination` routes either to the **host** (native: windows, hotkeys, permissions, accessibility, WM) or the **backend** (Node `backend/index.mjs`: settings DB, root search, clipboard, snippets, notes, extensions host, AI). Host/back-end can call **into** the page via `window.ipcRequest(method, payload)` and push events via `window.ipcNotification(method, payload)`.
- Client API is a Proxy: `services.ipc.<destination>.<namespace>.<method>(args)` → method string `"<namespace>.<method>"`. Notifications: `services.ipcNotification.<ns>.subscribe<Event>(cb)` → `"<ns>.<event>"` (95 distinct subscriptions).
- Namespaces observed (call-site counts): host — `raycast` (window show/hide/resize, compact mode, appearance, confetti, dictation, quit/restart…), `fileSystem`, `media`, `settings`, `applications`, `permissions`, `system`, `windowManagement`, `virtualDesktops`, `hotkey`, `wifi`, `clipboard`, `calendars`, `bluetooth`, `palette`, `navigation`, `workspace`, `appMenuBar`, `dictionary`, `snippets`, `debug`. backend — `system`, `clipboard`, `ai`, `settings`, `fileSystem`, `aiRuntime`, `extensionHost`, `notes`, `snippets`, `userDefaults`, `indexer`, `userActivity`, `analytics`, `quicklinks`, `dictation`, `focus`, `auth`, `organizations`, `debug`, `windowsRunCommands`, `windowManagement`, `releases`, `emojiPicker`, `calculator`, `screenshots`, `mcp`, `rootSearch`, `store`, `translator`, `scriptCommands`, `legacyDatabase`, `menuBar`, `calendars`, `trials`, `themes`, `appMenuBarItems`, `remoteNotifications`, `database`, `linkInfo`.
- Bootstrap globals injected by host [O]: `window.identifier` (`main`/`notes`/…), `window.initialGeneralSettings`, `window.initialThemes`, `window.version`, `window.commitHash`, `window.raycastApi.environment`, `window.enablePerformanceMetrics`, `window.__NOTES_BOOT__`.

### 5.3 Linux rebuild suggestions (plumbing)
- Tauri: replace `webkit.messageHandlers.ipcRequest.postMessage` with `invoke('ipc', {method, data, destination})`; replace `window.ipcNotification` with Tauri `emit/listen`. Keep the same `<ns>.<method>` naming so the frontend layer is a thin Proxy.
- Backend: keep a Node (or Bun) sidecar process for root search, settings DB (SQLite), clipboard history, snippets, quicklinks, notes, script commands, extension host (for Raycast-API-compatible store extensions); host side in Rust for: global hotkeys (portal), clipboard watch (`wl-clipboard`/`wlr-data-control` or X11 XFixes), text injection for snippets/paste (`wtype`/`ydotool`/`uinput`, X11 XTest), keystroke monitoring for snippet expansion (evdev/uinput — requires input group; on Wayland there is no other global key-capture path), window management (per-compositor IPC: Hyprland `hyprctl`, Sway `swaymsg`, KWin scripting D-Bus, GNOME Shell extension; X11 EWMH via `wmctrl`/xcb), app list from `.desktop` files (XDG data dirs), System Settings panes from GNOME/KDE control-center `.desktop` entries, system actions via `systemctl`/logind D-Bus (suspend/hibernate/poweroff/reboot/lock via `loginctl lock-session`), volume via PipeWire `wpctl`/PulseAudio, media via MPRIS D-Bus (`playerctl`), Wi-Fi/Bluetooth via NetworkManager/BlueZ D-Bus, file search via `plocate`/own indexer + ripgrep for contents, OCR via Tesseract, calendar/contacts via EDS/Khal/CalDAV, dictionary via `dictd`/Wiktionary, emoji data from Unicode CLDR.

---

## Appendix A — Machine-extracted catalog (verbatim from `internal-extensions-DTEJ6vg9.js`)
Format: `CMD <key> <Title> -- <Description> type=<view-command|no-view-command|ai-extension-command> avail=<all|macOS-only|Windows-only|{…}|<other gate var>>`. `PREFS:` = extension preference key=default[storage]. `!0`=true, `!1`=false, `void 0`=undefined. Rows with `type=ai-extension-command` or titled "Ask …" are AI (exclude).  No `type=` shown = default `no-view-command`.

```

### EXT apple-shortcuts | Apple Shortcuts | Search and run the Shortcuts in your Mac instantly.
  CMD shortcut e=>e.payload.name --   avail=all

### EXT applications | Applications | Quickly launch your installed applications.
  PREFS: hotkeyBehavior=toggle[synced]; userSearchScopes=[][local]; disabledDefaultSearchScopes=[][local]; recursiveSearch=!1[local]; autoQuitRules=[][platform]; autoQuitDefaultIntervalMinutes=3[platform]; quitAppsClosedToTray=!0[platform]
  CMD uninstall Uninstall Applications -- Uninstall all applications. type=view-command avail={macos:production}
  CMD manageAutoQuits Manage Auto Quits -- Manage apps that automatically quit after you stop using them.  avail=macOS-only
  CMD application e=>e.payload.name --   avail=all

### EXT browser | Browser | Provide more context to AI Commands and Chat.
  PREFS: externalWebSocketServerEnabled=!0[local]; browserExtensionLastConnectedAt=void 0[local]
  CMD installBrowserExtension Install Browser Extension --   avail=all
  CMD aiExtension Ask Browser --  type=ai-extension-command avail=all

### EXT calculator | Calculator | Calculate numbers and expressions.
  PREFS: enableColorDetection=!0[synced]; enableFlightTracker=!0[synced]; enableWeather=!0[synced]; enableSyntaxHighlighting=!0[synced]; remToPxRate=16[synced]; workHoursPerDay=8[synced]
  CMD color Color -- Preview a color and copy it in different formats. type=no-view-command avail=all
  CMD flight Flight Tracker -- Track a flight's route, status and delay. type=no-view-command avail=all
  CMD calculate Calculator -- Calculate numbers and expressions.  avail=all
  CMD weather Weather -- Weather forecast for the queried location.  avail=all
  CMD history Calculator History -- A history of the calculations and conversions you perform using Raycast, preserved for the last 3 months. type=view-command avail=all
  CMD aiExtension Ask Calculator --  type=ai-extension-command avail=all

### EXT calendar | Calendar | Check your schedule and join conference calls.
  PREFS: disabledCalendars=[][synced]; eventDisplayTolerance=600[synced]; defaultCalendarApplication=void 0[platform]; defaultGoogleBrowserApplication=void 0[platform]
  CMD mySchedule My Schedule -- Check upcoming schedule from your enabled calendars and join meetings. type=view-command avail=all
  CMD createEvent Create Event -- Create a new calendar event. type=view-command avail=all
  CMD aiExtension Ask Calendar --  type=ai-extension-command avail=ie
  CMD event e=>e.payload.title --   avail=all

### EXT clipboard-history | Clipboard History | Search for text, images, links and colors you copied earlier and paste it again.
  PREFS: historyDuration=P1W[synced]; textRecognitionEnabled=!0[synced]; ocrLevel=void 0[synced]; captureUniversalClipboard=!1[local]
  CMD history Clipboard History --  type=view-command avail=all
  CMD pasteSequential Paste Sequentially -- Paste clipboard items one after another.  avail=all
  CMD resetPasteSequence Reset Paste Sequence -- Reset the paste sequence to start again from the most recent clipboard item.  avail=all
  CMD aiExtension Ask Clipboard --  type=ai-extension-command avail=all

### EXT contacts | Contacts | Search and manage your contacts.
  PREFS: sortOrder=last-name[synced]; showInRootSearch=!1[synced]
  CMD search Search Contacts -- Search through your contacts type=view-command avail=all
  CMD contact e=>e.payload.name??Unknown --   avail=all

### EXT developer | Developer | Create and manage Raycast extensions.
  PREFS: useNodeProductionEnvironment=!1[synced]; autoReloadOnSave=!0[synced]; keepWindowVisibleDuringDevelopment=!1[synced]; disablePopToRootSearch=!1[synced]; openRaycastInDevelopmentMode=!0[synced]
  CMD importExtension Import Extension -- Import extension from your file system.  avail=all
  CMD createExtension Create Extension -- Convenient way to quickly create new Raycast extensions. type=view-command avail=all
  CMD manageExtensions Manage Extensions -- Manage your Raycast extensions and publish them to the store. type=view-command avail=all
  CMD extensionDiagnostics Extension Diagnostics -- View loaded extensions with diagnostics data. type=view-command avail=all
  CMD aiExtension Ask Developer --  type=ai-extension-command avail=de

### EXT dictation | Dictation | Speech to text anywhere
  PREFS: allowEnterHotkey=ot[synced]; customInstructions=[synced]; customVocabulary=[Raycast][local]; outputAction=paste[synced]; contextAwareInsertion=!1[synced]; submitAction=disabled[synced]; submitKey=enter[synced]; submitKeyword=st[synced]; autoDetectStyle=!0[synced]; sounds=!0[synced]; language=auto[synced]; muteWhileRecording=!0[synced]; appContext=!0[synced]; builtinStyleFilters={}[synced]
  CMD dictateText Dictate -- Dictate text and paste it into the active application.  avail=all
  CMD dictateToAi Dictate to AI -- Dictate a prompt and send it to Quick AI or AI Chat.  avail=all
  CMD dictateToNote Dictate to Note -- Dictate text and save it as a new Raycast Note.  avail=all
  CMD copyLastTranscription Get Last Transcription -- Copy or paste the most recent dictation transcription.  avail=all
  CMD addWordToVocabulary Add Word to Vocabulary -- Add a word or the currently selected word to your dictation vocabulary.  avail=all
  CMD finishDictation Finish Dictation -- Finish the active dictation.  avail=all
  CMD cancelDictation Cancel Dictation -- Cancel the active dictation.  avail=all
  CMD searchTranscriptions Dictation History -- Search for saved dictation transcriptions. type=view-command avail=all
  CMD aiExtension Ask Dictation --  type=ai-extension-command avail=ce
  CMD openDictationCustomInstructions Custom Instructions -- Add global guidance on how to transcribe text across all your transcriptions.  avail=all
  CMD openDictationVocabulary Vocabulary -- Words and names that dictation should always get right.  avail=all
  CMD createTranscriptionStyle Create Style -- Create a new style type=view-command avail=I
  CMD searchTranscriptionStyles Search Styles -- Search for a style type=view-command avail=I
  CMD setUpDictation Get Started with Dictation -- Grant required permissions and configure your Dictate hotkey. type=view-command avail=all
  CMD transcriptionStyle e=>e.payload.name --  type=no-view-command avail=I

### EXT dictionary | Dictionary | Look up definitions for words.
  CMD defineWord Define Word -- Define a word using macOS Dictionary. type=view-command avail=all

### EXT emoji-picker | Emoji & Symbols | Search emoji & symbols from Raycast.
  PREFS: columnCount=8[synced]; skinTone=none[synced]; saveAiCustomKeyword=!0[synced]; primaryAction=paste[synced]
  CMD searchEmoji Search Emoji & Symbols --  type=view-command avail=all

### EXT file-search | File Search | Search for files and folders on your computer.
  PREFS: showInRootSearch=r.showInRootSearch[synced]; contentSearch=r.contentSearch[synced]; contentSearchInRootSearch=r.contentSearchInRootSearch[synced]; includeHiddenFiles=r.includeHiddenFiles[synced]; respectIgnoreFiles=r.respectIgnoreFiles[synced]; useNtfsScanner=r.useNtfsScanner[synced]; keepRemovedVolumeFiles=r.keepRemovedVolumeFiles[synced]; ignore=r.ignore[local]; include=r.include[local]; semanticIndexingPaths=r.semanticIndexingPaths[local]; enforceLowDiskSpaceBlock=r.enforceLowDiskSpaceBlock[local]; contentSearchEngine=r.contentSearchEngine[local]; contentSearchNonLocalVolumes=r.contentSearchNonLocalVolumes[local]; contentSearchOcrMaxPages=r.contentSearchOcrMaxPages[local]; walkThreads=r.walkThreads[local]; indexNetworkAndRemovableVolumes=r.indexNetworkAndRemovableVolumes[local]; semanticIndexingUseFileSearchScope=r.semanticIndexingUseFileSearchScope[local]; limitedFileAccessAcknowledgedAt=null[local]; viewState=i.viewState[local]
  CMD searchFiles Search Files --  type=view-command avail=all
  CMD quickLookSelection Quick Look -- Quick Look the file selected in File Explorer. Assign a global hotkey to preview the selection without focusing Raycast.  avail=Windows-only
  CMD quickOpen m({macos:Open in Finder,windows:Open in File Explorer}) --   avail=all
  CMD indexing File Search is indexing… --   avail=all
  CMD aiExtension Ask Finder --  type=ai-extension-command avail=ne
  CMD fileExplorerAiExtension Ask File Explorer --  type=ai-extension-command avail=Windows-only
  CMD fileSearchAiExtension Ask File Search --  type=ai-extension-command avail=all
  CMD result e=>gt(e.instanceId) --   avail=all

### EXT raycast-focus | Raycast Focus | Manage focus sessions and categories.
  PREFS: snoozeDurationMs=18e4[synced]; playSound=!0[synced]; restoreAppsWhenSessionEnds=!1[synced]; allowAllOnEmptyWebsiteAllowlist=!1[local]
  CMD start Start Focus Session -- Start a new focus session type=view-command avail=all
  CMD toggle Toggle Focus Session -- Start with last settings or stop the current focus session  avail=all
  CMD pause Pause Focus Session -- Pause the current focus session  avail=all
  CMD resume Resume Focus Session -- Resume the current focus session  avail=all
  CMD complete Complete Focus Session -- Complete the current focus session  avail=all
  CMD edit Edit Focus Session -- Edit the current focus session type=view-command avail=all
  CMD searchCategories Search Focus Categories -- Search through focus categories type=view-command avail=all
  CMD createCategory Create Focus Category -- Create a new focus category type=view-command avail=all
  CMD importCategories Import Focus Categories -- Import focus categories from a JSON file type=view-command avail=all
  CMD aiExtension Ask Raycast Focus --  type=ai-extension-command avail=all
  CMD session e=>{let t=e.payload.session.title.trim();return t.length>0?t:Focus Session} --  type=no-view-command avail=all

### EXT games | Games | Quickly launch your installed games.
  PREFS: gameModeEnabled=!1[platform]
  CMD searchGames Game Launcher -- Launch games from Steam, Epic, Xbox, Riot, and more. type=view-command avail=all
  CMD game e=>e.payload.name --   avail=all

### EXT mcp | MCP | Connect external tools and data sources using the Model Context Protocol (MCP).
  CMD installServer Install MCP Server -- Install a new Model Context Protocol server to use with Raycast AI type=view-command avail=all
  CMD manageServers Manage MCP Servers -- Manage and configure your installed Model Context Protocol servers type=view-command avail=all
  CMD aiExtension Ask MCP --  type=ai-extension-command avail=ue
  CMD server e=>Ask ${e.payload.title} --  type=ai-extension-command avail=all

### EXT navigation | Navigation | None
  CMD switchWindows Switch Windows -- See list of open windows from all your running apps and switch instantly. Search for window titles or app names and use the action panel to perform common window or app related actions. type=view-command avail=all
  CMD searchMenuItems Search Menu Bar Items -- Search menu bar items of the active application. type=view-command avail=macOS-only

### EXT notes | Raycast Notes | Create and manage your notes.
  PREFS: showMenuBarToggle=!1[synced]; escapeKeyBehavior=closesWindow[synced]; zoom=1[local]
  CMD open Raycast Notes -- Open Raycast Notes  avail=all
  CMD search Search Notes -- Search through your notes type=view-command avail=all
  CMD create Create Note -- Create a new note  avail=all
  CMD aiExtension Ask Raycast Notes --  type=ai-extension-command avail=all

### EXT organizations | Raycast for Teams | Manage your Raycast organizations.
  CMD manageOrganizations Manage Organizations -- Manage your organizations and members. type=view-command avail=all
  CMD createOrganization Create Organization -- Create organization to get access to team features. type=view-command avail=all
  CMD copyOrganizationInvite Copy Organization Invite Link -- Copy a link which can be used to invite other members to your organization.  avail=all
  CMD manageWebhooks Manage Webhooks -- Manage the webhooks of your organization to receive notifications about changes in your team. type=view-command avail=all
  CMD createWebhook Create Webhook -- Create a webhook for your organization to receive notifications about changes in your team. type=view-command avail=all
  CMD preference e=>e.payload.name --   avail=all

### EXT quicklinks | Quicklinks | Create links to open your frequently used websites and apps.
  PREFS: showPreviews=!0[synced]; preferExistingTabs=!1[synced]; passSelectedTextAsArgument=!1[synced]
  CMD create Create Quicklink -- Create a new quicklink. type=view-command avail=all
  CMD createWithURL Create Quicklink -- Create a new quicklink. type=view-command avail=all
  CMD search Search Quicklinks -- Search all your quicklinks. type=view-command avail=all
  CMD import Import Quicklinks -- Import quicklinks from a file or URL. type=view-command avail=all
  CMD export Export Quicklinks -- Export all quicklinks. type=view-command avail=all
  CMD aiExtension Ask Quicklinks --  type=ai-extension-command avail=oe
  CMD quicklink e=>e.payload.name --  type=no-view-command avail=all

### EXT raycast-account | Account | Manage your Raycast Account.
  CMD logout Log Out -- Log out of your Raycast Account.  avail=all

### EXT raycast-core | Raycast | A set of core commands provided out of the box.
  PREFS: widgetLayout=void 0[local]; weatherLocation=[local]; weatherUnits=automatic[local]; scheduledExportFrequency=none[synced]; scheduledExportAutoDelete=never[synced]; scheduledExportLocation=void 0[local]; scheduledExportSkipOnBattery=!0[synced]; showWhatsNew=!0[synced]
  CMD installUpdate Install Update -- Install the latest update for Raycast.  avail=all
  CMD upgradeToV2 Upgrade to Raycast 2.0 -- Learn what's new in Raycast 2.0 and install the update.  avail=all
  CMD whatsNew Release Notes -- See what's new in the latest version of Raycast.  avail=all
  CMD announcement Announcement -- An announcement from Raycast.  avail=all
  CMD getStarted Get Started with Raycast -- Open the Quickstart guide.  avail={macos:internal,windows:production}
  CMD sessionExpired Sign In Again -- Your Raycast session has expired. Sign in again to restore syncing and AI.  avail=all
  CMD checkForUpdates Check for Updates -- Check for updates for Raycast.  avail=all
  CMD checkForExtensionUpdates Check for Extension Updates -- Check and install updates for all installed extensions.  avail=all
  CMD forceUpdateAllExtensions Force Update All Extensions -- Force update all installed extensions, regardless of version.  avail=all
  CMD quitApp Quit Raycast -- Quits the application.  avail=all
  CMD openSettings Settings -- Open the settings window.  avail=all
  CMD showOnboarding Show Onboarding -- Show Raycast onboarding.  avail=all
  CMD proWalkthrough Open Pro Walkthrough -- Discover the features included with Raycast Pro.  avail=all
  CMD resetPosition Reset Raycast Window Position -- Reset Raycast window position.  avail=all
  CMD confetti Confetti -- Show confetti.  avail=all
  CMD toggleBounceAnimation Toggle Bounce Animation -- Toggle bounce animation - makes the window bounce around the screen.  avail=macOS-only
  CMD inspectWebView Inspect WebView -- Open WebView inspector for the frontmost window.  avail={macos:internal}
  CMD fixLoginItems Fix Login Items -- Unregister and re-register Raycast's Login Items to repair broken background item records.  avail={macos:internal}
  CMD togglePerformanceLogs Toggle Performance Logs -- Enable or disable performance logs for Raycast.  avail=all
  CMD showThemeStudio Show Theme Studio -- Open the Theme Studio window.  avail=all
  CMD switchTheme Switch Theme -- Preview and apply installed themes. type=view-command avail=all
  CMD openManual Open Manual -- Open the Raycast Manual.  avail=all
  CMD askManual Ask Manual --  type=ai-extension-command avail=all
  CMD sendFeedback Send Feedback -- Send feedback to the Raycast team.  avail=all
  CMD askFeedback Ask Feedback --  type=ai-extension-command avail=all
  CMD changelog Changelog -- View the changelog. type=view-command avail=all
  CMD openSearchStore Store -- One place for all Raycast extensions. type=view-command avail=all
  CMD askStore Ask Store --  type=ai-extension-command avail=ae
  CMD shareRaycast Share Raycast -- Refer Raycast to get one month Raycast Pro for free. type=view-command avail=all
  CMD copyRaycastVersion Copy Raycast Version -- Copy the version of Raycast.  avail=all
  CMD copyLogFiles Copy Raycast Logs -- Copy recent log files to the clipboard.  avail=all
  CMD investigateLogFiles Investigate Raycast Logs -- Open a new AI Chat with recent log files attached.  avail=all
  CMD revealLogFiles Reveal Raycast Logs -- Reveal log files in Finder.  avail=all
  CMD createMemoryDump Create Raycast Memory Dump -- Capture a memory dump of all Raycast processes and reveal it in Explorer.  avail=Windows-only
  CMD windowCapture Capture Window -- Capture a Raycast window to share it, or add a screenshot of your extension to the Store.  avail=all
  CMD openCamera Open Camera -- Open camera to preview inside Raycast. type=view-command avail=macOS-only
  CMD exportSettingsAndData Export Settings & Data -- Export Raycast settings and data for backup or to transfer them to another computer. type=view-command avail=all
  CMD importSettingsAndData Import Settings & Data -- Import Raycast settings and data from another computer.  avail=all
  CMD migrateClassicSettingsData Migrate from Raycast v1 -- Migrate settings and data from Raycast v1.  avail=macOS-only
  CMD becomeAnAffiliate Become an Affiliate -- Earn a 30% commission on all payments coming from users you brought to Raycast Pro.  avail=all
  CMD openAffiliateDashboard Open Affiliate Dashboard -- Manage your leads, see your earnings, and find your affiliate link.  avail=all

### EXT raycast-debug | Debug | A set of commands that come in handy during development. The commands are only available in debug or internal builds.
  CMD memoryHistory Memory History --  type=view-command avail=all
  CMD activateRaycastPalette Activate Raycast Palette --  type=view-command avail={macos:internal}
  CMD createDebugClipboardHistory Create Debug Clipboard History Items --  type=no-view-command avail=all
  CMD showHudFadeTest Show HUD (Fade Out Test) --  type=no-view-command avail=all

### EXT raycast-settings | Raycast Settings | Shortcuts to various Raycast Settings.
  CMD aiExtension Ask Raycast Settings --  type=ai-extension-command avail=se
  CMD openAccountSettings Account -- Manage your Raycast account, sign in state, and subscription.  avail=all
  CMD openGeneralSettings General -- Configure appearance, startup behavior, and the Raycast hotkey.  avail=all
  CMD openLauncherSettings Launcher -- Customize your root search experience  avail=all
  CMD openShortcutsSettings Shortcuts -- Manage command hotkeys and aliases across Raycast.  avail=all
  CMD openKeyboardSettings Keyboard -- Configure keyboard behavior, navigation bindings, input sources, and Hyper Key.  avail=all
  CMD openCloudSyncSettings Cloud Sync -- Enable cloud sync for settings and content across devices.  avail=all
  CMD openAdvancedSettings Advanced -- Tune launcher behavior, exporting, and connectivity.  avail=all
  CMD openOrganizationsSettings Organizations -- Manage organizations, members, and organization settings.  avail=all
  CMD openInternalSettings Internal -- Development-only toggles and internal debugging settings.  avail=all
  CMD openAboutSettings About -- Check for updates, view links, and open feedback destinations.  avail=all

### EXT raycast-wrapped | Raycast Wrapped | View your Raycast year in review
  CMD showRaycastWrapped Raycast Wrapped -- View your Raycast 2026 year in review type=view-command avail=all

### EXT screen-awareness | Screen Awareness | Capture context from your screen and send it to AI
  PREFS: setupCompletedAt=null[platform]; setupCompletionSource=null[platform]; launcherSetupSkippedAt=null[local]
  CMD sendSelectedText Send Selected Text to AI -- Send the selected text from the active app to AI  avail=all
  CMD sendScreen Send Screen to AI -- Capture the full screen and send it to AI  avail=all
  CMD sendScreenArea Send Screen Area to AI -- Select a screen area and send it to AI  avail=all
  CMD sendWindow Send Window to AI -- Select a window and attach its screenshot to AI  avail={macos:production}
  CMD sendElement Send Element to AI -- Select an interface element and attach its screenshot and accessible context to AI  avail={macos:production}
  CMD sendFocusedWindow Send Focused Window to AI -- Capture context from the focused window and send it to AI  avail=all
  CMD aiExtension Ask Screen Awareness --  type=ai-extension-command avail=all

### EXT screenshots | Screenshots | Search and manage your screenshots.
  PREFS: columnCount=3[synced]; includeAllMedia=!1[synced]; textRecognitionEnabled=!0[synced]; ocrLevel=void 0[synced]; storageDuration=unlimited[synced]; allowCloudFileOcr=!1[platform]; searchDirectories=void 0[platform]; hasOpenedSearchScreenshots=!1[local]; hasActivatedIndexing=!1[local]; selectedCategory=all[local]
  CMD searchScreenshots Search Screenshots -- Search through your screenshots type=view-command avail=all
  CMD pasteLatestScreenshot Paste Latest Screenshot -- Paste your most recent screenshot to the active app  avail=all

### EXT script-commands | Script Commands | Run script commands from configured directories
  PREFS: searchDirectories=[][platform]
  CMD searchScriptCommands Search Script Commands -- Search and run all your script commands type=view-command avail=all
  CMD createScriptCommand Create Script Command -- Create a new script command from a template type=view-command avail=all
  CMD reloadScriptCommands Reload Script Commands -- Rescan script directories and reload all script commands  avail=all

### EXT snippets | Snippets | Snippets provide quick access to short snippets of text, code, etc..
  PREFS: autoExpansionEnabled=!0[synced]; paletteInjectionEnabled=!1[local]; responseTime=Default[synced]; expansionMode=Immediately[synced]; expandWithinWords=!1[synced]; overrideSystemSnippets=!1[synced]; injectionDelay=None[synced]; showPinnedSnippetTagsBar=!1[local]; completionSound=null[platform]; disabledApplications=[][platform]
  CMD createSnippet Create Snippet -- Create a new snippet type=view-command avail=all
  CMD searchSnippets Search Snippets -- Search for a snippet type=view-command avail=all
  CMD autoSnippet Auto Snippet -- Insert the snippet that best fits your current context type=no-view-command avail={macos:internal}
  CMD importSnippets Import Snippets -- Import snippets type=view-command avail=all
  CMD exportSnippets Export Snippets -- Export all snippets type=view-command avail=all
  CMD aiExtension Ask Snippets --  type=ai-extension-command avail=le

### EXT system | System Actions | A set of system commands provided out of the box.
  PREFS: favoriteNetworks=[][local]; favoriteDeviceIds=[][local]
  CMD dismissNotifications Dismiss Notifications -- Close all notifications or alerts on the screen.  avail=macOS-only
  CMD ejectAllDisks Eject All Disks -- Eject all mounted disk images.  avail=macOS-only
  CMD openTrash m({macos:Open Trash,windows:Open Recycle Bin}) -- m({macos:Open Trash in Finder,windows:Open Recycle Bin in Explorer})  avail=all
  CMD emptyTrash m({macos:Empty Trash,windows:Empty Recycle Bin}) -- m({macos:Empty the Trash,windows:Empty the Recycle Bin})  avail=all
  CMD hideAllAppsExceptFrontmost Hide All Apps Except Frontmost -- View the front app but hide all other apps.  avail=all
  CMD lockScreen Lock Screen -- Lock the screen of your computer.  avail=all
  CMD logOut Log Out -- Log out from current user.  avail=all
  CMD quitAllApplications Quit All Apps -- Quits all running applications.  avail=all
  CMD quitAllApplicationsExceptFrontmost Quit All Apps Except Frontmost -- Quits all running applications except the frontmost app.  avail=all
  CMD quitActiveApplication Quit the Active App -- Close the active app's window (equivalent of Alt+F4).  avail=Windows-only
  CMD restart Restart -- Restart your computer.  avail=all
  CMD wifiNetworks Manage Wi-Fi Connections -- Connect to saved networks and manage WiFi preferences. type=view-command avail=Windows-only
  CMD bluetoothDevices Manage Bluetooth Devices -- Manage paired Bluetooth devices. type=view-command avail=Windows-only
  CMD appVolume Volume Mixer -- Adjust or mute the volume of individual apps that are playing audio. type=view-command avail=Windows-only
  CMD setSoundOutputDevice Set Sound Output Device -- Choose which speakers, headphones or display play your computer's audio. type=view-command avail={windows:internal}
  CMD setSoundInputDevice Set Sound Input Device -- Choose which microphone your computer records from. type=view-command avail={windows:internal}
  CMD toggleMuteCurrentApp Toggle Active App Mute -- Mute or unmute the active app.  avail=Windows-only
  CMD turnCurrentAppVolumeUp Turn Active App Volume Up -- Turn up the volume of the active app.  avail=Windows-only
  CMD turnCurrentAppVolumeDown Turn Active App Volume Down -- Turn down the volume of the active app.  avail=Windows-only
  CMD setVolume Set Volume -- Set the volume of your computer.  avail=all
  CMD setVolume0 Set Volume to 0% -- Set the volume of your computer to 0%.  avail=all
  CMD setVolume25 Set Volume to 25% -- Set the volume of your computer to 25%.  avail=all
  CMD setVolume50 Set Volume to 50% -- Set the volume of your computer to 50%.  avail=all
  CMD setVolume75 Set Volume to 75% -- Set the volume of your computer to 75%.  avail=all
  CMD setVolume100 Set Volume to 100% -- Set the volume of your computer to 100%.  avail=all
  CMD playPause Play / Pause -- Play or pause the current track.  avail=all
  CMD nextTrack Next Track -- Play the next track.  avail=all
  CMD previousTrack Previous Track -- Play the previous track.  avail=all
  CMD showDesktop Show Desktop -- Show the desktop.  avail=all
  CMD showScreenSaver Show Screen Saver -- Start the screen saver.  avail=all
  CMD shutDown Shut Down -- Shut down your computer.  avail=all
  CMD sleep Sleep -- Put your computer to sleep.  avail=all
  CMD hibernate Hibernate -- Hibernate your computer.  avail=Windows-only
  CMD sleepDisplays Sleep Displays -- Put the displays of your computer to sleep.  avail=all
  CMD toggleWifi Toggle WiFi -- Toggle WiFi on and off.  avail=Windows-only
  CMD toggleAirplaneMode Toggle Airplane Mode -- Toggle airplane mode on and off.  avail=Windows-only
  CMD toggleBluetooth Toggle Bluetooth -- Toggle Bluetooth on and off.  avail=all
  CMD toggleCameraMute Toggle Camera Mute -- Block or restore camera access for every app.  avail=Windows-only
  CMD toggleEnergySaver Toggle Energy Saver -- Toggle Energy Saver on and off.  avail=Windows-only
  CMD toggleHiddenFiles Toggle Hidden Files -- Show or hide hidden files.  avail=all
  CMD toggleMute Toggle Mute -- Mute or unmute your computer's speaker.  avail=all
  CMD toggleStageManager Toggle Stage Manager -- Toggle built-in Stage Manager.  avail=macOS-only
  CMD toggleSystemAppearance m({macos:Toggle System Appearance,windows:Toggle Dark Mode}) -- m({macos:Toggle the system appearance.,windows:Toggle dark mode on and off.})  avail=all
  CMD toggleHdr Toggle HDR -- Toggle HDR on and off.  avail=Windows-only
  CMD toggleNightLight Toggle Night Light -- Toggle Night Light on and off.  avail=Windows-only
  CMD toggleMicrophoneMute Toggle Microphone Mute -- Mute or unmute every connected microphone.  avail=Windows-only
  CMD turnVolumeDown Turn Volume Down -- Turn down the volume of your computer.  avail=all
  CMD turnVolumeUp Turn Volume Up -- Turn up the volume of your computer.  avail=all
  CMD unhideAllHiddenApps Unhide All Hidden Apps -- Show all hidden apps.  avail=macOS-only

### EXT translator | Translator | Quickly translate text between languages.
  PREFS: defaultSourceLanguage=null[synced]; defaultTargetLanguage=null[synced]; primaryAction=copy[synced]; prefillFromSelectedText=!1[synced]
  CMD translate Translate -- Translate any text into other languages type=view-command avail=all
  CMD quickTranslate e=>Translate to ${e.payload.query.targetLanguageLabel} -- e=>e.payload.query.phrase type=no-view-command avail=all
  CMD customTranslate e=>e.payload.name --  type=view-command avail=all

### EXT trial-nudges | Trial Nudges | Contextual nudges for the Raycast Pro trial.
  PREFS: trialScenario=null[local]; featureNudgePreview=null[local]
  CMD welcomePro Welcome to Pro --   avail=all
  CMD startTrial Level up, sign in and start a 7-day free trial -- Discover powerful features with a free Raycast Pro trial.  avail=all
  CMD chargeReminder Continue Pro after your trial --   avail=all

### EXT typing-practice | Typing Practice | Practice your typing easily
  CMD startTypingPractice Start Typing Practice -- Start new typing practice session type=view-command avail=all

### EXT urls | URL | Set of URL-related commands.
  CMD quickOpen Open in Browser -- Open URL in default browser  avail=all

### EXT web-searches | Web Searches | Quickly search for text on web.
  CMD google Google Search -- Search the web with Google Search  avail=all
  CMD duckDuckGo DuckDuckGo Search -- Search the web with DuckDuckGo Search  avail=all
  CMD bing Bing -- Search the web with Bing  avail=all

### EXT window-management | Window Management | Move and resize your application windows.
  PREFS: innerGap=0[synced]; outerGap=0[synced]; cycleMode=sizes[synced]; respectStageManager=!1[synced]; autoCloseEmptyDesktops=!1[platform]
  CMD maximize Maximize -- Maximize focused window to fit the screen.  avail=all
  CMD restore Restore -- Restore focused window to its last position.  avail=all
  CMD minimize Minimize -- m({macos:Minimize focused window to the Dock.,windows:Minimize focused window to the taskbar.})  avail=all
  CMD minimizeOnDisplay Minimize on This Display -- Minimize all windows on the display where Raycast is open.  avail=all
  CMD maximizeHeight Maximize Height -- Maximize height of focused window to fit the screen.  avail=all
  CMD maximizeWidth Maximize Width -- Maximize width of focused window to fit the screen.  avail=all
  CMD maximizeAlmost Almost Maximize -- Maximize focused window to almost fit the screen.  avail=all
  CMD reasonableSize Reasonable Size -- Resize focused window to 60% of the screen (Maximum: 1024x900).  avail=all
  CMD resizeWindow Resize Window -- Resize focused window to an exact width and height.  avail=all
  CMD center Center -- Center focused window in screen.  avail=all
  CMD centerHalf Center Half -- Resize focused window to the half of the screen and center.  avail=all
  CMD leftHalf Left Half -- Resize focused window to the left half of the screen.  avail=all
  CMD rightHalf Right Half -- Resize focused window to the right half of the screen.  avail=all
  CMD topHalf Top Half -- Resize focused window to the top half of the screen.  avail=all
  CMD bottomHalf Bottom Half -- Resize focused window to the bottom half of the screen.  avail=all
  CMD firstThird First Third -- Resize focused window to the first third of the screen.  avail=all
  CMD centerThird Center Third -- Resize focused window to the center third of the screen.  avail=all
  CMD lastThird Last Third -- Resize focused window to the last third of the screen.  avail=all
  CMD firstTwoThird First Two Thirds -- Resize focused window to the first two thirds of the screen.  avail=all
  CMD centerTwoThird Center Two Thirds -- Resize focused window to the center two thirds of the screen.  avail=all
  CMD lastTwoThird Last Two Thirds -- Resize focused window to the last two thirds of the screen.  avail=all
  CMD firstThreeFourth First Three Fourths -- Resize focused window to the first three fourths of the screen.  avail=all
  CMD centerThreeFourth Center Three Fourths -- Resize focused window to the center three fourths of the screen.  avail=all
  CMD lastThreeFourth Last Three Fourths -- Resize focused window to the last three fourths of the screen.  avail=all
  CMD topThird Top Third -- Resize focused window to the top third of the screen.  avail=all
  CMD middleThird Middle Third -- Resize focused window to the vertical middle third of the screen.  avail=all
  CMD bottomThird Bottom Third -- Resize focused window to the bottom third of the screen.  avail=all
  CMD topTwoThird Top Two Thirds -- Resize focused window to the top two thirds of the screen.  avail=all
  CMD bottomTwoThird Bottom Two Thirds -- Resize focused window to the bottom two thirds of the screen.  avail=all
  CMD topFirstFourth Top First Fourth -- Resize focused window to the top first fourth of the screen.  avail=all
  CMD topSecondFourth Top Second Fourth -- Resize focused window to the top second fourth of the screen.  avail=all
  CMD topThirdFourth Top Third Fourth -- Resize focused window to the top third fourth of the screen.  avail=all
  CMD topLastFourth Top Last Fourth -- Resize focused window to the top last fourth of the screen.  avail=all
  CMD topThreeFourth Top Three Fourths -- Resize focused window to the top three fourths of the screen.  avail=all
  CMD bottomThreeFourth Bottom Three Fourths -- Resize focused window to the bottom three fourths of the screen.  avail=all
  CMD topCenterTwoThird Top Center Two Thirds -- Resize focused window to the top center two thirds of the screen.  avail=all
  CMD bottomCenterTwoThird Bottom Center Two Thirds -- Resize focused window to the bottom center two thirds of the screen.  avail=all
  CMD firstFourth First Fourth -- Resize focused window to the first fourth of the screen.  avail=all
  CMD secondFourth Second Fourth -- Resize focused window to the second fourth of the screen.  avail=all
  CMD thirdFourth Third Fourth -- Resize focused window to the third fourth of the screen.  avail=all
  CMD lastFourth Last Fourth -- Resize focused window to the last fourth of the screen.  avail=all
  CMD topLeftSixth Top Left Sixth -- Resize focused window to the top left sixth of the screen.  avail=all
  CMD topCenterSixth Top Center Sixth -- Resize focused window to the top center sixth of the screen.  avail=all
  CMD topRightSixth Top Right Sixth -- Resize focused window to the top right sixth of the screen.  avail=all
  CMD bottomLeftSixth Bottom Left Sixth -- Resize focused window to the bottom left sixth of the screen.  avail=all
  CMD bottomCenterSixth Bottom Center Sixth -- Resize focused window to the bottom center sixth of the screen.  avail=all
  CMD bottomRightSixth Bottom Right Sixth -- Resize focused window to the bottom right sixth of the screen.  avail=all
  CMD moveLeft Move Left -- Move focused window to the left edge of the screen.  avail=all
  CMD moveRight Move Right -- Move focused window to the right edge of the screen.  avail=all
  CMD moveTop Move Top -- Move focused window to the top edge of the screen.  avail=all
  CMD moveBottom Move Bottom -- Move focused window to the bottom edge of the screen.  avail=all
  CMD moveWindow Move Window -- Move focused window to exact coordinates on its display.  avail=all
  CMD movePreviousDesktop m({macos:Move to Previous Space,windows:Move to Previous Desktop}) -- e=>Move focused window to the previous ${e.payload.desktopName.toLowerCase()}.  avail=all
  CMD moveNextDesktop m({macos:Move to Next Space,windows:Move to Next Desktop}) -- e=>Move focused window to the next ${e.payload.desktopName.toLowerCase()}.  avail=all
  CMD switchToPreviousSpace Switch to Previous Space -- Switch to the previous space.  avail=macOS-only
  CMD switchToNextSpace Switch to Next Space -- Switch to the next space.  avail=macOS-only
  CMD movePreviousDisplay Move to Previous Display -- Move focused window to the previous display.  avail=all
  CMD moveNextDisplay Move to Next Display -- Move focused window to the next display.  avail=all
  CMD topLeftQuarter Top Left Quarter -- Resize focused window to the top left quarter of the screen.  avail=all
  CMD topRightQuarter Top Right Quarter -- Resize focused window to the top right quarter of the screen.  avail=all
  CMD bottomLeftQuarter Bottom Left Quarter -- Resize focused window to the bottom left quarter of the screen.  avail=all
  CMD bottomRightQuarter Bottom Right Quarter -- Resize focused window to the bottom right quarter of the screen.  avail=all
  CMD makeSmaller Make Smaller -- Decrease the focused window until it reaches 25% of the screen.  avail=macOS-only
  CMD makeLarger Make Larger -- Increase the focused window until it reaches the screen size.  avail=macOS-only
  CMD toggleFullscreen Toggle Fullscreen -- Toggle fullscreen mode of focused window.  avail=macOS-only
  CMD toggleAlwaysOnTop Toggle Always on Top -- Pin the focused window above all other windows.  avail=Windows-only
  CMD focusNextAppWindow Focus Next App Window -- Focus the next window of the app you are using. Press repeatedly to cycle through all of its windows.  avail=Windows-only
  CMD focusPreviousAppWindow Focus Previous App Window -- Focus the previous window of the app you are using. Press repeatedly to cycle through all of its windows.  avail=Windows-only
  CMD gridPlacement Toggle Grid Overlay -- Visually place a window on a custom grid region.  avail=macOS-only
  CMD createWindowManagementCommand Create Command -- Create a custom window management command.  avail=all
  CMD createWindowManagementLayout Create Layout -- Create a custom window layout to arrange multiple app windows.  avail=all
  CMD captureWindowManagementLayout Save Current Layout -- Turn the windows currently on screen into a custom window layout you can tweak and save.  avail=all
  CMD importWindowManagementCommands m({macos:Import Commands & Layouts,windows:Import Commands}) -- Import custom window management commands and layouts from a JSON file.  avail=all
  CMD switchDesktop Switch Desktops -- See a list of virtual desktops and switch to one. type=view-command avail=Windows-only
  CMD openDesktop Open Desktop -- Switch to a specific desktop by index.  avail=Windows-only
  CMD moveWindowToDesktop Move to Desktop -- Move active window to a specific desktop by index.  avail=Windows-only
  CMD closeActiveDesktop Close Desktop Active -- Close the active virtual desktop.  avail=Windows-only
  CMD closeDesktop Close Desktop -- Close a specific virtual desktop by index.  avail=Windows-only
  CMD renameActiveDesktop Rename Desktop Active -- Rename the active virtual desktop.  avail=Windows-only
  CMD renameDesktop Rename Desktop -- Rename a specific virtual desktop by index.  avail=Windows-only
  CMD openDesktop1 Open Desktop 1 -- Switch to desktop 1.  avail=Windows-only
  CMD openDesktop2 Open Desktop 2 -- Switch to desktop 2.  avail=Windows-only
  CMD openDesktop3 Open Desktop 3 -- Switch to desktop 3.  avail=Windows-only
  CMD openDesktop4 Open Desktop 4 -- Switch to desktop 4.  avail=Windows-only
  CMD openDesktop5 Open Desktop 5 -- Switch to desktop 5.  avail=Windows-only
  CMD openDesktop6 Open Desktop 6 -- Switch to desktop 6.  avail=Windows-only
  CMD openDesktop7 Open Desktop 7 -- Switch to desktop 7.  avail=Windows-only
  CMD openDesktop8 Open Desktop 8 -- Switch to desktop 8.  avail=Windows-only
  CMD openDesktop9 Open Desktop 9 -- Switch to desktop 9.  avail=Windows-only
  CMD openDesktop10 Open Desktop 10 -- Switch to desktop 10.  avail=Windows-only
  CMD moveWindowToDesktop1 Move to Desktop 1 -- Move active window to desktop 1.  avail=Windows-only
  CMD moveWindowToDesktop2 Move to Desktop 2 -- Move active window to desktop 2.  avail=Windows-only
  CMD moveWindowToDesktop3 Move to Desktop 3 -- Move active window to desktop 3.  avail=Windows-only
  CMD moveWindowToDesktop4 Move to Desktop 4 -- Move active window to desktop 4.  avail=Windows-only
  CMD moveWindowToDesktop5 Move to Desktop 5 -- Move active window to desktop 5.  avail=Windows-only
  CMD moveWindowToDesktop6 Move to Desktop 6 -- Move active window to desktop 6.  avail=Windows-only
  CMD moveWindowToDesktop7 Move to Desktop 7 -- Move active window to desktop 7.  avail=Windows-only
  CMD moveWindowToDesktop8 Move to Desktop 8 -- Move active window to desktop 8.  avail=Windows-only
  CMD moveWindowToDesktop9 Move to Desktop 9 -- Move active window to desktop 9.  avail=Windows-only
  CMD moveWindowToDesktop10 Move to Desktop 10 -- Move active window to desktop 10.  avail=Windows-only
  CMD layoutGroup e=>e.payload.name --   avail=all

### EXT windows-run | Run | Improved version of the Windows Run dialog with quality of life features.
  PREFS: shell=null[platform]
  CMD windowsRun Open Run -- Quickly run system binaries, access environment variables, and more. type=view-command avail=all
  CMD windowsRunWithArgument Execute Run Command -- Execute a command directly without opening the Run view.  avail=all
  CMD searchRunCommands Search Run Commands -- Search and manage custom run command aliases. type=view-command avail=all
  CMD createRunCommand Create Run Command -- Create a new custom run command with an alias. type=view-command avail=all
  CMD runCommand e=>e.payload.alias.charAt(0).toUpperCase()+e.payload.alias.slice(1) --   avail=all

### EXT windows-taskbar | Taskbar | Customizable taskbar behaviour.
  PREFS: showTaskbar=!1[local]; disableWindowsTaskbar=!1[local]; position=bn[local]; sidebar=!1[local]; compact=!1[local]; size=Cn[local]; widgets=En[local]
  CMD toggleTaskbar Toggle Taskbar Window --   avail=all
```

### A.2 Command-level preferences, keywords, fallback eligibility (verbatim)

```
browser.aiExtension Ask Browser kw=@browser fallback=available
calculator.aiExtension Ask Calculator kw=@calculator,math,convert,calculate fallback=available
calendar.aiExtension Ask Calendar kw=@calendar fallback=available
clipboard-history.pasteSequential Paste Sequentially 
    pref addNewLine (checkbox, default !0): Add a new line after pasting text
clipboard-history.aiExtension Ask Clipboard kw=@clipboard fallback=available
contacts.search Search Contacts fallback=available
developer.importExtension Import Extension kw=install
developer.createExtension Create Extension kw=new extension
developer.aiExtension Ask Developer kw=@developer,extension,development fallback=available
dictation.dictateText Dictate kw=speech,voice,transcription,microphone,dictation
dictation.dictateToAi Dictate to AI kw=speech,voice,transcription,microphone,dictation,ai,chat,prompt
dictation.dictateToNote Dictate to Note kw=speech,voice,transcription,microphone,dictation,note
dictation.copyLastTranscription Get Last Transcription kw=dictation,transcription,speech,voice,copy,clipboard,paste,recover
dictation.addWordToVocabulary Add Word to Vocabulary kw=vocabulary,word,dictation,selection,add,term
dictation.searchTranscriptions Dictation History kw=dictation,transcription,speech,voice,history
dictation.aiExtension Ask Dictation kw=@dictation,transcription,speech,voice,history,style,styles fallback=available
dictation.openDictationCustomInstructions Custom Instructions kw=custom instructions,dictation,personalization,profile,prompt
dictation.openDictationVocabulary Vocabulary kw=vocabulary,words,custom,dictation,personalization
dictation.createTranscriptionStyle Create Style kw=new style,dictation,transcription
dictation.searchTranscriptionStyles Search Styles kw=dictation
dictation.setUpDictation Get Started with Dictation kw=setup,configure,permissions,microphone,hotkey,dictation
dictionary.defineWord Define Word kw=lexicon,thesaurus,glossary,spell fallback=available
emoji-picker.searchEmoji Search Emoji & Symbols fallback=available
file-search.searchFiles Search Files fallback=available
file-search.aiExtension Ask Finder kw=@finder fallback=available
file-search.fileExplorerAiExtension Ask File Explorer kw=@file-explorer fallback=available
file-search.fileSearchAiExtension Ask File Search kw=@file-search fallback=available
raycast-focus.createCategory Create Focus Category kw=new focus category
raycast-focus.importCategories Import Focus Categories kw=import focus categories
raycast-focus.aiExtension Ask Raycast Focus kw=@raycast-focus,focus fallback=available
games.searchGames Game Launcher fallback=available
mcp.aiExtension Ask MCP kw=@mcp,model context protocol fallback=available
mcp.server e=>Ask ${e.payload.title} fallback=available
navigation.switchWindows Switch Windows kw=windows switch,window switcher
navigation.searchMenuItems Search Menu Bar Items fallback=available
notes.open Raycast Notes kw=notes
notes.create Create Note kw=new note fallback=available
notes.aiExtension Ask Raycast Notes kw=@raycast-notes,notes fallback=available
quicklinks.create Create Quicklink kw=new quicklink fallback=available
    pref autofill (checkbox, default !0): Autofill from current app or clipboard -- Prefill the link and name from the frontmost app, or from a URL or file path in the clipboard.
quicklinks.search Search Quicklinks fallback=available
quicklinks.aiExtension Ask Quicklinks kw=@quicklinks,quicklinks fallback=available
quicklinks.quicklink e=>e.payload.name kw=quicklink
raycast-core.openSettings Settings kw=preferences
raycast-core.showOnboarding Show Onboarding kw=welcome
raycast-core.proWalkthrough Open Pro Walkthrough kw=trial,welcome
raycast-core.resetPosition Reset Raycast Window Position kw=recenter
raycast-core.confetti Confetti 
    pref showHolidayConfetti (checkbox, default !0): Use seasonal holiday confetti
raycast-core.fixLoginItems Fix Login Items kw=btm,background,updater,launch agent
raycast-core.togglePerformanceLogs Toggle Performance Logs kw=metrics,performance
raycast-core.askManual Ask Manual kw=@manual,documentation,docs,help,support fallback=available
raycast-core.askFeedback Ask Feedback kw=@raycast-feedback,bug report,feature request,billing,support fallback=available
raycast-core.changelog Changelog kw=whats new,what's new,see whats new,release notes
raycast-core.openSearchStore Store kw=extensions fallback=available
raycast-core.askStore Ask Store kw=@store,extensions fallback=available
raycast-core.shareRaycast Share Raycast kw=referral
raycast-core.investigateLogFiles Investigate Raycast Logs kw=fix yourself
raycast-core.windowCapture Capture Window kw=screenshot
    pref copyToClipboard (checkbox, default !0): Copy to clipboard
raycast-core.openCamera Open Camera 
    pref shutterSound (checkbox, default !0): Play shutter sound
raycast-core.exportSettingsAndData Export Settings & Data kw=backup
raycast-core.importSettingsAndData Import Settings & Data kw=backup
raycast-debug.memoryHistory Memory History kw=RAM
raycast-settings.aiExtension Ask Raycast Settings kw=@raycast-settings,settings,preferences fallback=available
raycast-settings.openAccountSettings Account kw=account,advanced ai,login,logout,profile,pro,sign in,sign out,subscription
raycast-settings.openGeneralSettings General kw=appearance,compact,dark,expanded,hotkey,light,menu bar,open at login,startup,system tray,theme,window mode
raycast-settings.openLauncherSettings Launcher kw=fallback,root search,manage fallback
raycast-settings.openShortcutsSettings Shortcuts kw=aliases,applications,commands,extensions,hotkeys,keybindings,keyboard,quicklinks
raycast-settings.openKeyboardSettings Keyboard kw=caps lock,emacs,escape key,hyper key,input source,keyboard,navigation,vim
raycast-settings.openCloudSyncSettings Cloud Sync kw=backup,cloud,raycast pro,sync
raycast-settings.openAdvancedSettings Advanced kw=backup,certificate,connection,export,favicon,pop to root,proxy,scheduled backup,search sensitivity,show raycast on,window activation behavior,tidy menu bar
raycast-settings.openOrganizationsSettings Organizations kw=invite,members,organization,org,team,teams,webhooks
raycast-settings.openInternalSettings Internal kw=debug,developer,feature flags,internal,preload,worker,raycast api environment
raycast-settings.openAboutSettings About kw=changelog,community,feedback,support,updates,version,website
screen-awareness.sendWindow Send Window to AI kw=capture,screenshot,window
screen-awareness.sendElement Send Element to AI kw=capture,screenshot,element,control
screen-awareness.sendFocusedWindow Send Focused Window to AI fallback=available
screen-awareness.aiExtension Ask Screen Awareness kw=@screen-awareness,frontmost,focused app fallback=available
script-commands.searchScriptCommands Search Script Commands kw=find,browse,scripts fallback=available
script-commands.createScriptCommand Create Script Command kw=new,create,script,template
script-commands.reloadScriptCommands Reload Script Commands kw=refresh,rescan,reload
snippets.createSnippet Create Snippet kw=new snippet fallback=available
snippets.searchSnippets Search Snippets fallback=available
snippets.autoSnippet Auto Snippet kw=smart snippet,insert snippet fallback=available
snippets.aiExtension Ask Snippets kw=@snippets,snippets fallback=available
    pref showWarning (checkbox, default !0): Show Warning Before Quitting Applications
    pref showWarning (checkbox, default !0): Show Warning Before Quitting the Active App
system.restart Restart kw=reboot
system.wifiNetworks Manage Wi-Fi Connections kw=wifi,wi-fi,wi fi,wireless,network,networks,wlan,internet,connect,connectivity
system.bluetoothDevices Manage Bluetooth Devices kw=bluetooth,blue tooth,bt,devices,pair,headphones,headset,speaker,wireless,connect,connectivity
system.appVolume Volume Mixer kw=app volume,set app volume,mute app,audio mixer
system.setSoundOutputDevice Set Sound Output Device kw=output device,audio output,playback device,speakers,headphones,sound device
system.setSoundInputDevice Set Sound Input Device kw=input device,audio input,recording device,microphone,mic,sound device
system.toggleMuteCurrentApp Toggle Active App Mute kw=mute current app,mute foreground app,mute active app
system.turnCurrentAppVolumeUp Turn Active App Volume Up kw=current app volume up,foreground app volume,active app volume
system.turnCurrentAppVolumeDown Turn Active App Volume Down kw=current app volume down,foreground app volume,active app volume
system.toggleWifi Toggle WiFi kw=wifi,wi-fi,wi fi,wireless,internet
system.toggleAirplaneMode Toggle Airplane Mode kw=flight mode,aeroplane,wireless
system.toggleCameraMute Toggle Camera Mute kw=mute camera,webcam,video mute,camera off
system.toggleEnergySaver Toggle Energy Saver kw=battery saver,power saving,low power mode
system.toggleSystemAppearance m({macos:Toggle System Appearance,windows:Toggle Dark Mode}) kw=theme,dark mode,light mode,system appearance,toggle system appearance
system.toggleHdr Toggle HDR kw=hdr,high dynamic range,display
system.toggleNightLight Toggle Night Light kw=night light,blue light,night mode
system.toggleMicrophoneMute Toggle Microphone Mute kw=mute mic,mute microphone,unmute microphone,mic mute
translator.translate Translate fallback=available
translator.customTranslate e=>e.payload.name fallback=available
typing-practice.startTypingPractice Start Typing Practice fallback=available
window-management.minimize Minimize kw=hide,taskbar,dock
window-management.minimizeOnDisplay Minimize on This Display kw=show desktop,minimize all,hide,monitor,screen
window-management.resizeWindow Resize Window kw=exact,size,dimensions,resolution,pixels,1920x1080
window-management.firstThird First Third kw=left
window-management.lastThird Last Third kw=right
window-management.firstTwoThird First Two Thirds kw=left
window-management.lastTwoThird Last Two Thirds kw=right
window-management.firstThreeFourth First Three Fourths kw=left
window-management.lastThreeFourth Last Three Fourths kw=right
window-management.firstFourth First Fourth kw=left
window-management.lastFourth Last Fourth kw=right
window-management.moveLeft Move Left 
    pref centerWindow (checkbox, default !0): Center Window
window-management.moveRight Move Right 
    pref centerWindow (checkbox, default !0): Center Window
window-management.moveTop Move Top kw=up
    pref centerWindow (checkbox, default !0): Center Window
window-management.moveBottom Move Bottom kw=down
    pref centerWindow (checkbox, default !0): Center Window
window-management.moveWindow Move Window kw=exact,position,coordinates,pixels,place
window-management.movePreviousDesktop m({macos:Move to Previous Space,windows:Move to Previous Desktop}) kw=desktop,space
window-management.moveNextDesktop m({macos:Move to Next Space,windows:Move to Next Desktop}) kw=desktop,space
window-management.switchToPreviousSpace Switch to Previous Space kw=previous space,previous desktop
    pref animated (checkbox, default !1): Animate Switching -- When enabled, use the default space switching animation.
window-management.switchToNextSpace Switch to Next Space kw=next space,next desktop
    pref animated (checkbox, default !1): Animate Switching -- When enabled, use the default space switching animation.
window-management.movePreviousDisplay Move to Previous Display kw=desktop
    pref wrap (checkbox, default !0): Wrap Around Displays
    pref keepAspectRatio (checkbox, default !0): Keep Aspect Ratio
window-management.moveNextDisplay Move to Next Display kw=desktop
    pref wrap (checkbox, default !0): Wrap Around Displays
    pref keepAspectRatio (checkbox, default !0): Keep Aspect Ratio
window-management.toggleAlwaysOnTop Toggle Always on Top kw=pin,topmost,always on top,stay on top
window-management.focusNextAppWindow Focus Next App Window kw=cycle,switch,same app,next window,app windows,foreground
window-management.focusPreviousAppWindow Focus Previous App Window kw=cycle,switch,same app,previous window,app windows,foreground
window-management.gridPlacement Toggle Grid Overlay kw=divvy,grid,spectacle,place,snap
window-management.captureWindowManagementLayout Save Current Layout kw=capture,snapshot,save layout,current windows
window-management.importWindowManagementCommands m({macos:Import Commands & Layouts,windows:Import Commands}) kw=layout,command
window-management.switchDesktop Switch Desktops kw=desktop,virtual desktop,switch
window-management.openDesktop Open Desktop kw=desktop,virtual desktop,switch
window-management.moveWindowToDesktop Move to Desktop kw=desktop,virtual desktop,move
window-management.closeActiveDesktop Close Desktop Active kw=desktop,virtual desktop,remove
window-management.closeDesktop Close Desktop kw=desktop,virtual desktop,remove
window-management.renameActiveDesktop Rename Desktop Active kw=desktop,virtual desktop,rename
window-management.renameDesktop Rename Desktop kw=desktop,virtual desktop,rename
windows-taskbar.toggleTaskbar Toggle Taskbar Window kw=bar,show,hide
```

## Appendix B — Settings page definitions (verbatim titles/descriptions; AI page omitted)

```

## about
  - raycastUpdates: Raycast Updates
  - openChangelog: Open Changelog
  - website: Website
  - slackCommunity: Slack Community
  - sendFeedback: Send Feedback

## advanced
  - windowActivationBehavior: Window Activation Behavior -- Choose whether Raycast brings windows to your current Space or switches to the Space where they are open.
  - faviconProvider: Favicon Provider -- Select the provider used to fetch favicons or None to disable favicon fetching.
  - tidyMenuBar: Tidy Menu Bar -- Hide menu bar items to the left of a special status item when not hovering the menu bar.
  - openFoldersInTabs: Open Folders in Tabs -- Open folders as new tabs in an existing File Explorer window instead of opening new windows.
  - useElevatedUiAccessHelper: Run the Accessibility Helper Elevated -- Turn this on if global shortcuts, snippet expansion, or copying selected text aren't working on your PC. Raycast then launches its input helper with administrator rights via the Raycast System Service. Requires an administrator account — on standard Windows accounts this has no effect, since Windows can't grant elevation without a password prompt. Takes effect after you restart Raycast.
  - recordStallDiagnostics: Diagnostics Services -- Turn this on if searches, keyboard shortcuts, or Raycast in general are slow to respond. Raycast will monitor activity and send diagnostic recordings to the Raycast team when it detects slowdowns. This installs the Raycast System Service with a one-time administrator prompt. Recordings may include process names, file paths, and function names from your computer.
  - export: Export
  - connection: Connection
  - exportPassphrase: Export Passphrase
  - backupFrequency: Scheduled Backup -- Automatically export your Raycast settings and data on a schedule.
  - backupLocation: Backup Location
  - autoDelete: Auto-Delete -- Automatically delete old backups to save disk space.
  - skipOnBattery: Skip on Battery -- Skip scheduled exports while on battery power and run them once back on AC power.
  - useSystemProxySettings: Use System Proxy Settings -- Automatically use your computer's proxy configuration for network connections.
  - additionalCertificateAuthorities: Additional Certificate Authority -- Choose a certificate file (.crt, .cer, .pem) to trust connections that would otherwise show security warnings or fail.

## applications
  - autoQuit: Auto Quit -- Automatically quit apps shortly after you stop using them.
  - hotkeyBehavior: Hotkey Action -- Behavior when triggering an application hotkey.
  - directories: Search Scopes -- Pick additional folders to be included when searching for Applications
  - recursiveSearch: Deep Search -- Search up to 3 levels deep inside added directories

## clipboard
  - keepHistoryFor: Keep history for
  - textRecognitionEnabled: Text Recognition -- Text content in images will be automatically extracted and can be searched.
  - recognitionMode: Recognition Mode -- Choose between faster processing or more accurate text recognition. Accurate mode uses more CPU resources.
  - captureUniversalClipboard: Save Universal Clipboard Items Immediately -- Items copied on your iPhone, iPad or other Mac are saved to Clipboard History as soon as they arrive, instead of only after you paste them. Large items such as photos can take time to download.
  - disabledApplications: Disabled Applications -- Clipboard changes from these applications will not be recorded.

## cloud-sync
  - syncedDevices: Synced Devices -- View devices connected to Cloud Sync.
  - syncedContent: Synced Content -- See which content categories are synced across devices.
  - deleteData: Delete Cloud Sync Data & Devices -- Delete your synced data and devices from Cloud Sync.
  - enabled: Cloud Sync -- Keep settings and content synchronised across devices.

## contacts
  - sortOrder: Sort By -- Sort contacts by first or last name

## developer
  - autoReloadOnSave: Auto-reload on save -- Restarts the active command after a successful build to reflect saved changes
  - keepWindowVisibleDuringDevelopment: Keep window always visible during development -- Raycast stays visible while any extension is being developed
  - disablePopToRootSearch: Disable pop to root search -- Disabling pop to root search will prevent Raycast from navigating to the root search while developing
  - openRaycastInDevelopmentMode: Open Raycast in development mode -- Automatically open Raycast and pop to the root search after the first initial build
  - useNodeProductionEnvironment: Use Node production environment -- Sets the NODE_ENV variable to "production" while developing

## dictation
  - language: Language
  - useSystemDefault: Use System Default -- Enable to use the microphone set in macOS System Settings. Disable to manually set the priority order for all your microphones.
  - outputAction: Output Action -- Choose what happens with the transcription after accepting.
  - contextAwareInsertion: Context-Aware Paste -- Add a leading space and adjust capitalization to fit the text before the cursor.
  - submitAction: Auto Submit -- Choose whether to press the submit key after the transcription is pasted.
  - submitKeyword: Submit Keyword -- Say this word at the end of a dictation to submit. It is removed from the pasted text.
  - submitKey: Submit Key -- The key pressed to submit.
  - sounds: Sound Effects -- Play audio feedback when starting or stopping dictation.
  - muteWhileRecording: Mute While Recording -- Mute system audio while dictation is active.
  - allowEnterHotkey: Finish and Cancel Shortcuts -- Choose the shortcuts used to finish or cancel dictation.
  - cancelDictationWarning: Show Warning Before Canceling Dictation
  - deleteStyleWarning: Show Warning Before Deleting Styles
  - autoDetectStyle: Auto Styling -- Applies text formatting based on the active app or website. When off, baseline cleanup (filler words, punctuation, grammar) still applies.
  - appContext: App Context -- Use context from your frontmost app to improve transcription accuracy. It stays private and isn't stored.
  - customInstructions: Custom Instructions -- Add global guidance on how to transcribe text across all your transcriptions.
  - migrate: Import from Another App -- Import vocabulary and shortcuts from another dictation app.
  - inputDevice: Microphone -- Choose which microphone Dictation uses.
  - general: General
  - sound: Sound
  - output: Output
  - personalization: Personalization -- Customize how Dictation understands and formats your words.
  - accuracy: Accuracy
  - advanced: Advanced -- Configure experimental features and warnings.
  - experimental: Experimental
  - warnings: Warnings
  - vocabulary: Vocabulary -- Words and names that dictation should always get right.
  - transcriptionStyles: Styles -- Styles control how dictated text is processed by AI.

## emoji-picker
  - columns: Column Count
  - primaryAction: Primary Action
  - emojiSkinTone: Emoji Skin Tone
  - saveAiCustomKeyword: Save AI-generated custom keywords -- When enabled, your search term is stored as a custom keyword on the emoji you copied or pasted, helping future searches find it without AI.

## file-search
  - directories: Search Scopes -- Pick additional folders to be included when searching for files
  - ignorePatterns: Ignore Patterns -- File Search respects .gitignore, .ignore, Git exclude files, and .rayignore by default. Add comma-separated filenames or directories here to ignore them globally in Raycast.
  - autoExcluded: Excluded Automatically -- Folders an app keeps rewriting, like build output and caches. Restore one to index it again.
  - contentSearch: Content Search -- Also search the text inside files, not just their names.
  - includeHiddenFiles: Include Hidden Files
  - useIgnoreFiles: Use ignore files -- Respect .gitignore, .ignore, .rayignore files found while indexing
  - indexNetworkAndRemovableVolumes: Index Network & Removable Drives -- Index files on network shares, removable drives, and virtual filesystems, including ones mounted inside your search scopes.
  - keepRemovedVolumeFiles: Keep Files from Removed Volumes -- Preserve indexed files when their volumes are disconnected. Useful for network drives and external storage.
  - uninstallNtfsScanner: Uninstall NTFS Scanner -- Uninstall the NTFS Scanner service and stop it from running.
  - useNtfsScanner: Use NTFS Scanner -- Use a scanner based on the NTFS Master File Table. May speed up indexing on systems with large HDDs. Requires User Account Control (UAC) permissions.
  - resetToDefaults: Reset to Defaults -- Reset all File Search settings, including search scopes and ignore patterns, to their defaults.

## games
  - gameMode: Game Mode -- Disable Raycast hotkeys while a game window is detected in the foreground.

## internal
PAGE title=Internal path=/internal desc=Development-only toggles and internal debugging settings.
  - paletteEnabled: Enable Palette -- Palette is a macOS input helper that lets Raycast insert text directly into apps. Enabling it installs and activates the helper; disabling it resets setup and removes the helper.
  - paletteCaretPosition: Enable Caret Inspector -- Press ⌃⌥P in a text field to highlight the caret and show its position. Type, click, or press Escape to dismiss.
  - paletteSnippetExpansion: Use Palette for Snippet Expansion -- Insert plain-text snippets with Palette and fall back to Accessibility when unavailable.
  - webContentProcessMode: Web Content Processes -- Use separate processes to release each window's memory independently, or share one process across windows. Requires restarting Raycast.
  - capRenderingTo60Fps: Cap Rendering to 60 FPS -- Target rendering updates at around 60 FPS. Disabled by default in Raycast (WebKit enables it by default). Requires restarting Raycast.
  - aiChatCacheDuration: AI Chat Cache Duration
  - notesCacheDuration: Notes Cache Duration
  - clearMemoryCache: Clear Cache -- Free memory by closing Raycast windows and releasing cached content.
  - palette: Palette
  - memoryPerformance: Memory & Performance -- Choose how Raycast uses memory, renders content, and keeps windows ready for reopening.

## keyboard
PAGE title=Keyboard path=/keyboard desc=Configure keyboard behavior, navigation bindings, input sources, and Hyper Key.
  - escapeKeyBehavior: Escape Key Behavior -- Choose what happens when pressing Escape in the Main window.
  - escapeKeyClosesWindow: Escape Key Closes Window -- Dismiss windows such as AI Chat, Notes, and Settings by pressing the Escape key.
  - autoSwitchInputSource: Auto-switch Input Source -- Automatically switch to the selected keyboard input source when opening Raycast. The previous input source will be restored when closing.
  - navigationBindings: Navigation Bindings -- Key bindings for quick navigation in supported controls.
  - pageNavigationKeys: Page Navigation Keys -- Key equivalent for navigating back and forward in paginated context.
  - builtinHotkeysPreset: Built-in Hotkeys Preset
  - hyperKey: Hyper Key
  - hyperKeyCapsLockAction: Quick Press
  - hyperKeyIncludeShift: Include Shift (⇧)
  - hyperKeySecureInput: Secure Input Compatibility -- Keep the Hyper Key working in password fields and other Secure Input contexts. Only Raycast Hyper Key shortcuts work there (not other apps' Hyper shortcuts). While on, Right Control (⌃⏵) shortcuts are reserved for the Hyper Key.
  - hyperKeyDisplayShortcut: Replace Hyper Key Modifiers with ✦
  - keyboard: Keyboard

## launcher
PAGE title=Launcher path=/launcher desc=Configure content shown in root search.
  - showRaycastOn: Show Raycast on
  - popToRootSearch: Pop to Root Search -- Timeout after which Raycast will reset to root search after closing the window.
  - rootSearchSensitivity: Root Search Sensitivity -- Search sensitivity controls the number of matching results presented in Root Search. Low sensitivity produces many results for a search term, while high sensitivity displays fewer results.
  - includeFilesInRootSearch: Include Files in Root Search
  - searchFileContentsInRootSearch: Include File Content search results in Root Search
  - includeContactsInRootSearch: Include Contacts in Root Search
  - resetSearchHistory: Search History -- Clear recent searches restored when pressing the up arrow in Root Search.
  - behavior: Behavior
  - customizeSearch: Customize Search
  - fallbackCommands: Fallback Commands

## notes
  - showMenuBarToggle: Show Notes Toggle Button in Menu Bar -- Display a button in the menu bar to quickly toggle the Notes window.
  - escapeKeyBehavior: Escape Key Loses Focus -- When enabled, pressing Escape in Notes makes the window lose focus instead of using Keyboard > Escape Key Closes Window.
  - zoom: Zoom -- Adjust the zoom level in the Notes content.

## organizations
PAGE title=Organizations path=/organizations desc=Manage organizations, members, and organization settings.

## quicklinks
  - showLinkPreviews: Show Link Previews
  - preferExistingTabs: Prefer Existing Tabs -- When opening a Quicklink, check if the URL is already open and activate that tab instead of opening a new one.
  - passSelectedTextAsArgument: Pass Selected Text as Argument -- When enabled, Raycast will automatically pass selected text from the active application to Quicklinks with a single argument when invoked via hotkey.
  - deleteQuicklinkWarning: Show Warning Before Deleting Quicklinks

## raycast-account
  - manageAccount: Manage Account
  - signIn: Sign In
  - signOut: Sign Out
  - subscriptions: Subscription
  - credits: Credits
  - upgrade: Upgrade
  - account: Account

## raycast-core
  - showWhatsNew: Show "What's New" after an update
  - exportSettings: Export Settings

## raycast-focus
  - snoozeDuration: Snooze Duration -- Choose how long blocked apps and websites stay snoozed.
  - playSound: Play Sound -- Play sounds for Focus notifications.
  - allowAllWebsitesInAllowMode: Allow all Websites -- Allow all websites when a browser is allowed but no specific websites are listed.
  - restoreAppsWhenSessionEnds: Restore Terminated Apps -- Reopen apps Raycast Focus terminated when the session ends.

## remote
  - enabled: Available to iPhone -- Allow AI Chat on your iPhone to run through Raycast on this computer.
  - deviceName: Computer Name -- The name shown when choosing this computer on iPhone.
  - keepAvailable: Keep This Computer Available -- Prevent idle system sleep so this computer remains available for remote chats.
  - pairPhone: Connect iPhone -- Scan a short-lived QR code in Raycast for iPhone to connect it to this computer.
  - diagnostics: Remote Diagnostics -- Copy a privacy-safe connection report for troubleshooting Remote AI Chat.

## screenshots
  - screenshotFolders: Search Scopes -- Screenshots in these folders will be indexed.
  - columns: Column Count
  - includeAllMedia: Include All Media -- When enabled, all images and videos in the screenshot folders will be indexed, not just screenshots.
  - textRecognitionEnabled: Text Recognition -- Text content in screenshots will be automatically extracted and can be searched.
  - recognitionMode: Recognition Mode -- Choose between faster processing or more accurate text recognition. Accurate mode uses more CPU resources.
  - allowCloudFileOcr: Allow Text Recognition for Cloud Files -- When enabled, text recognition will download cloud-only files (e.g., OneDrive, Dropbox) to extract text.
  - storageDuration: Storage Duration -- Setting a short storage duration will automatically remove olders screenshots. Pinned screenshots will not be deleted.

## script-commands
  - scriptFolders: Script Folders -- Scripts in these folders will be discovered and available as commands.

## snippets
  - autoExpansionEnabled: Enable Snippet Expansion
  - expansionMode: Expansion Mode
  - expandWithinWords: Expand within Words -- If toggled off (default), a Snippet will only get expanded if the keyword is a single word. If toggled on, a Snippet keyword can be part of a wider word.
  - overrideSystemSnippets: Override System Snippets -- When enabled (experimental), Raycast expands Snippets before System Snippets. When disabled (default), matching Snippets won't expand.
  - injectionDelay: Injection Delay -- Injection delays serve two purposes: It lets you write words containing a snippet keyword without expanding that snippet, and it lets you have snippets with similar prefixes. For example, you might have a snippet with keyword '@@' to expand your email and another snippet with keyword '@@p' for the email of your partner.
  - responseTime: Response Time -- Some systems are capable of faster response times processing clipboard entries. This often depends on the software you have installed and running, rather than how new your machine is. Faster response times decrease delays, speeding up snippet expansion. If Raycast doesn't expand your snippets correctly, slower response times might help.
  - completionSound: Completion Sound -- Play a sound when a snippet is expanded automatically.
  - disabledApplications: Disabled Applications -- Snippet expansion will not work in these applications.
  - deleteSnippetWarning: Show Warning Before Deleting Snippets
  - snippetExpansion: Snippet Expansion

## translator
  - primaryAction: Primary Action -- The default action for the Translator command.
  - prefillFromSelectedText: Use Selected Text as Source -- When enabled, selected text from the foremost app will be filled as the source text.
  - defaultSourceLanguage: Default Source Language -- Default language to translate from
  - defaultTargetLanguage: Default Target Language -- Default language to translate to

## window-management
  - innerGap: Window Gap -- Gap between windows
  - outerGap: Screen Gap -- Gap from windows to the screen edge
  - cycling: Cycling -- Cycle sizes when using half commands
  - autoCloseEmptyDesktops: Auto Close Empty Desktops -- Automatically remove empty desktops after switching away
  - respectStageManager: Respect Stage Manager -- Keep windows clear of the Stage Manager strip on the side of the screen
  - presets: Presets -- Apply hotkeys from other window management apps
  - systemSpacesShortcuts: System Spaces Shortcuts -- Disable and import system keyboard shortcuts for switching spaces

## windows-run
  - runCommands: Run Commands
  - shell: Shell -- Shell used by Run in Shell actions.
```

## Appendix C — Dropdown option values observed in settings views

```
windowPresentationMode: mouse-screen "Screen containing mouse" | active-screen "Screen with active window" | primary-screen "Primary screen"
windowActivationBehavior: move-to-active-space | switch-space
faviconProvider: none | duckduckgo | google
escapeKeyBehavior: pop-back-or-close | close-and-pop-to-root
navigationBindings: emacs | vim-motions
pageNavigationKeys: square-brackets | arrow-keys
rootSearchSensitivity: low | medium | high
popToRootTimeout: 0,5,15,30,60,90,120,180 (seconds)
uiZoom: 1 Default | 1+d Large | 1+2d Larger
hyperKey: none, caps_lock, left/right control|shift|option|command, f1..f12; quick press: trigger_key | trigger_escape
builtinHotkeysPreset: improved (default) | classic "Classic User"
clipboard historyDuration: P1D | P1W | P1M | 3 months | ...
snippets expansionMode: Immediately | (delayed modes); injectionDelay/responseTime: None, Short, Long, ExtraLong, Default, Quick, Instant, Regular, Delayed, Extended
snippet completionSound: Basso Blow Bottle Frog Funk Glass Hero Morse Ping Pop Purr Sosumi Submarine Tink
emoji/translator primaryAction: paste "Paste to Active App" | copy "Copy to Clipboard"/"Copy Translation" | open-in-raycast | replace-selection
translator language: auto "Detect Language" + languages
window-management cycleMode: sizes "Cycle 1/2, 2/3, and 1/3" | displays "Cycle Displays"
window-management custom command sizes: Tiny, Small, Medium, Large, Extra Large
auto-quit intervals (min): 1, 3, 5, 10, 15
```
