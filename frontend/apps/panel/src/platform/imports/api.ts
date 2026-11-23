import { unwrap, useApiClient, type components } from "@ceiba/api-client";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useMe } from "../me/me-provider";
import type { ImportKind } from "./kinds";

type Schemas = components["schemas"];
export type ImportBatch = Schemas["ImportBatch"];
export type ImportRow = Schemas["ImportRow"];
export type DuplicateMode = "skip" | "update";

const IMPORTS =
  "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/imports";
const IMPORT = `${IMPORTS}/{import_id}` as const;
// The contract declares X-CSRF-Token as required; the client middleware replaces this with the real token.
const CSRF = { "X-CSRF-Token": "" };
const POLL_MS = 1000;
const ROWS_PAGE = 100;
export const RUNNING: readonly ImportBatch["status"][] = ["queued", "processing"];

function useImportScope(branchId: string) {
  const { context } = useMe();
  if (!context.organization || !context.company) {
    throw new Error("Importar necesita una organización y una empresa en el contexto");
  }
  return {
    organization_id: context.organization.id,
    company_id: context.company.id,
    branch_id: branchId,
  };
}

// Silent: the page shows a refused file in place.
export function useUploadImport(branchId: string) {
  const client = useApiClient();
  const path = useImportScope(branchId);
  return useMutation({
    mutationFn: (body: { kind: ImportKind; content_base64: string }) =>
      unwrap(client.POST(IMPORTS, { params: { path, header: CSRF }, body })),
    meta: { silent: true },
  });
}

export function useConfirmImport(branchId: string) {
  const client = useApiClient();
  const path = useImportScope(branchId);
  return useMutation({
    mutationFn: ({ id, mode }: { id: string; mode: DuplicateMode }) =>
      unwrap(
        client.POST(`${IMPORT}/confirm`, {
          params: { path: { ...path, import_id: id }, header: CSRF },
          body: { duplicate_mode: mode },
        }),
      ),
  });
}

/** Follows a confirmed batch until the job finishes. */
export function useImportProgress(branchId: string, batch: ImportBatch | null) {
  const client = useApiClient();
  const path = useImportScope(branchId);
  const running = batch !== null && RUNNING.includes(batch.status);
  return useQuery({
    queryKey: ["imports", path.company_id, batch?.id],
    queryFn: () =>
      unwrap(client.GET(IMPORT, { params: { path: { ...path, import_id: batch!.id } } })),
    enabled: running,
    refetchInterval: (query) =>
      query.state.data && !RUNNING.includes(query.state.data.data.status) ? false : POLL_MS,
  });
}

/** The rejected rows of a preview: row numbers and codes only, for the error list. */
export function useRejectedRows(branchId: string, batch: ImportBatch | null) {
  const client = useApiClient();
  const path = useImportScope(branchId);
  return useQuery({
    queryKey: ["imports", path.company_id, batch?.id, "rejected"],
    queryFn: () =>
      unwrap(
        client.GET(`${IMPORT}/rows`, {
          params: {
            path: { ...path, import_id: batch!.id },
            query: { status: "rejected", limit: ROWS_PAGE },
          },
        }),
      ),
    enabled: batch !== null && batch.rejected_count > 0,
  });
}

/** The file's bytes as base64 (the JSON body cannot carry raw bytes). */
export function readAsBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).replace(/^data:[^,]*,/, ""));
    reader.onerror = () => reject(reader.error ?? new Error("No se pudo leer el archivo"));
    reader.readAsDataURL(file);
  });
}
