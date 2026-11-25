import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { branch, ids, meFixture } from "../../test/fixtures";
import { renderApp } from "../../test/render-app";
import { signedInBackend } from "../../test/server";
import { useContextBranch } from "./use-context-branch";

const centro = branch(ids.branchA, ids.companyA, "Sucursal Centro");
const norte = branch(ids.branchA2, ids.companyA, "Sucursal Norte");

function Probe() {
  const { branch: current, needsChoice } = useContextBranch();
  return <p>{`sucursal=${current?.name ?? "ninguna"};elegir=${String(needsChoice)}`}</p>;
}

const renderProbe = () =>
  renderApp({ route: "/probe", workspaceChildren: [{ path: "probe", element: <Probe /> }] });

describe("useContextBranch", () => {
  it("con una sucursal en el contexto devuelve esa, aunque la empresa tenga varias", async () => {
    signedInBackend({
      me: meFixture({ role: "company_manager", branch: norte }),
      branches: [centro, norte],
    });
    await renderProbe();

    expect(await screen.findByText("sucursal=Sucursal Norte;elegir=false")).toBeTruthy();
  });

  it("sin sucursal en el contexto y con una sola sucursal real devuelve esa", async () => {
    signedInBackend({
      me: meFixture({ role: "company_manager", branch: null }),
      branches: [centro],
    });
    await renderProbe();

    expect(await screen.findByText("sucursal=Sucursal Centro;elegir=false")).toBeTruthy();
  });

  it("sin sucursal en el contexto y con varias pide elegirla en el selector global", async () => {
    signedInBackend({
      me: meFixture({ role: "company_manager", branch: null }),
      branches: [centro, norte],
    });
    await renderProbe();

    expect(await screen.findByText("sucursal=ninguna;elegir=true")).toBeTruthy();
  });
});
