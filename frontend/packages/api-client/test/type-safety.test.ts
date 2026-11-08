import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";

// Criterio 5 de M0.06: "dado el cliente generado, cuando el código TS accede a un campo inexistente de la
// respuesta, entonces tsc falla". Se ejecuta tsc de verdad contra dos fixtures.
const tsc = fileURLToPath(new URL("../node_modules/.bin/tsc", import.meta.url));
const fixtures = fileURLToPath(new URL("./fixtures/", import.meta.url));

function compile(fixture: "good" | "bad") {
  return spawnSync(tsc, ["--noEmit", "-p", `${fixtures}tsconfig.${fixture}.json`], {
    encoding: "utf8",
  });
}

describe("el cliente generado tipa la respuesta", () => {
  test("acceder a campos que existen en el contrato compila", () => {
    const result = compile("good");

    expect(result.stdout).toBe("");
    expect(result.status).toBe(0);
  });

  test("acceder a un campo inexistente hace fallar tsc con TS2339", () => {
    const result = compile("bad");

    expect(result.status).not.toBe(0);
    expect(result.stdout).toMatch(
      /bad-field\.ts.*error TS2339: Property 'phone_number' does not exist on type/,
    );
  });
});
