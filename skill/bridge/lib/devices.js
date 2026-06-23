// lib/devices.js — per-device bearer tokens with revoke.
//
// Replaces the old single global session token. Each paired phone/watch gets
// its OWN token, so pairing a new device no longer invalidates the others, and
// any device can be revoked individually. Persisted to devices.json (0600).
// A legacy single-token file is migrated into one device on first load.

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

export function createDeviceStore(filePath, legacyTokenFile = null) {
  let devices = []; // [{ id, name, token, pairedAt, lastSeen }]
  const byToken = new Map();

  function reindex() {
    byToken.clear();
    for (const d of devices) byToken.set(d.token, d);
  }

  function persist() {
    try {
      fs.mkdirSync(path.dirname(filePath), { recursive: true });
      fs.writeFileSync(filePath, JSON.stringify(devices, null, 2), { mode: 0o600 });
    } catch { /* best effort */ }
  }

  function load() {
    try {
      const j = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      devices = Array.isArray(j) ? j : [];
    } catch {
      devices = [];
    }
    // Migrate a legacy single session token so an existing pairing survives.
    if (devices.length === 0 && legacyTokenFile) {
      try {
        const t = fs.readFileSync(legacyTokenFile, "utf-8").trim();
        if (t) {
          devices = [{ id: "legacy", name: "Paired device (migrated)", token: t, pairedAt: Date.now(), lastSeen: null }];
          persist();
        }
      } catch { /* nothing to migrate */ }
    }
    reindex();
  }

  /** Issue a token for a (re-)pairing device. Re-pairing the same id replaces it. */
  function add({ name, id } = {}) {
    const device = {
      id: id || crypto.randomUUID(),
      name: name || "iPhone",
      token: crypto.randomBytes(32).toString("hex"),
      pairedAt: Date.now(),
      lastSeen: Date.now(),
    };
    devices = devices.filter((d) => d.id !== device.id);
    devices.push(device);
    persist();
    reindex();
    return device;
  }

  function isValid(token) {
    return typeof token === "string" && token.length > 0 && byToken.has(token);
  }

  function touch(token) {
    const d = byToken.get(token);
    if (d) d.lastSeen = Date.now(); // not persisted on every request (cheap, in-memory)
  }

  /** Revoke by device id. Returns true if a device was removed. */
  function revoke(id) {
    const before = devices.length;
    devices = devices.filter((d) => d.id !== id);
    if (devices.length === before) return false;
    persist();
    reindex();
    return true;
  }

  function revokeAll() {
    const had = devices.length > 0;
    devices = [];
    persist();
    reindex();
    return had;
  }

  /** Public list WITHOUT token values (safe to show / send over the wire). */
  function list() {
    return devices.map(({ token, ...rest }) => rest);
  }

  function count() {
    return devices.length;
  }

  load();
  return { add, isValid, touch, revoke, revokeAll, list, count, reload: load };
}
