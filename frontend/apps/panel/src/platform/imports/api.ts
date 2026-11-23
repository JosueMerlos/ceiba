import { unwrap, useApiClient, type components } from "@ceiba/api-client";
import { useInfiniteQuery, useMutation, useQuery } from "@tanstack/react-query";
import { useBranchScope } from "../context/use-branch-scope";
import type { ImportKind } from "./kinds";

type Schemas = components["schemas"];
export type ImportBatch = Schemas["ImportBatch"];
export type ImportRow = Schemas["ImportRow"];
export type DuplicateMode = ImportBatch["duplicate_modes"][number];

const IMPORTS =
  "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/imports";
const IMPORT = `${IMPORTS}/{import_id}` as const;
// The contract declares X-CSRF-Token as required; the client middleware replaces this with the real token.
const CSRF = { "X-CSRF-Token": "" };
const POLL_MS = 1000;
const ROWS_PAGE = 100;
export const RUNNING: readonly ImportBatch["status"][] = ["queued", "processing"];

// Silent: the page shows a refused file in place.
export function useUploadImport(branchId: string) {
  const client = useApiClient();
  const { path } = useBranchScope(branchId);
  return useMutation({
    mutationFn: (body: { kind: ImportKind; content_base64: string }) =>
      unwrap(client.POST(IMPORTS, { params: { path, header: CSRF }, body })),
    meta: { silent: true },
  });
}

export function useConfirmImport(branchId: string) {
  const client = useApiClient();
  const { path } = useBranchScope(branchId);
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
  const { path } = useBranchScope(branchId);
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

/** A batch's rows in one state (rejected in the preview, failed in the report), page by page: numbers and codes only. */
export function useBatchRows(
  branchId: string,
  batch: ImportBatch,
  status: "rejected" | "failed",
  enabled: boolean,
) {
  const client = useApiClient();
  const { path } = useBranchScope(branchId);
  return useInfiniteQuery({
    queryKey: ["imports", path.company_id, batch.id, status],
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      unwrap(
        client.GET(`${IMPORT}/rows`, {
          params: {
            path: { ...path, import_id: batch.id },
            query: { status, limit: ROWS_PAGE, ...(pageParam ? { after: pageParam } : {}) },
          },
        }),
      ),
    getNextPageParam: (last) =>
      last.page.has_more ? (last.page.next_cursor ?? undefined) : undefined,
    enabled,
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
