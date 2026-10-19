# CLAUDE.md

This repo is a clean-room rebuild of **Raycast for Linux**. The first target is **Omarchy**: Arch Linux + Hyprland, plus Omarchy's own scripts, themes and bindings. The behaviour and interfaces come from a static reverse-engineering pass over Raycast 2.8.2 on macOS, done with the `reverse-engineer-anything` skill. This repo holds that pass's results and no Raycast code.

## Read these first

| File | What it is | When to read it |
|---|---|---|
| `SPEC.md` | **The plan.** Architecture, IPC contract, platform matrix, data layer, root-search algorithm, feature catalog, extension runtime, frontend, `.rayconfig` import, phased build plan with acceptance checks. | Before any work. Re-read the relevant section before each phase. |
| `reference/01-host-ipc.md` | Native host: window model, ~408 host capabilities (§4.1), WebView bridge, host↔backend wire protocol, helper processes, a Linux mapping for each (§4.3). | Phase 0 (IPC, supervisor), Phase 1 (window), Phase 6 (WM) |
| `reference/02-backend.md` | Backend service map and RPC methods, DB engine, **root-search ranking (§4)**, frecency (§4.6), clipboard (§5.1), snippet placeholder grammar (§5.2), quicklinks (§6), calculator, indexer. | Phases 1–4, 7 |
| `reference/03-extensions.md` | `@raycast/api` runtime: worker model, reconciler, **render-tree JSON schema (§2.4)**, API→RPC table (§3.2), manifest (§4), Script Commands (§5), install pipeline (§6), Icon enum (App. A). | Phase 2 (script commands), Phase 5 |
| `reference/04-frontend-features.md` | **Built-in command catalog (§1, App. A)**, launcher UI anatomy (§2), default shortcuts (§2.8), settings pages (§3, App. B/C), themes and design tokens (§4). | Phase 1 onward, every UI task |
| `reference/05-data-config.md` | On-disk layout, DB encryption, reconstructed schema, `.rayconfig` format (§5), XDG mapping (§8). | Phase 0 (paths, DB), Phase 8 (import) |
| `reference/schema-nonai.sql` | Raycast's non-AI DDL, reconstructed. **Reference only.** The clone uses the simpler schema in `SPEC.md §6.4`. | When you need a field Raycast stores |
| `reference/backend-methods-nonai.txt` | Every non-AI backend RPC method name. **Do not implement all of them.** Reuse the names for what each phase needs. | When naming an IPC method |

Spec legend: **[O]** observed in Raycast, **[I]** inferred, **[D]** design decision for this clone. [O] is ground truth for behaviour. [D] may be changed if you have a reason; note the change in `SPEC.md`.

## Ground rules (from SPEC.md §0, non-negotiable)

1. **Clean room.** Never copy, bundle or redistribute anything from `Raycast.app` (JS, icons, fonts, `.node` modules). Allowed: the public npm `@raycast/api` / `@raycast/utils` packages (check the license of the pinned version) and the MIT `raycast/extensions` repo.
2. **Never call `*.raycast.com`.** No store, account, sync, telemetry or currency APIs. Build extensions from a local `raycast/extensions` clone.
3. **No telemetry.** No Sentry, no PostHog.
4. **No AI features.** Where a built-in mixes AI and non-AI behaviour, build the non-AI path and leave a `// AI: not implemented` comment.
5. **Port the root-search ranker exactly** from `reference/02-backend.md §4.2–4.5`. Do not substitute fzf, nucleo or fuse.js.

## How to work

- Build **phase by phase** following `SPEC.md §12` (Phase 0 → 9). A phase is done only when its **Accept** checks pass. Then move on.
- After each phase, update the **Status** section at the bottom of this file: what works, what's stubbed, and any deviations from the spec.
- If the reference docs don't answer a question, choose a sensible value, mark it `[I]` or `[D]` in a code comment, and keep going. Raycast.app is not on the Omarchy machine. Re-running the reverse-engineering only works on the Mac where `/Applications/Raycast.app` lives.
- The working name is **`raylinux`**: binary `raylinux`, app id `dev.typecraft.Raylinux`, URL scheme `raylinux://`. Also register `raycast://` for extension deep links (SPEC §5.5).

## Repo layout (create it in Phase 0)

The spec stays where it is (`SPEC.md` and `reference/` at the repo root, not `docs/spec/`). The code goes alongside:

