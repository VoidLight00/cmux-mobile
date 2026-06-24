import { test } from "node:test";
import assert from "node:assert/strict";
import os from "node:os";
import * as sys from "../../lib/sys.js";

test("lanIPv4s keeps every phone-reachable LAN address", () => {
  const real = os.networkInterfaces;
  os.networkInterfaces = () => ({
    lo0: [{ family: "IPv4", address: "127.0.0.1", internal: true }],
    en0: [{ family: "IPv4", address: "192.168.0.12", internal: false }],
    bridge100: [{ family: "IPv4", address: "172.20.10.2", internal: false }],
    utun7: [{ family: "IPv4", address: "100.66.91.74", internal: false }],
    awdl0: [{ family: "IPv4", address: "169.254.7.8", internal: false }],
  });
  try {
    assert.equal(typeof sys.lanIPv4s, "function");
    assert.deepEqual(sys.lanIPv4s(), ["192.168.0.12", "172.20.10.2"]);
    assert.equal(sys.lanIPv4(), "192.168.0.12");
  } finally {
    os.networkInterfaces = real;
  }
});
