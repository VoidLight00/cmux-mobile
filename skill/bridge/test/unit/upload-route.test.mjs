import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const server = readFileSync(path.resolve(fileURLToPath(import.meta.url), "../../../server.js"), "utf-8");

test("server exposes an authenticated image upload route", () => {
  assert.match(server, /function handleUpload/);
  assert.match(server, /requireAuth\(req\)/);
  assert.match(server, /MAX_UPLOAD_BYTES/);
  assert.match(server, /"uploads"/);
  assert.match(server, /"POST \/upload": handleUpload/);
});
