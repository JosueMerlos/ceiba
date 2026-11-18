import { describe, expect, it } from "vitest";
import { createIdempotencyKeys } from "./idempotency-keys";

function keys() {
  let next = 0;
  return createIdempotencyKeys(() => `clave-${(next += 1)}`);
}

describe("claves de idempotencia", () => {
  it("reintentar el mismo cuerpo reutiliza la clave", () => {
    const store = keys();
    expect(store.keyFor({ a: 1 })).toBe("clave-1");
    expect(store.keyFor({ a: 1 })).toBe("clave-1");
  });

  it("cambiar el cuerpo exige otra clave: la API rechazaría la anterior", () => {
    const store = keys();
    store.keyFor({ a: 1 });
    expect(store.keyFor({ a: 2 })).toBe("clave-2");
  });

  it("después de un éxito el mismo cuerpo es una operación nueva", () => {
    const store = keys();
    store.keyFor({ a: 1 });
    store.settle();
    expect(store.keyFor({ a: 1 })).toBe("clave-2");
  });
});
