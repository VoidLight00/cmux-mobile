import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const html = readFileSync(path.resolve(fileURLToPath(import.meta.url), "../../../webclient.html"), "utf-8");

test("cmux Esc restores the last sent terminal input for editing", () => {
  assert.match(html, /cmLastInput\.set\(cmTermId, t\)/);
  assert.match(html, /function restoreCmInput\(\)/);
  assert.match(html, /if\(k==='escape' && restoreCmInput\(\)\) return/);
});
