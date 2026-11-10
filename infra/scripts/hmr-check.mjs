// Checks Vite HMR through the proxy: upgrades to a websocket on the PROXY port with Host "localhost:8080" (like a
// browser), edits a component and waits for Vite's "update" message.
// Invoked from infra/scripts/hmr-check.sh: node - <panel|booking> <websocket-path>
//
// Uses http instead of the global WebSocket because the latter cannot set the Host header, and Vite rejects unknown
// hosts (proxy:8080) just as it would for a misconfigured browser.
//
// Vite only emits "update" for modules already in its graph. On a cold start nobody has requested App.tsx yet, so the
// edit produces no message and the check failed intermittently. Hence (1) the module is requested through the proxy
// before editing, as a browser would, and (2) if no update still arrives, it retries once.
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";

const [app, path] = process.argv.slice(-2).length === 2 ? process.argv.slice(-2) : [];
// Root component of each app (the panel's lives in src/app/app.tsx).
const rootComponent = app === "panel" ? "src/app/app.tsx" : "src/App.tsx";
const file = `/app/frontend/apps/${app}/${rootComponent}`;
const modulePath = `${path}${rootComponent}`;
// Public proxy port (PROXY_PORT; the Vite containers receive it as PUBLIC_PORT).
const publicPort = Number(process.env.PUBLIC_PORT ?? 8080);
const UPDATE_TIMEOUT_MS = 10_000;
const MAX_ATTEMPTS = 2;

const original = readFileSync(file, "utf8");
const restore = () => writeFileSync(file, original);
// Whatever happens (success, failure, Ctrl-C or exception) the component returns to its original state.
process.on("exit", restore);
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => process.exit(130));

const proxyOptions = (requestPath, headers = {}) => ({
  host: "proxy", port: publicPort, path: requestPath, headers: { Host: `localhost:${publicPort}`, ...headers },
});

// Requests the module from Vite through the proxy so it enters Vite's module graph.
const loadModule = () => new Promise((resolve, reject) => {
  http.get(proxyOptions(modulePath), (response) => {
    response.resume();
    response.on("end", () => (response.statusCode === 200
      ? resolve()
      : reject(new Error(`${modulePath} respondió ${response.statusCode}`))));
  }).on("error", reject);
});

// Unmasked server frames: [opcode, length (7 bits | 126+2 bytes | 127+8 bytes), payload].
// Returns the complete JSON text messages and the remaining buffer.
const parseFrames = (buffer) => {
  const messages = [];
  for (;;) {
    if (buffer.length < 2) break;
    let length = buffer[1] & 0x7f, offset = 2;
    if (length === 126) { if (buffer.length < 4) break; length = buffer.readUInt16BE(2); offset = 4; }
    else if (length === 127) { if (buffer.length < 10) break; length = Number(buffer.readBigUInt64BE(2)); offset = 10; }
    if (buffer.length < offset + length) break;
    const isText = (buffer[0] & 0x0f) === 0x1; // ping/pong/close/binary frames are ignored
    const payload = buffer.subarray(offset, offset + length).toString("utf8");
    buffer = buffer.subarray(offset + length);
    if (!isText) continue;
    try { messages.push(JSON.parse(payload)); } catch { /* frame no JSON: se ignora */ }
  }
  return { messages, buffer };
};

// One attempt: opens the websocket, edits the component on "connected" and waits for the "update".
const attempt = () => new Promise((resolve) => {
  let settled = false;
  const settle = (result) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    restore();
    request.destroy();
    resolve(result);
  };
  const timer = setTimeout(() => settle({ reason: `no llegó ningún update de HMR en ${UPDATE_TIMEOUT_MS / 1000} s` }), UPDATE_TIMEOUT_MS);

  const request = http.request(proxyOptions(`${path}?token=hmr-check`, {
    Connection: "Upgrade", Upgrade: "websocket",
    "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
    "Sec-WebSocket-Protocol": "vite-hmr",
  }));
  request.on("response", (response) => settle({ reason: `sin upgrade, el proxy respondió ${response.statusCode}` }));
  request.on("error", (error) => settle({ reason: error.message }));
  request.on("upgrade", (response, socket) => {
    if (response.statusCode !== 101) return settle({ reason: `upgrade con status ${response.statusCode}` });
    let buffer = Buffer.alloc(0);
    socket.on("error", (error) => settle({ reason: error.message }));
    socket.on("data", (chunk) => {
      const parsed = parseFrames(Buffer.concat([buffer, chunk]));
      buffer = parsed.buffer;
      for (const message of parsed.messages) {
        if (message.type === "connected") appendFileSync(file, "\n// hmr-check\n");
        if (message.type === "update") return settle({ updatedPath: message.updates[0].path });
      }
    });
  });
  request.end();
});

try {
  await loadModule();
} catch (error) {
  console.error(`FALLA ${app}: no se pudo cargar ${modulePath} (${error.message})`);
  process.exit(1);
}

let lastReason = "";
for (let number = 1; number <= MAX_ATTEMPTS; number += 1) {
  const result = await attempt();
  if (result.updatedPath) {
    const retried = number > 1 ? ` (tras ${number} intentos)` : "";
    console.log(`ok    ${app}: update de HMR recibido a través del proxy (${result.updatedPath})${retried}`);
    process.exit(0);
  }
  lastReason = result.reason;
  console.error(`aviso ${app}: intento ${number}/${MAX_ATTEMPTS} sin update (${lastReason})`);
}
console.error(`FALLA ${app}: ${lastReason}`);
process.exit(1);
