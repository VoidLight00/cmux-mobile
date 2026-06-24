import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const html = readFileSync(path.resolve(fileURLToPath(import.meta.url), "../../../webclient.html"), "utf-8");
const sw = readFileSync(path.resolve(fileURLToPath(import.meta.url), "../../../sw.js"), "utf-8");

test("web client shows an update button when a new service worker waits", () => {
  assert.match(html, /id="updateBtn"/);
  assert.match(html, /새 버전 업데이트/);
  assert.match(html, /function showUpdate\(\)/);
  assert.match(html, /registration\.waiting/);
  assert.match(html, /SKIP_WAITING/);
  assert.match(html, /controllerchange/);
  assert.match(sw, /SKIP_WAITING/);
  assert.match(sw, /skipWaiting\(\)/);
});
