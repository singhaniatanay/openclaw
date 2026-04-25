// Tiny HTTP listener bound to Render's $PORT so the platform's port scan
// and health checks succeed *immediately* — well before the OpenClaw
// gateway finishes loading plugins (~4 minutes on free tier).
//
// We don't need to expose the gateway externally for a Discord-only
// deployment: Discord uses outbound websockets, so nothing inbound is
// required. This listener just satisfies Render.
import http from "node:http";

const port = Number.parseInt(process.env.PORT ?? "10000", 10);

http
  .createServer((_req, res) => {
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.setHeader("Cache-Control", "no-store");
    res.end('{"ok":true,"status":"live"}');
  })
  .listen(port, "0.0.0.0", () => {
    console.log(`[health-listener] listening on 0.0.0.0:${port}`);
  });
