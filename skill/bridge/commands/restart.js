// cmux-iphone restart — restart the bridge (runner-aware).

import { execFileSync } from "node:child_process";
import os from "node:os";
import { getConfig, getRuntime, paths } from "../lib/config.js";

export async function run() {
  const cfg = getConfig();
  if (cfg.runner === "launchd") {
    try {
      execFileSync("launchctl", ["kickstart", "-k", `gui/${os.userInfo().uid}/${paths.plistLabel}`], { stdio: "inherit" });
      console.log("Restarted (launchctl kickstart).");
      return 0;
    } catch (e) {
      console.log(`launchctl kickstart failed: ${e.message}`);
      console.log("Is the LaunchAgent installed? Try 'cmux-iphone setup'.");
      return 1;
    }
  }
  // cmux (or unset) runner: the in-cmux supervisor (run-in-cmux.sh) relaunches the
  // bridge whenever it exits, so a restart = terminate the running process and let
  // it come back. The pid is in runtime.json (written by the server when it binds).
  const rt = getRuntime();
  if (rt.pid) {
    try {
      process.kill(rt.pid, "SIGTERM");
      console.log(`Restarted (signaled bridge pid ${rt.pid}; the in-cmux supervisor relaunches it).`);
      return 0;
    } catch (e) {
      console.log(`Could not signal bridge pid ${rt.pid}: ${e.message}`);
    }
  }
  console.log("No running bridge found. Close + reopen the \"Agent Bridge\" cmux");
  console.log("workspace, or run 'cmux-iphone setup'.");
  return 0;
}