```
SPEC.md, reference/   # the spec (this repo's existing files)
src-tauri/            # Rust host: main.rs, router.rs, supervisor.rs, platform/{hyprland,kwin,gnome,x11,wlroots}.rs,
                      #   clipboard.rs, input/{uinput,evdev}.rs, hotkeys.rs, tray.rs, schemes.rs, indexer/, calc.rs
backend/              # Node ≥22 TS: server.ts (NDJSON), services/*, db/{migrations,*.ts}, extensions/{host,worker-pool,store}.ts
packages/api/         # our @raycast/api-compatible runtime (reconciler, serializer, API functions)
packages/catalog/     # declarative built-in command catalog, shared by frontend and backend
frontend/             # React 19 + Vite: windows/{main,settings,notes,theme-studio,hud}, components/, renderer/
packaging/            # PKGBUILD, raylinux.desktop, systemd user unit, 60-raylinux-uinput.rules, hypr/raylinux.conf
gnome-extension/      # later; Omarchy doesn't need it
```

Stack: Tauri 2 (Rust) host, WebKitGTK webviews, Node backend bundled with esbuild, `better-sqlite3-multiple-ciphers`, pnpm workspaces. Rationale is in SPEC §2.

## Commands

Phase 0 sets these up. Keep this list accurate as the scripts change.

```sh
pnpm install                 # all JS workspaces
pnpm tauri dev               # run the app in dev (hot reload frontend, rebuilds host)
pnpm tauri build             # release build
pnpm -r test                 # backend + packages + frontend unit tests (vitest)
cargo test --manifest-path src-tauri/Cargo.toml
pnpm lint && cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings

raylinux toggle              # show/hide the launcher (talks to the running instance over D-Bus)
raylinux run <commandId>     # open a command directly
raylinux doctor              # check uinput/input group, portals, data-control, Hyprland socket
raylinux setup hyprland      # write ~/.config/hypr/raylinux.conf and source it
```

## Running on Omarchy

Omarchy is the primary runtime target: Hyprland only. KDE, GNOME and X11 adapters come later (SPEC §4). Check each of these on the machine instead of assuming it; Omarchy changes often.

**Dependencies**
- Install with `yay -S --needed webkit2gtk-4.1 gtk3 libsecret wl-clipboard libayatana-appindicator rust nodejs pnpm tesseract tesseract-data-eng`.
- Omarchy may manage Node through `mise`. Use whatever `node --version` reports, as long as it is ≥22.

**Build location**
- Build on the Omarchy machine itself. Tauri doesn't cross-compile from macOS to Linux.
- Gate Linux-only host code behind `#[cfg(target_os = "linux")]` so `cargo check` still runs on the Mac.

**Hyprland config**
- Run `hyprctl version` and use the window/layer rule syntax for that version, since rule syntax has changed between releases.
- Omarchy splits its config into files sourced from `~/.config/hypr/hyprland.conf` (user binds live in `~/.config/hypr/bindings.conf`).
- `raylinux setup hyprland` writes its own `~/.config/hypr/raylinux.conf` and adds one `source =` line. It must never rewrite Omarchy's files in place.
- The launcher window gets class `raylinux` with rules for float, pin, center, no border/shadow, stayfocused and blur (SPEC §4 table).

**Hotkey**
- Omarchy's own launcher, Walker, is bound to **Super+Space**. Default to **Alt+Space** (SPEC §5.2) and grep the Hypr config for conflicts before binding.
- Bind it as `bind = ALT, SPACE, exec, raylinux toggle`.
- Offer, but never force, swapping Super+Space over to raylinux.

**App launching**
- Omarchy launches apps through `uwsm app -- <cmd>`. Use that when `uwsm` is present, and fall back to `systemd-run --user --scope` (SPEC §8.1 Applications).

**Theme**
- The active Omarchy theme is under `~/.config/omarchy/current/theme/`. Add an "Omarchy" theme [D] that maps those colours onto the 15-field theme JSON (SPEC §10.4).
- Watch the directory/symlink so `omarchy-theme-set` restyles the launcher live.
- Inspect the files that exist there before writing the parser.

**Terminals and paste**
- Omarchy ships Alacritty/Ghostty/Kitty-class terminals, which need Ctrl+Shift+V for paste (SPEC §5.3). Read the actual WM class from `hyprctl activewindow -j`.

**Desktop services**
- Notifications go through mako (`org.freedesktop.Notifications`). The tray is waybar's SNI module.
- Clipboard uses `wlr-data-control` / `ext-data-control-v1`, which Hyprland supports.

**Autostart**
- Prefer `exec-once = uwsm app -- raylinux --background` in `raylinux.conf`, or a systemd user unit from `packaging/`.

**Snippet expansion**
- Expansion needs the `input` group or the uinput udev rule. Keep it opt-in, and have `raylinux doctor` explain how to enable it.

**Install**
- Phase 9 produces a `PKGBUILD` with `makepkg -si`. Until then, use `pnpm tauri build` and copy the binary to `~/.local/bin/`.

## Status

Nothing is built yet. The repo contains only the spec. Start with **SPEC.md §12 Phase 0**.
