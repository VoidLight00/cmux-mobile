<h1 align="center">Cmux Mobile</h1>

<p align="center">
  Watch and control your <strong>Claude Code</strong>, <strong>Codex</strong>, and
  <strong>cmux</strong> sessions from <strong>any phone — iOS <em>and</em> Android</strong>.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License: MIT"/>
  <img src="https://img.shields.io/badge/platforms-iOS%20%7C%20Android%20%7C%20any%20browser-blue.svg" alt="Platforms"/>
  <img src="https://img.shields.io/badge/install-PWA-purple.svg" alt="PWA"/>
</p>

---

## What this is

A fork of **[lim-won/cmux-iphone](https://github.com/lim-won/cmux-iphone)** (MIT) that makes the
mobile client **cross-platform**. The upstream project ships a native SwiftUI app for iPhone +
Apple Watch; this fork turns the bridge's built-in web client into an **installable PWA** so the
same live session mirror, prompt input, and permission approvals work on **Android Chrome** too —
no Kotlin/Flutter app required.

> **Why no native Android app?** The bridge already serves a complete mobile client at `GET /`
> (pairing, live SSE terminal mirror, approvals, prompt send) using only `fetch`, `EventSource`,
> and `localStorage` — all of which work identically in Android Chrome and iOS Safari. So
> "support Android" means *serve that page to Android* and make it installable. The native iOS app
> stays the iOS-premium path; the web client is the universal one.

**→ See [`ANDROID.md`](ANDROID.md) for the cross-platform setup (iOS + Android + tethering).**

## How it works

```
   phone (any browser / iOS app)  ──HTTP POST──►  cmux-iphone bridge (Node, on your Mac)
                                  ◄──SSE stream──   serves the web client at GET /
                                                    ├─ Claude Code  → hooks
                                                    ├─ cmux         → control-socket RPC (live mirror)
                                                    └─ Codex        → log + pinned terminal
```

Everything runs **on your own machines** — no cloud, no account. The bridge is loopback-only by
default; expose it over a trusted LAN or a Tailscale tailnet. Auth is a pairing code + per-device
token.

## What this fork adds

| File | Change |
|---|---|
| `skill/bridge/manifest.webmanifest` | PWA manifest (name, icons, `display: standalone`) |
| `skill/bridge/sw.js` | shell-only service worker — caches `/`, manifest, icons; **never** caches `/events` (SSE), `/command`, `/status`, `/cmux/*` |
| `skill/bridge/icons/` | 192 / 512 / maskable app icons |
| `skill/bridge/webclient.html` | `<link rel=manifest>`, theme-color, apple-touch-icon, secure-context-guarded SW registration |
| `skill/bridge/server.js` | 5 public static routes (`/manifest.webmanifest`, `/sw.js`, `/icons/*`) |
| `skill/bridge/verify-pwa.sh` | deterministic gate (syntax + units + route 200s + SW bypass) |

The native iOS app, the bridge core, and the CLI are unchanged from upstream.

## Quick start

```bash
cd skill/bridge
npm ci
node bin/cmux-iphone.js setup     # installs Claude Code hooks (backs up settings) + picks a runner
node bin/cmux-iphone.js pair      # shows the pairing code
```

Then on your phone (Android Chrome or iOS Safari) open the bridge URL and enter the code.
Full instructions — same Wi-Fi, Bonjour auto-discovery, phone tethering, Tailscale, and "install as
an app" — are in [`ANDROID.md`](ANDROID.md). For the iOS native app and the bridge internals, see
[`README.upstream.md`](README.upstream.md).

## Verification

The PWA layer ships with a runnable gate:

```bash
bash skill/bridge/verify-pwa.sh   # node --check, 14/14 upstream unit tests, all PWA routes 200, SW bypass asserts
```

## License & attribution

MIT — see [`LICENSE`](LICENSE). This is a fork of
[lim-won/cmux-iphone](https://github.com/lim-won/cmux-iphone) (MIT), itself a fork of
[shobhit99/claude-watch](https://github.com/shobhit99/claude-watch) (MIT). Original-author
copyrights are preserved; see [`NOTICE.md`](NOTICE.md). The app ships neutral icons — "Claude" and
"Codex" are trademarks of Anthropic and OpenAI respectively, used only as text labels. Independent
community tool, not affiliated with or endorsed by Anthropic or OpenAI.
