# Security

## Trust model

Cmux iPhone is a **personal, local-network tool**, not an internet-facing service.

- The **bridge** listens on `127.0.0.1:<apiPort>` (default 7860) by default —
  **loopback-only**, so a fresh install is never reachable over plaintext HTTP by
  the rest of the network. Reaching it from the phone/watch is an explicit opt-in
  (`cmux-iphone setup --bind <tailscale-ip>` / `--lan`, the `bindAddress` config, or
  the `HOST` env). Anyone who can reach the exposed port can attempt to pair.
- **DNS-rebinding defense:** requests whose `Host` header is a foreign domain (not
  an IP literal, `localhost`, `*.local`, or `*.ts.net`) are rejected `403`, so a
  malicious web page can't drive the bridge through the victim's browser.
- **Auth boundary:** a **6-digit pairing code** establishes a **per-device bearer
  token**. By default `cmux-iphone setup` generates a **fixed, random per-machine
  code once**, stores it `0600`, and does **not** rotate it (always retrievable via
  `cmux-iphone pair`). The bridge **rate-limits pairing to 5 attempts per 5-minute
  window, per client IP** (so one abusive client can't lock everyone else out), and
  a fixed code resists online brute force. A **rotating** mode (a fresh
  6-digit code with a 24h TTL, regenerated on restart and cleared after a device
  pairs) is **opt-in** — used only when no fixed code is set (`cmux-iphone setup
  --rotating`, or unset `pairing.fixedCode`). Every authenticated request
  (`/command`, `/events`, `/status`, `/devices`, cmux routes) requires a valid
  device token, and each paired device gets its **own revocable token**
  (`cmux-iphone pair --revoke <id>`).
- The **hook listener** (default 7861) is bound to **loopback only** and gated by
  a shared secret header, so Claude Code's hook traffic never crosses the network.
- `GET /health` is public (liveness only — no session data). `GET /status` and
  everything else require a token.
- **iOS/watchOS bearer tokens** are stored in the **Keychain** (this-device-only),
  not in `UserDefaults`.
- **LAN traffic is unencrypted** — once exposed beyond loopback, the phone-facing
  API is **plaintext HTTP**. Prefer **Tailscale** (encrypted) over a plaintext LAN
  bind (`--lan` / `0.0.0.0`), and never port-forward to the public internet. The
  `bindAddress` config (or `HOST` env) pins the listener to a chosen interface.

### Recommendations

- **Prefer Tailscale** (or a trusted home LAN) over exposing the LAN port. Do
  **not** port-forward the bridge to the public internet.
- Revoke a lost device's token with `cmux-iphone pair --revoke <id>`.
- `cmux-iphone uninstall --purge` removes the service, hooks, and all local data.

## Secrets

Generated at runtime, stored **outside the repo** with `0600` permissions:

- `~/Library/Application Support/cmux-iphone/devices.json` — per-device tokens
- `~/Library/Application Support/cmux-iphone/hook-secret` — hook listener secret
- `~/.config/cmux-iphone/cmux-password` — cmux control-socket password (if used)

The hook secret is also embedded in `~/.claude/settings.json` (in the hook
headers); `cmux-iphone setup` backs that file up and `chmod 600`s it. None of
these are tracked by git (`.gitignore` guards them as defense-in-depth). **Never
commit a real token, secret, password, or pairing code.**

## Reporting a vulnerability

Please open a private report via GitHub Security Advisories on this repository,
or email the maintainer listed in the repo profile. Do not file a public issue
for anything that could expose a user's machine. We aim to acknowledge within a
few days.

This is a community project provided as-is (MIT, no warranty); there is no formal
SLA, but security reports are taken seriously.
