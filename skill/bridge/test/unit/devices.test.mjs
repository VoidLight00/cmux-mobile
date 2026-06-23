// Unit tests for the per-device token store (pair / validate / revoke / migrate).
// Deterministic, hermetic — writes to a temp file, no bridge/network.

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { createDeviceStore } from "../../lib/devices.js";

function tmp() { return path.join(mkdtempSync(path.join(os.tmpdir(), "aw-dev-")), "devices.json"); }

test("pairing a new device issues a token without invalidating others", () => {
  const f = tmp();
  try {
    const store = createDeviceStore(f);
    const a = store.add({ name: "iPhone A" });
    const b = store.add({ name: "iPhone B" });
    assert.notEqual(a.token, b.token);
    assert.ok(store.isValid(a.token), "A still valid after B paired");
    assert.ok(store.isValid(b.token));
    assert.equal(store.count(), 2);
  } finally { rmSync(path.dirname(f), { recursive: true, force: true }); }
});

test("revoke removes only that device's token", () => {
  const f = tmp();
  try {
    const store = createDeviceStore(f);
    const a = store.add({ name: "A" });
    const b = store.add({ name: "B" });
    assert.equal(store.revoke(a.id), true);
    assert.ok(!store.isValid(a.token), "revoked token rejected");
    assert.ok(store.isValid(b.token), "other device unaffected");
    assert.equal(store.revoke("nonexistent"), false);
  } finally { rmSync(path.dirname(f), { recursive: true, force: true }); }
});

test("list() never exposes token values", () => {
  const f = tmp();
  try {
    const store = createDeviceStore(f);
    store.add({ name: "A" });
    const listed = store.list();
    assert.equal(listed.length, 1);
    assert.equal(listed[0].token, undefined, "token must not be in the public list");
    assert.ok(listed[0].id && listed[0].name);
  } finally { rmSync(path.dirname(f), { recursive: true, force: true }); }
});

test("tokens persist across reload (survive a restart)", () => {
  const f = tmp();
  try {
    const s1 = createDeviceStore(f);
    const a = s1.add({ name: "A" });
    const s2 = createDeviceStore(f);   // fresh store, same file
    assert.ok(s2.isValid(a.token), "token restored from disk");
  } finally { rmSync(path.dirname(f), { recursive: true, force: true }); }
});

test("legacy single session-token file is migrated into one device", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "aw-dev-"));
  const devicesFile = path.join(dir, "devices.json");
  const legacyFile = path.join(dir, "session-token");
  try {
    writeFileSync(legacyFile, "legacytoken123\n");
    const store = createDeviceStore(devicesFile, legacyFile);
    assert.ok(store.isValid("legacytoken123"), "legacy token still works (migrated)");
    assert.equal(store.count(), 1);
    // and it was written into devices.json
    const onDisk = JSON.parse(readFileSync(devicesFile, "utf-8"));
    assert.equal(onDisk[0].token, "legacytoken123");
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("re-pairing the same deviceId replaces (not duplicates) it", () => {
  const f = tmp();
  try {
    const store = createDeviceStore(f);
    const first = store.add({ name: "iPhone", id: "dev-1" });
    const second = store.add({ name: "iPhone", id: "dev-1" });
    assert.equal(store.count(), 1, "same id replaces");
    assert.ok(!store.isValid(first.token), "old token invalidated on re-pair");
    assert.ok(store.isValid(second.token));
  } finally { rmSync(path.dirname(f), { recursive: true, force: true }); }
});
