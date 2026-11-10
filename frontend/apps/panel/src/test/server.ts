import { http, HttpResponse, type JsonBodyType } from "msw";
import { setupServer } from "msw/node";
import {
  API,
  authSession,
  branch,
  company,
  ids,
  meFixture,
  organization,
  problem,
  type Me,
} from "./fixtures";

export const server = setupServer();

const page = (data: unknown[]) => ({ data, page: { has_more: false, next_cursor: null } });

interface Backend {
  me?: { data: Me } | ((query: URLSearchParams) => { data: Me });
  organizations?: ReturnType<typeof organization>[];
  companies?: ReturnType<typeof company>[];
  branches?: ReturnType<typeof branch>[];
  session?: ReturnType<typeof authSession>;
}

/** Un backend de pruebas con sesión iniciada: sesión, /me y las listas del selector de contexto. */
export function signedInBackend({
  me = meFixture(),
  organizations = [organization(ids.orgA, "Barbería El Güegüense")],
  companies = [company(ids.companyA, "Barbería El Güegüense")],
  branches = [branch(ids.branchA, ids.companyA, "Sucursal Centro")],
  session = authSession(),
}: Backend = {}) {
  server.use(
    http.get(`${API}/api/v1/auth/session`, () => HttpResponse.json(session)),
    http.get(`${API}/api/v1/me`, ({ request }) =>
      HttpResponse.json(typeof me === "function" ? me(new URL(request.url).searchParams) : me),
    ),
    http.get(`${API}/api/v1/organizations`, () => HttpResponse.json(page(organizations))),
    http.get(`${API}/api/v1/organizations/:org/companies`, () =>
      HttpResponse.json(page(companies)),
    ),
    http.get(`${API}/api/v1/organizations/:org/companies/:company/branches`, () =>
      HttpResponse.json(page(branches)),
    ),
  );
}

/** Sin sesión: GET /auth/session responde 401 como la API real. */
export function signedOutBackend() {
  server.use(
    http.get(`${API}/api/v1/auth/session`, () =>
      HttpResponse.json(problem(401, "auth.unauthenticated", "Sin sesión"), { status: 401 }),
    ),
  );
}

export function respondWith(status: number, body: JsonBodyType) {
  return () => HttpResponse.json(body, { status });
}
