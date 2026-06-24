/* Cmux Mobile service worker — minimal PWA shell so Android Chrome / iOS Safari
 * can install the web client as a standalone app.
 *
 * Strategy: cache ONLY the static shell (page, manifest, icons) network-first so
 * the app icon launches even when the bridge is briefly unreachable. Every
 * dynamic path (SSE stream, commands, pairing, status, cmux mirror) bypasses the
 * SW entirely and hits the network live — caching them would break real-time use.
 *
 * ponytail: shell-only cache, no precache versioning beyond a name bump. If the
 * shell ever needs offline-first or background sync, add a real strategy then.
 */
const CACHE = "cmux-shell-v2";
const SHELL = ["/", "/manifest.webmanifest", "/icons/icon-192.png", "/icons/icon-512.png"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("message", (e) => {
  if (e.data && e.data.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (e) => {
  if (e.request.method !== "GET") return; // commands/pairing are POST — never touch them
  const u = new URL(e.request.url);
  if (u.origin !== self.location.origin) return;
  const shell = u.pathname === "/" || u.pathname === "/manifest.webmanifest" || u.pathname.startsWith("/icons/");
  if (!shell) return; // /events (SSE), /status, /cmux/* etc. go straight to network
  e.respondWith(
    fetch(e.request)
      .then((r) => { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return r; })
      .catch(() => caches.match(e.request))
  );
});
