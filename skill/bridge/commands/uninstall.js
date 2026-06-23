// cmux-iphone uninstall — remove Cmux iPhone's hooks + service. Surgical:
// only Cmux iPhone's own pieces. --purge also deletes config/secrets/logs.

import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { paths, clearRuntime } from "../lib/config.js";
import * as cmux from "../cmux.js";

export async function run(args) {
  const purge = args.includes("--purge");

  // 1) Remove Claude hooks via the existing (now-surgical) script.
  const script = fileURLToPath(new URL("../../setup-hooks.sh", import.meta.url));
  spawnSync("bash", [script, "--remove"], { stdio: "inherit" });

  // 2) Remove the LaunchAgent (if installed). Also clean up the LEGACY label
  //    (com.claudewatch.bridge) that older installers wrote, so a stale service
  //    can't keep running after rename.
  const uid = os.userInfo().uid;
  const legacyPlist = paths.launchAgentPlist.replace("com.cmuxiphone.bridge", "com.claudewatch.bridge");
  for (const [label, plist] of [
    [paths.plistLabel, paths.launchAgentPlist],
    ["com.claudewatch.bridge", legacyPlist],
  ]) {
    try {
      execFileSync("launchctl", ["bootout", `gui/${uid}/${label}`], { stdio: "ignore" });
    } catch { /* not loaded */ }
    try {
      if (fs.existsSync(plist)) {
        fs.rmSync(plist, { force: true });
        console.log(`Removed LaunchAgent (${label}).`);
      }
    } catch { /* ignore */ }
  }

  // 3) Stop the in-cmux bridge by removing its workspace — otherwise it keeps
  //    serving the LAN after uninstall. Best-effort (cmux may be absent/asleep).
  const ws = await cmux.removeBridgeWorkspace();
  if (ws.removed) console.log('Closed the "Agent Bridge" cmux workspace.');
  else if (ws.reason !== "cmux not found" && ws.reason !== "no Agent Bridge workspace") {
    console.log(`Could not auto-close the cmux workspace (${ws.reason}). Close the "Agent Bridge" workspace manually.`);
  }
  clearRuntime(); // drop the stale bound-port marker

  // 4) Data.
  if (purge) {
    for (const dir of [paths.dataDir, paths.logDir]) {
      try { fs.rmSync(dir, { recursive: true, force: true }); console.log(`Purged ${dir}`); } catch { /* ignore */ }
    }
  } else {
    console.log(`Kept config/secrets in ${paths.dataDir} (use --purge to delete).`);
  }

  console.log("Uninstall complete.");
  return 0;
}
