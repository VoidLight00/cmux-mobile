// lib/sys.js — small system helpers for the CLI (addresses, perms, binaries).

import os from "node:os";
import fs from "node:fs";
import { execFileSync } from "node:child_process";

export function lanIPv4() {
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const a of ifaces[name] || []) {
      if (a.family === "IPv4" && !a.internal && !a.address.startsWith("169.254")) return a.address;
    }
  }
  return null;
}

export function tailscaleIPv4() {
  const candidates = ["tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"];
  for (const bin of candidates) {
    try {
      const out = execFileSync(bin, ["ip", "-4"], { encoding: "utf-8", timeout: 2000 });
      const ip = out.trim().split("\n")[0];
      if (ip) return ip;
    } catch { /* try next */ }
  }
  return null;
}

export function which(bin) {
  try {
    return execFileSync("/usr/bin/which", [bin], { encoding: "utf-8" }).trim() || null;
  } catch {
    return null;
  }
}

export function fileMode(p) {
  try {
    return (fs.statSync(p).mode & 0o777).toString(8).padStart(3, "0");
  } catch {
    return null;
  }
}

export function exists(p) {
  try { fs.accessSync(p); return true; } catch { return false; }
}
