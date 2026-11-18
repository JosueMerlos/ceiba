import { unwrap, useApiClient } from "@ceiba/api-client";
import { useMutation, useQuery } from "@tanstack/react-query";
import { agendaKeys } from "./agenda";
import { CSRF, useCatalogScope } from "./shared";

const CUSTOMERS =
  "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/customers";
const RESULTS = 10;
const MIN_TERM = 2;
const PHONE_LIKE = /^[\d\s()+-]+$/;

export function useCustomerSearch(branchId: string, term: string) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  const query = term.trim();
  const filter = PHONE_LIKE.test(query) ? { phone: query } : { name_prefix: query };
  return useQuery({
    queryKey: agendaKeys.customers(organizationId, companyId, branchId, query),
    queryFn: () =>
      unwrap(
        client.GET(CUSTOMERS, {
          params: { path: { ...path, branch_id: branchId }, query: { ...filter, limit: RESULTS } },
        }),
      ),
    enabled: query.length >= MIN_TERM,
    throwOnError: false,
  });
}

// Silent: the form shows the failure next to its fields.
export function useCreateCustomer(branchId: string) {
  const client = useApiClient();
  const { path } = useCatalogScope();
  return useMutation({
    mutationFn: (body: { full_name: string; phone_e164: string }) =>
      unwrap(
        client.POST(CUSTOMERS, {
          params: { path: { ...path, branch_id: branchId }, header: CSRF },
          body,
        }),
      ),
    meta: { silent: true },
  });
}
