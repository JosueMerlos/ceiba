// Comprueba el HMR de Vite a través del proxy (criterio 5 de M0.01).
// Hace el upgrade a websocket por el puerto del PROXY con Host "localhost:8080" (como un navegador),
// modifica un componente y espera el mensaje "update" de Vite.
// Se invoca desde infra/scripts/hmr-check.sh: node - <panel|booking> <ruta-del-websocket>
//
// Se usa http en vez de WebSocket global porque este no permite fijar la cabecera Host, y Vite
// rechaza hosts desconocidos (proxy:8080) igual que lo haría con un navegador mal configurado.
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";

const [app, path] = process.argv.slice(-2).length === 2 ? process.argv.slice(-2) : [];
const file = `/app/frontend/apps/${app}/src/App.tsx`;
const original = readFileSync(file, "utf8");
const restore = () => writeFileSync(file, original);
const fail = (reason) => { restore(); console.error(`FALLA ${app}: ${reason}`); process.exit(1); };
const timer = setTimeout(() => fail("no llegó ningún update de HMR en 10 s"), 10_000);

const request = http.request({
  host: "proxy", port: 8080, path: `${path}?token=hmr-check`,
  headers: {
    Host: "localhost:8080", Connection: "Upgrade", Upgrade: "websocket",
    "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
    "Sec-WebSocket-Protocol": "vite-hmr",
  },
});
request.on("response", (response) => fail(`sin upgrade, el proxy respondió ${response.statusCode}`));
request.on("error", (error) => fail(error.message));
request.on("upgrade", (response, socket) => {
  if (response.statusCode !== 101) fail(`upgrade con status ${response.statusCode}`);
  let buffer = Buffer.alloc(0);
  socket.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    // Frames de servidor sin máscara: [opcode, longitud (7 bits | 126+2 bytes | 127+8 bytes), payload]
    for (;;) {
      if (buffer.length < 2) return;
      let length = buffer[1] & 0x7f, offset = 2;
      if (length === 126) { if (buffer.length < 4) return; length = buffer.readUInt16BE(2); offset = 4; }
      else if (length === 127) { if (buffer.length < 10) return; length = Number(buffer.readBigUInt64BE(2)); offset = 10; }
      if (buffer.length < offset + length) return;
      const message = JSON.parse(buffer.subarray(offset, offset + length).toString("utf8"));
      buffer = buffer.subarray(offset + length);
      if (message.type === "connected") appendFileSync(file, "\n// hmr-check\n");
      if (message.type === "update") {
        clearTimeout(timer);
        restore();
        console.log(`ok    ${app}: update de HMR recibido a través del proxy (${message.updates[0].path})`);
        process.exit(0);
      }
    }
  });
});
request.end();
