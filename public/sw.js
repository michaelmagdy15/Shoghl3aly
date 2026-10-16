// Thndr EGX Pro - iPhone 15 Pro Web Push Service Worker (iOS 16.4+ / iOS 17 / iOS 18+)
self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("push", (event) => {
  let payload = {
    title: "⚡ Thndr EGX Hourly Briefing",
    body: "Tap to view live EGX 279-stock signals & portfolio status.",
    url: "/?from=push"
  };

  if (event.data) {
    try {
      const parsed = event.data.json();
      payload = { ...payload, ...parsed };
    } catch (e) {
      payload.body = event.data.text() || payload.body;
    }
  }

  const options = {
    body: payload.body,
    icon: "https://cdn-icons-png.flaticon.com/512/831/831378.png",
    badge: "https://cdn-icons-png.flaticon.com/512/831/831378.png",
    tag: payload.tag || "thndr-egx-hourly",
    renotify: true,
    data: {
      url: payload.url || "/"
    }
  };

  event.waitUntil(
    self.registration.showNotification(payload.title, options)
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || "/";

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) {
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }
    })
  );
});
