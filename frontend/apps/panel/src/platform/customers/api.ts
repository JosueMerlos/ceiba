import { unwrap, useApiClient, type components } from "@ceiba/api-client";
import {
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
  type InfiniteData,
} from "@tanstack/react-query";
import { useMe } from "../me/me-provider";

type Schemas = components["schemas"];
export type Customer = Schemas["Customer"];
export type CustomerInput = Schemas["CustomerInput"];
export type CustomerPatch = Schemas["CustomerPatch"];
export type CustomerAppointment = Schemas["CustomerAppointment"];

const CUSTOMERS =
  "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/customers";
const CUSTOMER = `${CUSTOMERS}/{id}` as const;
const HISTORY =
  "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/customers/{customer_id}/appointments";
// The contract declares X-CSRF-Token as required; the client middleware replaces this with the real token.
const CSRF = { "X-CSRF-Token": "" };
const PAGE_SIZE = 50;
const PHONE_LIKE = /^[\d\s()+-]+$/;

/** Customers belong to the company; the route carries the branch the staff acts from. */
export function useCustomerScope(branchId: string) {
  const { context } = useMe();
  if (!context.organization || !context.company) {
    throw new Error("Los clientes necesitan una organización y una empresa en el contexto");
  }
  return {
    organizationId: context.organization.id,
    companyId: context.company.id,
    path: {
      organization_id: context.organization.id,
      company_id: context.company.id,
      branch_id: branchId,
    },
  };
}

export const customerKeys = {
  all: (companyId: string) => ["customers", companyId] as const,
  list: (companyId: string, branchId: string, term: string) =>
    [...customerKeys.all(companyId), "list", branchId, term] as const,
  one: (companyId: string, id: string) => [...customerKeys.all(companyId), "one", id] as const,
  history: (companyId: string, branchId: string, id: string) =>
    [...customerKeys.all(companyId), "history", branchId, id] as const,
};

/** Digits (and phone punctuation) search by phone; anything else by the start of the name. */
export const searchFilter = (term: string) =>
  term === "" ? {} : PHONE_LIKE.test(term) ? { phone: term } : { name_prefix: term };

export function useCustomersQuery(branchId: string, term: string) {
  const client = useApiClient();
  const { companyId, path } = useCustomerScope(branchId);
  return useInfiniteQuery({
    queryKey: customerKeys.list(companyId, branchId, term),
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      unwrap(
        client.GET(CUSTOMERS, {
          params: {
            path,
            query: {
              ...searchFilter(term),
              limit: PAGE_SIZE,
              ...(pageParam ? { after: pageParam } : {}),
            },
          },
        }),
      ),
    getNextPageParam: (last) =>
      last.page.has_more ? (last.page.next_cursor ?? undefined) : undefined,
  });
}

export function useCustomerQuery(branchId: string, id: string) {
  const client = useApiClient();
  const { companyId, path } = useCustomerScope(branchId);
  return useQuery({
    queryKey: customerKeys.one(companyId, id),
    queryFn: () => unwrap(client.GET(CUSTOMER, { params: { path: { ...path, id } } })),
  });
}

export function useCustomerHistory(branchId: string, customerId: string, enabled: boolean) {
  const client = useApiClient();
  const { companyId, path } = useCustomerScope(branchId);
  return useInfiniteQuery({
    queryKey: customerKeys.history(companyId, branchId, customerId),
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      unwrap(
        client.GET(HISTORY, {
          params: {
            path: { ...path, customer_id: customerId },
            query: { limit: PAGE_SIZE, ...(pageParam ? { after: pageParam } : {}) },
          },
        }),
      ),
    getNextPageParam: (last) =>
      last.page.has_more ? (last.page.next_cursor ?? undefined) : undefined,
    enabled,
  });
}

export const flattenPages = <T>(data: InfiniteData<{ data: T[] }> | undefined): T[] =>
  data?.pages.flatMap((page) => page.data) ?? [];

// Silent: the form shows a failure next to its fields.
export function useCreateCustomer(branchId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { companyId, path } = useCustomerScope(branchId);
  return useMutation({
    mutationFn: (body: CustomerInput) =>
      unwrap(client.POST(CUSTOMERS, { params: { path, header: CSRF }, body })),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: customerKeys.all(companyId) }),
    meta: { silent: true },
  });
}

export function useUpdateCustomer(branchId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { companyId, path } = useCustomerScope(branchId);
  return useMutation({
    mutationFn: ({ id, body }: { id: string; body: CustomerPatch }) =>
      unwrap(client.PATCH(CUSTOMER, { params: { path: { ...path, id }, header: CSRF }, body })),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: customerKeys.all(companyId) }),
    meta: { silent: true },
  });
}
