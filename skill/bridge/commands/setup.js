// cmux-iphone setup — idempotent bootstrap. Safe to re-run: it never rotates
// existing secrets, backs up Claude settings before merging hooks, and reports
// "already configured" for steps that are already done.

import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { getConfig, saveConfig, getRuntime, paths } from "../lib/config.js";
import { which, lanIPv4, tailscaleIPv4 } from "../lib/sys.js";
import { api, controlApi, bridgeUp } from "../lib/bridge-client.js";
import * as cmux from "../cmux.js";

const sh = (p) => stablePath(fileURLToPath(new URL(p, import.meta.url)));

// Under Homebrew, import.meta.url resolves to a version-pinned Cellar realpath
// (…/Cellar/cmux-iphone/<version>/…). Baking that into the LaunchAgent plist or
// the cmux workspace command means `brew upgrade` (which deletes the old Cellar
// dir) breaks the bridge. Rewrite it to the STABLE opt symlink, which brew
// repoints on every upgrade. No-op for non-Homebrew installs.
function stablePath(p) {
  const m = p.match(/^(.*)\/Cellar\/cmux-iphone\/[^/]+\/(.*)$/);
  return m ? `${m[1]}/opt/cmux-iphone/${m[2]}` : p;
}

export async function run(args = []) {
  const cfg = getConfig();
  const apiPort = String(process.env.PORT || cfg.ports.apiPort);
  const forceCmux = args.includes("--cmux");
  const forceLaunchd = args.includes("--launchd");

  // 1) Preflight
  if (process.platform !== "darwin") {
    console.error("cmux-iphone targets macOS.");
    return 1;
  }
  const major = parseInt(process.versions.node, 10);
  if (major < 18) {
    console.error(`Node 18+ required (have v${process.versions.node}).`);
    return 1;
  }
  console.log(`✓ macOS ${os.release()} · Node v${process.versions.node}`);
  if (which("claude")) console.log("✓ Claude Code detected");
  if (which("codex")) console.log("✓ Codex detected");

  // 2) Pick a runner. cmux mirror needs the bridge INSIDE cmux (a launchd
  //    process can't reach the control socket). Distinguish "installed" from
  //    "RPC reachable" — picking a cmux runner we can't actually drive would
  //    leave the bridge dead. Flags override: --cmux / --launchd.
  let runner;
  const cmuxPresent = cmux.cmuxAvailable();
  const cmuxOk = cmuxPresent && (await cmux.cmuxReachable());
  if (forceLaunchd) {
    runner = "launchd";
    console.log("• runner: LaunchAgent (--launchd) — hook/phone/Codex only");
  } else if (forceCmux || cmuxPresent) {
    if (!cmuxOk) {
      console.error("\n✗ cmux is installed but its control socket isn't reachable.");
      console.error("  Start cmux, configure its socket password, then re-run — OR run this");
      console.error("  command from INSIDE a cmux terminal. To skip cmux and use hook/phone");
      console.error("  sessions only: cmux-iphone setup --launchd");
      return 1; // do NOT proceed with a cmux runner we can't drive
    }
    runner = "cmux";
    console.log("✓ cmux reachable — live mirror ON (runner: in-cmux)");
  } else {
    runner = "launchd";
    console.log("• cmux not found — hook/phone/Codex only (runner: LaunchAgent)");
  }

  // 3) Persist config (merge, never clobber)
  saveConfig({ runner, cmux: { ...cfg.cmux, enabled: runner === "cmux" } });

  // 3a) Bind interface. SECURE DEFAULT is loopback (127.0.0.1): a fresh install
  // is never reachable over plaintext HTTP by the rest of the LAN. Exposing the
  // bridge to your phone is an explicit choice:
  //   HOST=<addr>     env override (highest priority)
  //   --bind <addr>   pin a specific interface (e.g. a Tailscale 100.x IP)
  //   --lan           bind 0.0.0.0 — the whole LAN, PLAINTEXT (eavesdrop risk)
  //   (default)       keep any prior choice in config.json, else loopback
  const bindIdx = args.indexOf("--bind");
  let bindAddress;
  if (process.env.HOST) bindAddress = process.env.HOST;
  else if (bindIdx !== -1 && args[bindIdx + 1]) bindAddress = args[bindIdx + 1];
  else if (args.includes("--lan")) bindAddress = "0.0.0.0";
  else bindAddress = cfg.bindAddress || "127.0.0.1";
  saveConfig({ bindAddress });
  const localOnly = bindAddress === "127.0.0.1" || bindAddress === "::1";
  const wholeLan = bindAddress === "0.0.0.0" || bindAddress === "::";
  if (localOnly) {
    console.log("• bind: 127.0.0.1 (LOCAL-ONLY, secure default) — your phone can't reach it yet.");
    console.log("        Expose it over Tailscale (encrypted, recommended):  cmux-iphone setup --bind <tailscale-ip>");
    console.log("        …or your LAN (plaintext, trusted networks only):     cmux-iphone setup --lan");
  } else if (wholeLan) {
    console.log("• bind: 0.0.0.0 (entire LAN, PLAINTEXT) — prefer Tailscale on untrusted networks.");
  } else {
    console.log(`• bind: ${bindAddress}`);
  }
  // Pairing. DEFAULT is a STABLE per-machine code so non-developers never have to
  // chase a rotating one: random 6-digit, stored 0600 (not in the repo), retrievable
  // anytime with `cmux-iphone pair`; the CMUX_IPHONE_PAIR_CODE env var overrides;
  // generated once, kept on re-run. `--rotating` opts into the higher-security
  // rotating mode (fresh code per restart, 24h TTL, cleared after a device pairs).
  const wantRotating = args.includes("--rotating");
  let pairCode = null;
  if (wantRotating) {
    saveConfig({ pairing: { ...cfg.pairing, fixedCode: null } });
    console.log("• pairing: rotating code (fresh per restart, 24h TTL) — re-show with 'cmux-iphone pair'");
  } else {
    pairCode = process.env.CMUX_IPHONE_PAIR_CODE || cfg.pairing?.fixedCode
      || crypto.randomInt(0, 1_000_000).toString().padStart(6, "0");
    saveConfig({ pairing: { ...cfg.pairing, fixedCode: pairCode } });
  }
  console.log(`✓ config written → ${paths.configFile}`);

  // 4) Dependencies (reproducible)
  const dep = spawnSync("bash", [sh("../../setup.sh")], { stdio: "inherit" });
  if (dep.status !== 0) { console.error("Dependency install failed."); return 1; }

  // 5) Claude hooks (the script backs up settings.json + generates the secret)
  const hooks = spawnSync("bash", [sh("../../setup-hooks.sh"), apiPort], { stdio: "inherit" });
  if (hooks.status !== 0) { console.error("Hook install failed."); return 1; }

  // 6) Runner — actually start it (don't just print instructions).
  if (runner === "launchd") {
    const la = spawnSync("bash", [sh("../install-launchd.sh"), apiPort], { stdio: "inherit" });
    if (la.status !== 0) { console.error("LaunchAgent install failed."); return 1; }
  } else {
    try {
      const r = await cmux.ensureBridgeWorkspace(sh("../run-in-cmux.sh"));
      console.log(r.created
        ? '✓ created "Agent Bridge" cmux workspace (runs the bridge inside cmux)'
        : '✓ "Agent Bridge" cmux workspace already present');
      // An already-running bridge holds the OLD config until it restarts. Bounce
      // it so config changes apply now (the in-cmux supervisor relaunches it) —
      // for --rotating OR a changed bind address (else `setup --bind` would
      // silently not take effect on an existing in-cmux bridge).
      if (!r.created) {
        const rt = getRuntime();
        const bindChanged = rt.bindAddress && rt.bindAddress !== bindAddress;
        if ((wantRotating || bindChanged) && rt.pid) {
          const why = bindChanged ? `new bind address (${bindAddress})` : "--rotating";
          try { process.kill(rt.pid, "SIGTERM"); console.log(`• bounced running bridge to apply ${why}`); }
          catch { /* will apply on next restart */ }
        }
      }
    } catch (err) {
      console.error(`✗ could not create the cmux workspace: ${err.message}`);
      return 1;
    }
  }

  // 7) Health check — setup MUST NOT report success if the bridge isn't up.
  let up = false;
  for (let i = 0; i < 12; i++) {
    if (await bridgeUp()) { up = true; break; }
    await new Promise((r) => setTimeout(r, 700));
  }
  if (!up) {
    console.error("\n✗ bridge did not come up. Check `cmux-iphone logs` / `cmux-iphone doctor`.");
    return 1;
  }
  console.log("✓ health check passed");
  if (runner === "cmux" && !(await cmux.cmuxReachable())) {
    console.error("✗ bridge is up but cmux RPC is unreachable — see `cmux-iphone doctor`.");
    return 1;
  }

  // 8) Pair info — show ONLY addresses that actually reach the bound interface,
  // so a loopback-only bridge never advertises a LAN/Tailscale URL that refuses.
  console.log("\nPair your iPhone:");
  const lan = lanIPv4();
  const ts = tailscaleIPv4();
  if (localOnly) {
    console.log("  Bridge is LOCAL-ONLY (127.0.0.1) — not reachable from your phone yet.");
    console.log("  Expose it first (see the 'bind:' note above), then re-run setup.");
  } else if (wholeLan) {
    if (ts) console.log(`  Tailscale: http://${ts}:${apiPort}   (encrypted — preferred)`);
    if (lan) console.log(`  LAN:       http://${lan}:${apiPort}   (plaintext)`);
  } else {
    console.log(`  Bridge:    http://${bindAddress}:${apiPort}`);
  }
  if (pairCode) {
    console.log(`  Code:      ${pairCode}   (stays the same — re-show anytime with 'cmux-iphone pair')`);
  } else if (up) {
    const pc = await controlApi("GET", "/pair-code"); // rotating mode (env/config didn't pin one)
    if (pc.ok && pc.json && pc.json.code) console.log(`  Code:      ${pc.json.code}`);
  }
  console.log("\nThen run 'cmux-iphone doctor' if anything looks off.");
  return 0;
}
