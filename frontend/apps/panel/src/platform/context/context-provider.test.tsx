import { ApiClientProvider, createApiClient, useMeQuery } from "@ceiba/api-client";
import { QueryClient, QueryClientProvider, useQuery } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { API, company, ids, meFixture, organization } from "../../test/fixtures";
import { server, signedInBackend } from "../../test/server";
import { ContextProvider, useContextSelection } from "./context-provider";

describe("ContextProvider", () => {
  it("criterio 2: cambiar de organización descarta los datos cacheados de la anterior", async () => {
    let activeOrganization = "Org A";
    signedInBackend({
      me: (query) => {
        const switchedToB = query.get("organization_id") === ids.orgB;
        activeOrganization = switchedToB ? "Org B" : "Org A";
        return meFixture({
          organization: organization(switchedToB ? ids.orgB : ids.orgA, activeOrganization),
          company: company(switchedToB ? ids.companyB : ids.companyA, "Empresa"),
        });
      },
    });
    // A business resource whose response depends on the organization active on the server.
    server.use(
      http.get(`${API}/api/v1/probe`, () =>
        HttpResponse.json({ text: `datos de ${activeOrganization}` }),
      ),
    );

    function Probe() {
      const { switchContext, selection } = useContextSelection();
      const me = useMeQuery(selection);
      const probe = useQuery({
        queryKey: ["probe"],
        queryFn: async () =>
          (await fetch(`${API}/api/v1/probe`)).json() as Promise<{ text: string }>,
        enabled: me.isSuccess,
      });
      return (
        <div>
          <p>{probe.data?.text ?? "cargando"}</p>
          <button type="button" onClick={() => switchContext({ organization_id: ids.orgB })}>
            Cambiar a B
          </button>
        </div>
      );
    }

    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false, staleTime: 60_000 } },
    });
    render(
      <QueryClientProvider client={queryClient}>
        <ApiClientProvider client={createApiClient({ baseUrl: API })}>
          <ContextProvider>
            <Probe />
          </ContextProvider>
        </ApiClientProvider>
      </QueryClientProvider>,
    );
    expect(await screen.findByText("datos de Org A")).toBeTruthy();

    await userEvent.click(screen.getByRole("button", { name: "Cambiar a B" }));

    // A's data is never seen again (not even stale while the new data loads).
    expect(screen.queryByText("datos de Org A")).toBeNull();
    await waitFor(() => expect(screen.getByText("datos de Org B")).toBeTruthy());
  });

  it("conserva la sesión en la caché al cambiar de contexto (no obliga a volver a entrar)", async () => {
    signedInBackend();
    const queryClient = new QueryClient();
    queryClient.setQueryData(["session"], { data: { user: {} } });
    queryClient.setQueryData(["clientes"], ["x"]);

    function Switch() {
      const { switchContext } = useContextSelection();
      return (
        <button type="button" onClick={() => switchContext({ organization_id: ids.orgB })}>
          Cambiar
        </button>
      );
    }
    render(
      <QueryClientProvider client={queryClient}>
        <ContextProvider>
          <Switch />
        </ContextProvider>
      </QueryClientProvider>,
    );

    await userEvent.click(screen.getByRole("button", { name: "Cambiar" }));

    expect(queryClient.getQueryData(["session"])).toBeTruthy();
    expect(queryClient.getQueryData(["clientes"])).toBeUndefined();
  });
});
