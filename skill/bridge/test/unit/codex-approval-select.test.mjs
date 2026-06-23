// Pure unit tests for codex approval terminal selection — NO cmux, NO bridge,
// NO live state. Deterministic; always runs as a real release gate.
//
//   node --test test/unit/

import { test } from "node:test";
import assert from "node:assert/strict";
import { selectCodexApprovalTerminal } from "../../cmux.js";

const CMD = "rm -rf ./build && npm run build";
const approvalScreen = (cmd) =>
  `Allow command?\n  ${cmd}\n  1. Yes, proceed\n  2. No\nPress enter to confirm`;
const shellScreen = (cmd) =>
  `user@host /tmp % echo ${cmd}\n${cmd}\nuser@host /tmp %`;   // command present, NO markers

test("picks the single terminal visibly showing the approval", () => {
  const r = selectCodexApprovalTerminal([
    { id: "shell", text: shellScreen(CMD) },
    { id: "codex", text: approvalScreen(CMD) },
  ], CMD);
  assert.equal(r.id, "codex");
  assert.equal(r.ambiguous, false);
});

test("excludes a shell that only has the command in scrollback/visible (no markers)", () => {
  const r = selectCodexApprovalTerminal([
    { id: "shell", text: shellScreen(CMD) },
  ], CMD);
  assert.equal(r.id, null);
  assert.equal(r.ambiguous, false);   // nothing to pin, but not ambiguous
});

test("fail-closed (ambiguous) when two terminals show the same approval command", () => {
  const r = selectCodexApprovalTerminal([
    { id: "codexA", text: approvalScreen(CMD) },
    { id: "codexB", text: approvalScreen(CMD) },
  ], CMD);
  assert.equal(r.id, null);
  assert.equal(r.ambiguous, true);
});

test("disambiguates two approval screens by the command", () => {
  const r = selectCodexApprovalTerminal([
    { id: "other", text: approvalScreen("ls -la /etc") },
    { id: "target", text: approvalScreen(CMD) },
  ], CMD);
  assert.equal(r.id, "target");
  assert.equal(r.ambiguous, false);
});

test("requires BOTH markers — 'Yes, proceed' alone is not an approval screen", () => {
  const r = selectCodexApprovalTerminal([
    { id: "partial", text: `Some output\n  ${CMD}\n  Yes, proceed with caution` },
  ], CMD);
  assert.equal(r.id, null);
});

test("empty / no entries → no pin, not ambiguous", () => {
  assert.deepEqual(selectCodexApprovalTerminal([], CMD), { id: null, ambiguous: false });
  assert.deepEqual(selectCodexApprovalTerminal(undefined, CMD), { id: null, ambiguous: false });
});
