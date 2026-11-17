import type { Me } from "../platform/me/me-provider";
import { appointments } from "./appointments";
import type { ModuleManifest, ModuleNavigation, ModuleRoute } from "./types";

/** Every module THIS front end can render (statically imported; their pages are not: they are lazy). */
export const modules: ModuleManifest[] = [appointments];

export function activeModules(me: Me): ModuleManifest[] {
  const active = new Set(me.modules.map((module) => module.key));
  return modules.filter((module) => active.has(module.key));
}

const hasAny = (me: Me, permissions: readonly string[]) =>
  permissions.some((permission) => me.permissions.includes(permission));

/** Routes of active modules the user has permission for: what /me does not offer is not mounted. */
export function routesFor(me: Me): ModuleRoute[] {
  return activeModules(me)
    .flatMap((module) => module.routes)
    .filter((route) => hasAny(me, route.permissions));
}

/** Menu items: from active modules, with the user's permission AND offered by /me navigation. */
export function navigationFor(me: Me): (ModuleNavigation & { module: string })[] {
  return activeModules(me).flatMap((module) =>
    module.navigation
      .filter(
        (item) =>
          hasAny(me, item.permissions) &&
          me.navigation.some(
            (offered) => offered.module === module.key && offered.key === item.key,
          ),
      )
      .map((item) => ({ ...item, module: module.key })),
  );
}
