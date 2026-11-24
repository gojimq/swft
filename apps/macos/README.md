# Swft — native macOS client

Swft is an unofficial hard fork of the T3 Code source (MIT). It is not affiliated with T3 Tools, Inc.
No T3 names, logos or icons may appear in the app (see /TRADEMARK.md).

- **Backend:** the Node server in `apps/server` (forked from T3 Code `main`, hard fork — no upstream syncing).
  The macOS app launches it as a bundled child process and talks to it over its existing WebSocket protocol.
- **Frontend:** this SwiftPM package. SwiftUI first, AppKit where SwiftUI falls short. macOS 15+.
  The Electron/web/mobile apps in `apps/` are reference only; Swft does not ship them.

## Layout

| Path                 | Owner                                                                         | Contents                                                                                             |
| -------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `Sources/SwftKit`    | engineering track                                                             | WebSocket/RPC client, Codable models mirroring `packages/contracts`, server process launcher, stores |
| `Sources/SwftDesign` | design track                                                                  | tokens (color, type, spacing, radius, motion), bundled Google Sans Flex font, reusable components    |
| `Sources/Swft`       | design track builds screens with mock data; engineering track wires real data | app, windows, screens, view models                                                                   |

## Build / run

    swift build            # from apps/macos
    swift test
    scripts/bundle.sh      # produces build/Swft.app ; open build/Swft.app

Run Swft from `build/Swft.app`. SwiftPM stamps the binary with the deployment target as its SDK version, which makes
macOS 26+ run it in compatibility mode (small traffic lights, no Liquid Glass); `bundle.sh` re-stamps the real SDK.

## Visual direction

Layout and feel follow the Gemini macOS desktop app (`docs/ref-gemini-home.png`): light, airy, soft blue radial glow,
rounded pill composer, left sidebar with primary nav. Typeface: Google Sans Flex (OFL, bundled).
Do not use Google logos, the Gemini name or Gemini's spark icon — Swft has its own mark.

The sidebar thread list is NOT plain titles: it follows the thread-inbox layout in `docs/ref-t3-thread-inbox.png`
(project chip + name, relative time, bold thread title, branch/host subtitle, provider glyph, status icons, highlighted
active/unread rows) restyled in the Gemini visual language.

## Font

`Sources/SwftDesign/Resources/Fonts/GoogleSansFlex.ttf` is the variable Google Sans Flex from google/fonts
(`ofl/googlesansflex`), licensed under the SIL Open Font License 1.1 (`OFL.txt` alongside it). It is registered
per-process at launch (`SwftFonts.register()`); every type token falls back to the system font if that fails.

## UI state and screenshots

Screens render plain value types from `Sources/Swft/ViewState`, adapted from `SwftKit` stores via
`Sources/Swft/Adapters/SwftKitAdapters.swift`. By default the app boots the local Node server under
`~/Library/Application Support/Swft`, authenticates, and connects over WebSocket.

Mock data (`Sources/Swft/Preview/MockData.swift`) is used only for SwiftUI previews and screenshot flags:

- `-SwftMock` (or `-SwftMock YES`): force mock mode without starting a server (`-SwftMock NO` forces live mode).
- `-SwftScreen thread`: open the sample mock thread.
- `-SwftAppearance light|dark`: pin the appearance for screenshot runs.
- `-SwftWindowSize 1924x1052`: pin the window size (for side-by-side comparisons with the reference).

Current mock captures live in `docs/screens/`.

## Running the local server (dev vs packaged `.app`)

During development, `ServerProcess` launches `apps/server` with a system `node` binary (v22.16+ or v24+).
Resolution order:

- **Node binary:** `SWFT_NODE_PATH` → `PATH` → common macOS paths (`~/.local/bin/node`, `/opt/homebrew/bin/node`,
  `/usr/local/bin/node`, `~/.local/node/*/bin/node`, `~/.nvm/versions/node/*/bin/node`).
- **Server entrypoint:** `SWFT_SERVER_ENTRY` → `SWFT_REPO_ROOT` (`apps/server/dist/bin.mjs` or `apps/server/src/bin.ts`)
  → bundled `Contents/Resources/server/bin.mjs` → ancestor walk from working directory, `.app` bundle, and the
  compile-time checkout path.
- **Data directory:** `SWFT_HOME` if set, otherwise `~/Library/Application Support/Swft` (`~/.t3` is rejected).

### Future packaged `.app` distribution (not yet built)

Shipping a standalone `Swft.app` without requiring a checkout or system Node install will require bundling the
runtime inside `Swft.app/Contents/Resources/`:

1. **Bundled Node runtime:** copy a signed, universal or per-arch `node` binary (matching `apps/server`'s engine
   requirement, Node 24+) into `Contents/Resources/node/bin/node` (or bundle a Node SEA executable) and point
   `ServerProcess` at it before falling back to system `PATH`.
2. **Built server bundle:** run `vp run --filter t3 build:bundle` (`apps/server/dist/bin.mjs`) and stage
   `dist/bin.mjs` plus required runtime assets and native addons (`node-pty` prebuilds, `@napi-rs/keyring`,
   `playwright-core` if used, etc.) into `Contents/Resources/server/`. `ServerProcess` already probes
   `Bundle.main.resourceURL/server/bin.mjs`.
3. **Codesigning & notarization:** sign the bundled `node` binary and every `.node` native addon inside
   `Contents/Resources/server/` with Hardened Runtime entitlements (`com.apple.security.cs.allow-jit`,
   `allow-unsigned-executable-memory` as needed by V8) before signing and notarizing `Swft.app`.

## Safety

Never start a dev server against `~/.t3/userdata` (the user's live install). Swft defaults to
`~/Library/Application Support/Swft` and refuses any path under `~/.t3`.
Never kill processes by name pattern — `ServerProcess` terminates only the exact PID it spawned.
