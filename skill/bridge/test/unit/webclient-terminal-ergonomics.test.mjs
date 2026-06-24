import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const html = readFileSync(path.resolve(fileURLToPath(import.meta.url), "../../../webclient.html"), "utf-8");

test("mobile terminal has scale controls and readable spacing", () => {
  assert.match(html, /id="scaleDown"/);
  assert.match(html, /id="scaleUp"/);
  assert.match(html, /--ui-scale/);
  assert.match(html, /--term-size/);
  assert.match(html, /white-space:pre/);
  assert.match(html, /setScale\(next\)/);
});

test("mobile terminal can attach an image and insert its saved path", () => {
  assert.match(html, /id="imagePick"/);
  assert.match(html, /accept="image\/\*"/);
  assert.match(html, /function attachImage\(/);
  assert.match(html, /\/upload/);
});
