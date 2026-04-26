// Reverse proxy bound to Render's $PORT.
//
// Two jobs:
//   1. Answer /health immediately so Render's port-scan and health checks
//      succeed even before the OpenClaw gateway has finished booting
//      (~3.5 min cold boot).
//   2. Forward everything else (HTTP + WebSocket upgrades) to the gateway
//      on localhost:18789, so the Control UI is reachable at the public
//      Render URL.
//
// Replaces the previous health-listener.mjs (which only did job 1).

import http from "node:http";
import net from "node:net";

const PUBLIC_PORT = Number.parseInt(process.env.PORT ?? "10000", 10);
const GATEWAY_PORT = Number.parseInt(
  process.env.OPENCLAW_GATEWAY_PORT ?? "18789",
  10,
);
const GATEWAY_HOST = "127.0.0.1";

function fastHealth(res) {
  res.statusCode = 200;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end('{"ok":true,"status":"live"}');
}

function gatewayUnavailable(res, err) {
  res.statusCode = 503;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Retry-After", "10");
  res.end(
    JSON.stringify({
      ok: false,
      status: "gateway_starting",
      detail: err?.code ?? err?.message ?? "upstream_unreachable",
    }),
  );
}

const server = http.createServer((req, res) => {
  if (req.url === "/health" || req.url === "/healthz") {
    fastHealth(res);
    return;
  }

  const upstream = http.request(
    {
      host: GATEWAY_HOST,
      port: GATEWAY_PORT,
      method: req.method,
      path: req.url,
      headers: req.headers,
    },
    (upstreamRes) => {
      res.writeHead(upstreamRes.statusCode ?? 502, upstreamRes.headers);
      upstreamRes.pipe(res);
    },
  );
  upstream.on("error", (err) => {
    if (!res.headersSent) gatewayUnavailable(res, err);
    else res.destroy();
  });
  req.pipe(upstream);
});

server.on("upgrade", (req, clientSocket, head) => {
  const upstream = net.connect(GATEWAY_PORT, GATEWAY_HOST, () => {
    const reqLine = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`;
    const headers = Object.entries(req.headers)
      .map(([k, v]) =>
        Array.isArray(v) ? v.map((vv) => `${k}: ${vv}`).join("\r\n") : `${k}: ${v}`,
      )
      .join("\r\n");
    upstream.write(`${reqLine}${headers}\r\n\r\n`);
    if (head?.length) upstream.write(head);
    upstream.pipe(clientSocket);
    clientSocket.pipe(upstream);
  });
  const bail = () => {
    clientSocket.destroy();
    upstream.destroy();
  };
  upstream.on("error", bail);
  clientSocket.on("error", bail);
});

server.listen(PUBLIC_PORT, "0.0.0.0", () => {
  console.log(
    `[proxy] listening on 0.0.0.0:${PUBLIC_PORT} -> gateway ${GATEWAY_HOST}:${GATEWAY_PORT}`,
  );
});
