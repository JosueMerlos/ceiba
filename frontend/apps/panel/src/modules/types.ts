import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";

export interface ModuleRoute {
  /** Relativa a la raíz del panel, sin barra inicial ("agenda", "agenda/summary"). */
  path: string;
  /** Permiso que el usuario debe tener (en /me) para que la ruta exista. */
  permission: string;
  element: ReactNode;
}

export interface ModuleNavigation {
  /** Coincide con `navigation[].key` de /me. */
  key: string;
  path: string;
  /** Clave del namespace `shell` de i18n. */
  labelKey: "nav.agenda" | "nav.summary";
  permission: string;
  icon: LucideIcon;
}

/** Manifiesto del front de un módulo: el equivalente al `Modules.define` del backend. */
export interface ModuleManifest {
  key: string;
  routes: ModuleRoute[];
  navigation: ModuleNavigation[];
}
