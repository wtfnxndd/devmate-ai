// Serves the Flutter web app and one tiny endpoint: /backend-url returns the current
// Cloudflare Tunnel address of the DevMate backend (written by deploy/cloudflare-tunnel.sh),
// so the site link never changes even though quick-tunnel URLs do.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/backend-url") {
      const api = (await env.DEVMATE_CONFIG.get("api_url")) || "";
      return new Response(api, {
        headers: { "content-type": "text/plain", "cache-control": "no-store", "access-control-allow-origin": "*" },
      });
    }
    return env.ASSETS.fetch(request);
  },
};
