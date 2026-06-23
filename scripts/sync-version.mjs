#!/usr/bin/env node
// scripts/sync-version.mjs — ./VERSION is the single source of truth for the
// release version. This stamps it into every file that carries a version, and
// with --check verifies they all agree (wired into CI).
//
//   node scripts/sync-version.mjs           # write VERSION into all files
//   node scripts/sync-version.mjs --check    # exit 1 if any file disagrees

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const V = fs.readFileSync(path.join(ROOT, "VERSION"), "utf8").trim();
if (!/^\d+\.\d+\.\d+([.-].+)?$/.test(V)) {
  console.error(`Invalid VERSION: "${V}" (expected semver like 0.1.0)`);
  process.exit(1);
}
const check = process.argv.includes("--check");
let bad = 0;

// Each target knows how to READ its current version and how to SET it.
const targets = [
  {
    rel: "skill/bridge/package.json",
    get: (s) => JSON.parse(s).version,
    set: (s) => { const o = JSON.parse(s); o.version = V; return JSON.stringify(o, null, 2) + "\n"; },
  },
  {
    rel: "skill/bridge/package-lock.json",
    get: (s) => JSON.parse(s).version,
    set: (s) => {
      const o = JSON.parse(s);
      o.version = V;
      if (o.packages && o.packages[""]) o.packages[""].version = V;
      return JSON.stringify(o, null, 2) + "\n";
    },
  },
  ...["skill/SKILL.md", ".claude/skills/cmux-iphone/SKILL.md"].map((rel) => ({
    rel,
    get: (s) => (s.match(/^version:\s*(.+)$/m) || [])[1],
    set: (s) => s.replace(/^version:\s*.+$/m, `version: ${V}`),
  })),
  ...["ios/CmuxiPhone/CmuxiPhone iOS/Info.plist", "ios/CmuxiPhone/CmuxiPhone watchOS/Info.plist"].map((rel) => ({
    rel,
    get: (s) => (s.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]*)<\/string>/) || [])[1],
    set: (s) => s.replace(/(<key>CFBundleShortVersionString<\/key>\s*<string>)[^<]*(<\/string>)/, `$1${V}$2`),
  })),
];

for (const t of targets) {
  const p = path.join(ROOT, t.rel);
  let s;
  try { s = fs.readFileSync(p, "utf8"); } catch { console.warn(`skip (missing): ${t.rel}`); continue; }
  const cur = t.get(s);
  if (cur === V) continue;
  if (check) { console.error(`✗ ${t.rel}: ${cur ?? "—"} (expected ${V})`); bad = 1; continue; }
  fs.writeFileSync(p, t.set(s));
  console.log(`✓ ${t.rel}: ${cur ?? "—"} → ${V}`);
}

if (check) {
  if (bad) {
    console.error(`\nVersions out of sync with VERSION (${V}). Run: node scripts/sync-version.mjs`);
    process.exit(1);
  }
  console.log(`All versions match VERSION (${V}).`);
} else {
  console.log(`Done — all files stamped to ${V}.`);
}
