import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";

export interface ModuleRoute {
  /** Relative to the panel root, no leading slash ("agenda", "agenda/summary"). */
  path: string;
  /** Permission the user must have (in /me) for the route to exist. */
  permission: string;
  element: ReactNode;
}

export interface ModuleNavigation {
  /** Matches `navigation[].key` from /me. */
  key: string;
  path: string;
  /** Key in the i18n `shell` namespace. */
  labelKey: "nav.agenda" | "nav.summary";
  permission: string;
  icon: LucideIcon;
}

/** Front-end manifest of a module: the counterpart of the backend's `Modules.define`. */
export interface ModuleManifest {
  key: string;
  routes: ModuleRoute[];
  navigation: ModuleNavigation[];
}
