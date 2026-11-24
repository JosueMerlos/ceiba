import { useTranslation } from "@ceiba/i18n";
import { LoadingState } from "@ceiba/ui";
import type { UseQueryResult } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { QueryError } from "./query-error";

interface QueryBoundaryProps<T> {
  query: UseQueryResult<T>;
  /** When it returns true the `empty` node replaces the content. */
  isEmpty?(data: T): boolean;
  empty?: ReactNode;
  children(data: T): ReactNode;
}

/** The four states of a list query (loading, failed with retry, empty, content) in one place. */
export function QueryBoundary<T>({ query, isEmpty, empty, children }: QueryBoundaryProps<T>) {
  const { t } = useTranslation("common");

  if (query.isPending) return <LoadingState label={t("loading")} />;
  if (query.isError) return <QueryError error={query.error} onRetry={() => void query.refetch()} />;
  if (isEmpty?.(query.data)) return empty ?? null;
  return children(query.data);
}
