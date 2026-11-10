// Comprueba el HMR de Vite a través del proxy (criterio 5 de M0.01).
// Hace el upgrade a websocket por el puerto del PROXY con Host "localhost:8080" (como un navegador),
// modifica un componente y espera el mensaje "update" de Vite.
// Se invoca desde infra/scripts/hmr-check.sh: node - <panel|booking> <ruta-del-websocket>
//
// Se usa http en vez de WebSocket global porque este no permite fijar la cabecera Host, y Vite
// rechaza hosts desconocidos (proxy:8080) igual que lo haría con un navegador mal configurado.
//
// Robustez (M0.02): Vite solo emite "update" para módulos que ya están en su grafo. En un arranque
// en frío nadie ha pedido App.tsx todavía y la edición no genera ningún mensaje, de modo que la
// prueba fallaba de forma intermitente. Por eso (1) se pide el módulo a través del proxy antes de
// editar, como haría el navegador, y (2) si aun así no llega el update, se reintenta una vez.
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";

const [app, path] = process.argv.slice(-2).length === 2 ? process.argv.slice(-2) : [];
// Componente raíz de cada app (en el panel vive en src/app/app.tsx desde M0.12).
const rootComponent = app === "panel" ? "src/app/app.tsx" : "src/App.tsx";
const file = `/app/frontend/apps/${app}/${rootComponent}`;
const modulePath = `${path}${rootComponent}`;
// Puerto público del proxy (PROXY_PORT; los contenedores de Vite lo reciben como PUBLIC_PORT).
const publicPort = Number(process.env.PUBLIC_PORT ?? 8080);
const UPDATE_TIMEOUT_MS = 10_000;
const MAX_ATTEMPTS = 2;

const original = readFileSync(file, "utf8");
const restore = () => writeFileSync(file, original);
// Pase lo que pase (éxito, fallo, Ctrl-C o excepción) el componente vuelve a su estado original.
process.on("exit", restore);
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => process.exit(130));

const proxyOptions = (requestPath, headers = {}) => ({
  host: "proxy", port: publicPort, path: requestPath, headers: { Host: `localhost:${publicPort}`, ...headers },
});

// Pide el módulo a Vite a través del proxy para que entre en su grafo de módulos.
const loadModule = () => new Promise((resolve, reject) => {
  http.get(proxyOptions(modulePath), (response) => {
    response.resume();
    response.on("end", () => (response.statusCode === 200
      ? resolve()
      : reject(new Error(`${modulePath} respondió ${response.statusCode}`))));
  }).on("error", reject);
});

// Frames de servidor sin máscara: [opcode, longitud (7 bits | 126+2 bytes | 127+8 bytes), payload].
// Devuelve los mensajes de texto JSON completos y el buffer restante.
const parseFrames = (buffer) => {
  const messages = [];
  for (;;) {
    if (buffer.length < 2) break;
    let length = buffer[1] & 0x7f, offset = 2;
    if (length === 126) { if (buffer.length < 4) break; length = buffer.readUInt16BE(2); offset = 4; }
    else if (length === 127) { if (buffer.length < 10) break; length = Number(buffer.readBigUInt64BE(2)); offset = 10; }
    if (buffer.length < offset + length) break;
    const isText = (buffer[0] & 0x0f) === 0x1; // se ignoran ping/pong/close/binarios
    const payload = buffer.subarray(offset, offset + length).toString("utf8");
    buffer = buffer.subarray(offset + length);
    if (!isText) continue;
    try { messages.push(JSON.parse(payload)); } catch { /* frame no JSON: se ignora */ }
  }
  return { messages, buffer };
};

// Un intento: abre el websocket, edita el componente al recibir "connected" y espera el "update".
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
