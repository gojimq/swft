# Swft — native macOS client

Swft is an unofficial hard fork of the T3 Code source (MIT). It is not affiliated with T3 Tools, Inc.
No T3 names, logos or icons may appear in the app (see /TRADEMARK.md).

- **Backend:** the Node server in `apps/server` (forked from T3 Code `main`, hard fork — no upstream syncing).
  The macOS app launches it as a bundled child process and talks to it over its existing WebSocket protocol.
- **Frontend:** this SwiftPM package. SwiftUI first, AppKit where SwiftUI falls short. macOS 15+.
  The Electron/web/mobile apps in `apps/` are reference only; Swft does not ship them.

## Layout

| Path | Owner | Contents |
|---|---|---|
| `Sources/SwftKit` | engineering track | WebSocket/RPC client, Codable models mirroring `packages/contracts`, server process launcher, stores |
| `Sources/SwftDesign` | design track | tokens (color, type, spacing, radius, motion), bundled Google Sans Flex font, reusable components |
| `Sources/Swft` | design track builds screens with mock data; engineering track wires real data | app, windows, screens, view models |

## Build / run

    swift build            # from apps/macos
    swift test
    scripts/bundle.sh      # produces build/Swft.app ; open build/Swft.app

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

Screens render plain value types from `Sources/Swft/ViewState`, seeded today by `Sources/Swft/Preview/MockData.swift`
through `AppModel`. Wiring real data means filling those types from SwftKit, not changing the views.

Launch flags (handy for screenshots): `-SwftScreen thread` opens the sample thread, `-SwftAppearance light|dark`
pins the appearance. Current captures live in `docs/screens/`.

## Safety

Never start a dev server against `~/.t3/userdata` (the user's live install). Use a temp `T3CODE_HOME`/base dir.
Never kill processes by name pattern.
