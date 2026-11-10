import { describe, expect, it } from "vitest";
import { loginPathFor, safeReturnPath } from "./return-path";

describe("ruta de retorno tras el login", () => {
  it("conserva la ruta, la búsqueda y el hash de donde venía", () => {
    expect(loginPathFor({ pathname: "/agenda", search: "?dia=2026-11-09", hash: "#h" })).toBe(
      "/login?next=%2Fagenda%3Fdia%3D2026-11-09%23h",
    );
  });

  it("desde la raíz no añade ?next", () => {
    expect(loginPathFor({ pathname: "/", search: "", hash: "" })).toBe("/login");
  });

  it("no encadena ?next si ya está en /login", () => {
    expect(loginPathFor({ pathname: "/login", search: "?next=%2Fagenda", hash: "" })).toBe(
      "/login?next=%2Fagenda",
    );
  });

  it("acepta rutas internas", () => {
    expect(safeReturnPath("/agenda?dia=1")).toBe("/agenda?dia=1");
  });

  it.each([
    ["una URL absoluta (open redirect)", "https://malo.example/robar"],
    ["una URL sin esquema con doble barra", "//malo.example"],
    ["una barra invertida que algunos navegadores tratan como barra", "/\\malo.example"],
    ["un esquema javascript", "javascript:alert(1)"],
    ["vacío", ""],
    ["nulo", null],
    ["el propio /login", "/login"],
  ])("rechaza %s y vuelve a la raíz", (_label, raw) => {
    expect(safeReturnPath(raw)).toBe("/");
  });
});
