// lib/bridge-client.js — helpers for the cmux-iphone CLI to talk to the LOCAL
// bridge running on this same Mac.
//
// Resolving WHERE the bridge is: the server writes runtime.json after it binds
// (the actual port + the interface it bound to). The CLI reaches it on that
// interface — loopback when the bridge binds all interfaces (0.0.0.0), or the
// exact bound IP when the user restricted it to e.g. a Tailscale address. A
// successful probe is CACHED so every later api() call hits the same host:port
// (otherwise a range-scan that found 7862 would be ignored by the next call).

import fs from "node:fs";
import { paths, getConfig, getRuntime } from "./config.js";

let _resolved = null; // { host, port } once a live bridge is found

/** Host the local CLI should use for a given bound interface. The CLI runs on
 *  the same machine, so loopback works whenever the bridge binds every interface;
 *  otherwise it must use the exact interface the bridge restricted itself to
 *  (e.g. a Tailscale IP), since 127.0.0.1 won't reach a Tailscale-only listener. */
function hostFor(bindAddress) {
  if (!bindAddress || bindAddress === "0.0.0.0" || bindAddress === "::") return "127.0.0.1";
  return bindAddress;
}

/** Best guess at the bridge target from env/runtime/config (no network probe). */
function defaultTarget() {
  const rt = getRuntime();
  return {
    host: hostFor(rt.bindAddress),
    port: Number(process.env.PORT) || rt.apiPort || getConfig().ports.apiPort,
  };
}

export function apiBase() {
  const t = _resolved || defaultTarget();
  return `http://${t.host}:${t.port}`;
}

/** Back-compat: the resolved (or best-guess) API port. */
export function apiPort() {
  return (_resolved || defaultTarget()).port;
}

/** A valid device token read from the local store (for authed CLI calls), or null. */
export function readAnyToken() {
  try {
    const d = JSON.parse(fs.readFileSync(paths.devicesFile, "utf-8"));
    return Array.isArray(d) && d[0] && d[0].token ? d[0].token : null;
  } catch {
    return null;
  }
}

async function healthAt(host, port) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 1500);
  try {
    const res = await fetch(`http://${host}:${port}/health`, { signal: ctrl.signal });
    const j = await res.json().catch(() => null);
    return res.ok && j && j.ok === true;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

export async function api(method, route, { token, body, timeoutMs = 4000 } = {}) {
  // Resolve the live host:port once (cheap probe of the known target) so this
  // call lands on the interface/port the bridge actually bound.
  if (!_resolved) await bridgeUp();
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${apiBase()}${route}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
      signal: ctrl.signal,
    });
    let json = null;
    try { json = await res.json(); } catch { /* non-JSON */ }
    return { status: res.status, json, ok: res.ok };
  } catch (e) {
    return { status: 0, json: null, ok: false, error: e.message };
  } finally {
    clearTimeout(timer);
  }
}

/** Call the LOOPBACK control listener (the hook port, 127.0.0.1 only, secret-gated)
 *  for local-only operations like reading the pairing code. Goes straight to
 *  127.0.0.1:<hookPort> with the hook secret, so it works regardless of the API's
 *  bindAddress (even Tailscale-only) and can't be reached by a rebinding browser
 *  (which has no secret). Returns {status, json, ok}. */
export async function controlApi(method, route, { timeoutMs = 4000 } = {}) {
  const rt = getRuntime();
  const port = parseInt(process.env.CMUX_IPHONE_HOOK_PORT, 10) || rt.hookPort || getConfig().ports.hookPort || 7861;
  let secret = "";
  try { secret = fs.readFileSync(paths.hookSecretFile, "utf-8").trim(); } catch { /* no secret yet */ }
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`http://127.0.0.1:${port}${route}`, {
      method,
      headers: { "Content-Type": "application/json", "x-cmux-iphone-secret": secret },
      signal: ctrl.signal,
    });
    let json = null;
    try { json = await res.json(); } catch { /* non-JSON */ }
    return { status: res.status, json, ok: res.ok };
  } catch (e) {
    return { status: 0, json: null, ok: false, error: e.message };
  } finally {
    clearTimeout(timer);
  }
}

/** Quick liveness probe of the known target (no range scan). Caches on success. */
export async function bridgeUp() {
  const t = defaultTarget();
  if (await healthAt(t.host, t.port)) { _resolved = t; return true; }
  return false;
}

/** Thorough discovery: known target first, then scan the configured port range
 *  on the bound interface AND loopback. Caches + returns {host,port} or null. */
export async function findBridge() {
  const t = defaultTarget();
  if (await healthAt(t.host, t.port)) { _resolved = t; return t; }
  const { apiPort: start, apiPortRangeEnd: end, hookPort } = getConfig().ports;
  const hosts = [...new Set([t.host, "127.0.0.1"])];
  for (const host of hosts) {
    for (let p = start; p <= end; p++) {
      if (p === hookPort) continue;
      if (await healthAt(host, p)) { _resolved = { host, port: p }; return _resolved; }
    }
  }
  return null;
}

/** Convenience: the live bridge's port (via full discovery), or null. */
export async function findBridgePort() {
  const r = await findBridge();
  return r ? r.port : null;
}
