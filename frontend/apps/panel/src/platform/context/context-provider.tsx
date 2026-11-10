import type { MeContext } from "@ceiba/api-client";
import { useQueryClient } from "@tanstack/react-query";
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";

interface ContextSelectionValue {
  /** What is requested from /me. Empty = the last used context (server cookie) or the first available. */
  selection: MeContext;
  /** Switches context: discards ALL cached data (except the session) and requests /me again. */
  switchContext(next: MeContext): void;
}

const ContextSelection = createContext<ContextSelectionValue | null>(null);

export function ContextProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [selection, setSelection] = useState<MeContext>({});

  const switchContext = useCallback(
    (next: MeContext) => {
      // `removeQueries` (not `invalidateQueries`): invalidating would show the previous organization's data while the
      // new data loads. Here the old data disappears immediately.
      queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== "session" });
      setSelection(next);
    },
    [queryClient],
  );

  const value = useMemo(() => ({ selection, switchContext }), [selection, switchContext]);
  return <ContextSelection.Provider value={value}>{children}</ContextSelection.Provider>;
}

export function useContextSelection(): ContextSelectionValue {
  const value = useContext(ContextSelection);
  if (!value) throw new Error("useContextSelection debe usarse dentro de <ContextProvider>");
  return value;
}
