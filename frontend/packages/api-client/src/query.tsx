import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createContext, useContext, type ReactNode } from "react";
import { createApiClient, unwrap, type ApiClient } from "./client";

// Hooks base de TanStack Query sobre el cliente generado. Los `queryFn` usan `unwrap`: devuelven el cuerpo tipado del
// contrato o rechazan con ApiError, que es lo que TanStack Query espera. El estado del servidor vive SOLO en la caché.

const ApiClientContext = createContext<ApiClient | null>(null);

export function ApiClientProvider({
  client,
  children,
}: {
  client?: ApiClient;
  children: ReactNode;
}) {
  return (
    <ApiClientContext.Provider value={client ?? defaultClient()}>
      {children}
    </ApiClientContext.Provider>
  );
}

let shared: ApiClient | undefined;
const defaultClient = () => (shared ??= createApiClient());

export function useApiClient(): ApiClient {
  const client = useContext(ApiClientContext);
  if (!client) throw new Error("useApiClient debe usarse dentro de <ApiClientProvider>");
  return client;
}

/** Contexto elegido: ver GET /api/v1/me. Vacío = el último usado (cookie `ceiba_context`) o el primero disponible. */
export interface MeContext {
  organization_id?: string;
  company_id?: string;
  branch_id?: string;
}

export const queryKeys = {
  session: ["session"] as const,
  me: (context: MeContext = {}) => ["me", context] as const,
  organizations: ["organizations"] as const,
  companies: (organizationId: string) => ["organizations", organizationId, "companies"] as const,
  branches: (organizationId: string, companyId: string) =>
    ["organizations", organizationId, "companies", companyId, "branches"] as const,
};

/** Páginas del selector de contexto: el máximo que admite la API (100). Más de eso no es un selector, es un buscador. */
// El contrato declara X-CSRF-Token como parámetro obligatorio; el middleware del cliente lo reemplaza por el token real.
const CSRF_PLACEHOLDER = "";

const SELECTOR_PAGE = { limit: 100 };

export function useSessionQuery() {
  const client = useApiClient();
  return useQuery({
    queryKey: queryKeys.session,
    queryFn: () => unwrap(client.GET("/api/v1/auth/session")),
    // Una sesión que ya respondió 401 no se vuelve a pedir al montar el login (una sola GET al arrancar).
    retryOnMount: false,
  });
}

export function useMeQuery(context: MeContext = {}) {
  const client = useApiClient();
  return useQuery({
    queryKey: queryKeys.me(context),
    queryFn: () => unwrap(client.GET("/api/v1/me", { params: { query: context } })),
  });
}

export function useOrganizationsQuery({ enabled = true }: { enabled?: boolean } = {}) {
  const client = useApiClient();
  return useQuery({
    queryKey: queryKeys.organizations,
    queryFn: () =>
      unwrap(client.GET("/api/v1/organizations", { params: { query: SELECTOR_PAGE } })),
    enabled,
  });
}

export function useCompaniesQuery(organizationId: string | undefined) {
  const client = useApiClient();
  return useQuery({
    queryKey: queryKeys.companies(organizationId ?? ""),
    queryFn: () =>
      unwrap(
        client.GET("/api/v1/organizations/{organization_id}/companies", {
          params: { path: { organization_id: organizationId! }, query: SELECTOR_PAGE },
        }),
      ),
    enabled: !!organizationId,
  });
}

export function useBranchesQuery(
  organizationId: string | undefined,
  companyId: string | undefined,
) {
  const client = useApiClient();
  return useQuery({
    queryKey: queryKeys.branches(organizationId ?? "", companyId ?? ""),
    queryFn: () =>
      unwrap(
        client.GET("/api/v1/organizations/{organization_id}/companies/{company_id}/branches", {
          params: {
            path: { organization_id: organizationId!, company_id: companyId! },
            query: SELECTOR_PAGE,
          },
        }),
      ),
    enabled: !!organizationId && !!companyId,
  });
}

export function useLoginMutation() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (credentials: { email: string; password: string }) =>
      unwrap(client.POST("/api/v1/auth/login", { body: credentials })),
    // El error (credenciales inválidas, límite de intentos) lo muestra el propio formulario: sin aviso global.
    meta: { silent: true },
    // El middleware ya guardó el token CSRF; aquí la sesión entra a la caché para que el panel no la pida de nuevo.
    onSuccess: (session) => queryClient.setQueryData(queryKeys.session, session),
  });
}

/** Cierra la sesión de este navegador y olvida TODO lo cacheado (otra persona puede usar el equipo después). */
export function useLogoutMutation() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async () => {
      const result = await client.DELETE("/api/v1/auth/logout", {
        params: { header: { "X-CSRF-Token": CSRF_PLACEHOLDER } },
      });
      if (result.error !== undefined) await unwrap(Promise.resolve(result));
    },
    onSuccess: () => queryClient.clear(),
  });
}

export function useLogoutAllMutation() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async () => {
      const result = await client.DELETE("/api/v1/auth/sessions", {
        params: { header: { "X-CSRF-Token": CSRF_PLACEHOLDER } },
      });
      if (result.error !== undefined) await unwrap(Promise.resolve(result));
    },
    onSuccess: () => queryClient.clear(),
  });
}
