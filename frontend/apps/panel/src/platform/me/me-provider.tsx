import type { components } from "@ceiba/api-client";
import { createContext, useContext, type ReactNode } from "react";

/** Lo que devuelve GET /api/v1/me: contexto, módulos activos, permisos y navegación. Es la ÚNICA fuente de la UI. */
export type Me = components["schemas"]["Me"]["data"];

const MeContext = createContext<Me | null>(null);

export function MeProvider({ me, children }: { me: Me; children: ReactNode }) {
  return <MeContext.Provider value={me}>{children}</MeContext.Provider>;
}

export function useMe(): Me {
  const me = useContext(MeContext);
  if (!me) throw new Error("useMe debe usarse dentro de <MeProvider>");
  return me;
}
