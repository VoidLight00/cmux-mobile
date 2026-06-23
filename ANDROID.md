# Cmux Mobile — iOS + Android (no native Android app needed)

This is a vendored fork of [lim-won/cmux-iphone](https://github.com/lim-won/cmux-iphone)
(MIT, upstream `5d5c51b`) with one addition: the bridge's built-in **web client is
now an installable PWA**, so you control your Claude Code / Codex / cmux sessions
from **any** phone — Android included — not just the native iOS app.

## Why no Kotlin/Flutter app

The bridge already serves a full mobile client at `GET /` (pairing, live SSE
terminal mirror, permission approvals, prompt send). It uses only `fetch`,
`EventSource` (SSE), and `localStorage` — all of which work identically in
**Android Chrome** and iOS Safari. So "make Android work too" = serve that page
to Android. Done. The native SwiftUI app stays the iOS-premium path; the web
client is the universal one.

What this fork adds (≈5 small files, no dependencies):
`manifest.webmanifest`, `sw.js` (shell-only service worker), `icons/`, plus a
`<link rel=manifest>` / SW registration in `webclient.html` and 5 public routes
in `server.js`.

## Run the bridge (Mac)

```bash
cd skill/bridge
npm ci
node bin/cmux-iphone.js setup        # installs hooks (backs up ~/.claude/settings.json) + picks runner
node bin/cmux-iphone.js pair          # shows the 6-digit pairing code
```

## Use it on Android (or iOS)

1. Expose the bridge to your phone (loopback-only by default):
   ```bash
   node bin/cmux-iphone.js setup --bind 100.x.y.z   # your Mac's Tailscale IP (encrypted, recommended)
   ```
2. On the phone, open `http://100.x.y.z:7860/` in **Chrome (Android)** or Safari (iOS).
3. Enter the pairing code → you're in. Live sessions, approvals, prompts all work.

### Install as an app (home-screen icon, standalone window)

- **Android Chrome:** ⋮ menu → **Install app** / **Add to Home screen**.
- **iOS Safari:** Share → **Add to Home Screen**.

The "Install app" prompt and the service worker require a **secure context**
(HTTPS or localhost). A plain `http://100.x.y.z` Tailscale IP works as a normal
tab but won't offer install. To get HTTPS (and a real installable PWA) over your
tailnet, front the bridge with Tailscale Serve:

```bash
tailscale serve --bg --https=443 http://127.0.0.1:7860
# then open https://<your-mac>.<tailnet>.ts.net/ on the phone
```

`.ts.net` hosts are already allowed by the bridge's Host check.

> Security unchanged from upstream: loopback by default, pairing code + per-device
> token, DNS-rebinding Host check. Run it over Tailscale or a trusted LAN — never
> the open internet. See `SECURITY.md`.
