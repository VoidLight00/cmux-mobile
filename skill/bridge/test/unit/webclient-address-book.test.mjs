import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const html = readFileSync(path.resolve(fileURLToPath(import.meta.url), "../../../webclient.html"), "utf-8");

test("pairing screen exposes saved bridge addresses", () => {
  assert.match(html, /id="macsPairBtn"/);
  assert.match(html, /저장된 주소/);
  assert.match(html, /macsPairBtn'\)\.onclick=\(\)=>openMacs\(\)/);
});
