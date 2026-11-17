import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { meFixture } from "../../test/fixtures";
import { renderApp } from "../../test/render-app";
import { signedInBackend } from "../../test/server";
import { AsidePortal } from "./aside-slot";

function Page({ show }: { show: boolean }) {
  return (
    <>
      <p>Pantalla</p>
      {show ? (
        <AsidePortal>
          <aside aria-label="Panel contextual de prueba">Edición</aside>
        </AsidePortal>
      ) : null}
    </>
  );
}

describe("AsidePortal", () => {
  it("dibuja el panel en la ranura lateral del marco, no dentro de la hoja principal", async () => {
    signedInBackend({ me: meFixture({ role: "receptionist" }) });
    await renderApp({ route: "/x", workspaceChildren: [{ path: "x", element: <Page show /> }] });

    const panel = await screen.findByRole("complementary", { name: "Panel contextual de prueba" });
    expect(panel.closest("[data-slot=app-aside]")).not.toBeNull();
    expect(panel.closest("main")).toBeNull();
  });

  it("sin el portal no queda nada en la ranura (adversarial: no deja restos)", async () => {
    signedInBackend({ me: meFixture({ role: "receptionist" }) });
    await renderApp({
      route: "/x",
      workspaceChildren: [{ path: "x", element: <Page show={false} /> }],
    });

    await screen.findByText("Pantalla");
    expect(screen.queryByRole("complementary", { name: "Panel contextual de prueba" })).toBeNull();
    expect(document.querySelector("[data-slot=app-aside]")?.childElementCount ?? 0).toBe(0);
  });

  it("fuera del marco (sin ranura) no dibuja nada y no falla", async () => {
    const { render } = await import("@testing-library/react");
    render(<AsidePortal>contenido</AsidePortal>);

    expect(screen.queryByText("contenido")).toBeNull();
  });
});
