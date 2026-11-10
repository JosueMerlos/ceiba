import type { MeContext } from "@ceiba/api-client";
import { useQueryClient } from "@tanstack/react-query";
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";

interface ContextSelectionValue {
  /** Lo que se le pide a /me. Vacío = el último contexto usado (cookie del servidor) o el primero disponible. */
  selection: MeContext;
  /** Cambia de contexto: descarta TODA la caché de datos (menos la sesión) y vuelve a pedir /me. */
  switchContext(next: MeContext): void;
}

const ContextSelection = createContext<ContextSelectionValue | null>(null);

export function ContextProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [selection, setSelection] = useState<MeContext>({});

  const switchContext = useCallback(
    (next: MeContext) => {
      // `removeQueries` (no `invalidateQueries`): invalidar mostraría los datos de la organización anterior mientras
      // llegan los nuevos. Aquí el dato viejo desaparece de inmediato (criterio 2).
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
