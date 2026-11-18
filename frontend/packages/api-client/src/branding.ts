import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { unwrap, type ApiClient } from "./client";
import { queryKeys, useApiClient } from "./query";
import type { components } from "./schema";

export type Branding = components["schemas"]["Branding"];
/** The image kinds of a brand: whatever the contract publishes under `assets`. */
export type BrandingFile = keyof Branding["assets"];

const TEXT_FIELDS = [
  "brand_name",
  "tagline",
  "primary_color",
  "secondary_color",
  "accent_color",
  "font_choice",
] as const;

/** What the edit screen sends. A text field sent empty returns to the platform default; absent files stay as they are. */
export interface BrandingChanges {
  text: Record<(typeof TEXT_FIELDS)[number], string>;
  files: Partial<Record<BrandingFile, File>>;
  remove: BrandingFile[];
}

/** multipart/form-data body of PATCH .../branding (the generated type models files as strings, so it is built by hand). */
export function toBrandingFormData({ text, files, remove }: BrandingChanges): FormData {
  const form = new FormData();
  for (const field of TEXT_FIELDS) form.append(field, text[field]);
  for (const [name, file] of Object.entries(files)) form.append(name, file);
  for (const name of remove) form.append("remove[]", name);
  return form;
}

// The contract declares X-CSRF-Token as a required parameter; the client middleware replaces it with the real token.
const CSRF_PLACEHOLDER = "";

/** Public brand by slug: the same endpoint the booking page uses, so both share one cached answer. */
export function usePublicBrandingQuery(slug: string | undefined) {
  const client = useApiClient();
  return useQuery({
    queryKey: queryKeys.publicBranding(slug ?? ""),
    queryFn: () =>
      unwrap(client.GET("/api/public/v1/c/{slug}/branding", { params: { path: { slug: slug! } } })),
    enabled: !!slug,
    // A company without a readable brand simply uses the platform palette: it must not reach the error boundary.
    retry: false,
    throwOnError: false,
  });
}

export function useBrandingQuery(
  organizationId: string | undefined,
  companyId: string | undefined,
  { enabled = true }: { enabled?: boolean } = {},
) {
  const client = useApiClient();
  return useQuery({
    queryKey: queryKeys.branding(companyId ?? ""),
    queryFn: () =>
      unwrap(
        client.GET("/api/v1/organizations/{organization_id}/companies/{company_id}/branding", {
          params: { path: { organization_id: organizationId!, company_id: companyId! } },
        }),
      ),
    enabled: enabled && !!organizationId && !!companyId,
  });
}

interface BrandingTarget {
  organizationId: string;
  companyId: string;
  slug: string;
}

/** PATCH of the brand as multipart/form-data. Rejects with ApiError (422 carries the per-field `errors`). */
export function updateBranding(
  client: ApiClient,
  { organizationId, companyId }: Pick<BrandingTarget, "organizationId" | "companyId">,
  changes: BrandingChanges,
) {
  return unwrap(
    client.PATCH("/api/v1/organizations/{organization_id}/companies/{company_id}/branding", {
      params: {
        header: { "X-CSRF-Token": CSRF_PLACEHOLDER },
        path: { organization_id: organizationId, company_id: companyId },
      },
      // Every field is optional and the serializer ignores `body`: the real payload is the FormData.
      body: {},
      bodySerializer: () => toBrandingFormData(changes),
    }),
  );
}

export function useUpdateBrandingMutation(target: BrandingTarget) {
  const { companyId, slug } = target;
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (changes: BrandingChanges) => updateBranding(client, target, changes),
    onSuccess: (saved) => {
      // The panel's own theme (public query) and this screen's form read these two: both show the saved brand at once.
      queryClient.setQueryData(queryKeys.branding(companyId), saved);
      queryClient.setQueryData(queryKeys.publicBranding(slug), saved);
    },
  });
}
