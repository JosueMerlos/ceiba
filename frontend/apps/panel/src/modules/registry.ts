import type { Me } from "../platform/me/me-provider";
import { appointments } from "./appointments";
import type { ModuleManifest, ModuleNavigation, ModuleRoute } from "./types";

/** Todos los módulos que ESTE front sabe pintar (importados estáticamente; sus páginas, no: son lazy). */
export const modules: ModuleManifest[] = [appointments];

/** Los módulos que /me reporta activos y que este front conoce. */
export function activeModules(me: Me): ModuleManifest[] {
  const active = new Set(me.modules.map((module) => module.key));
  return modules.filter((module) => active.has(module.key));
}

/** Rutas de los módulos activos cuyo permiso tiene el usuario: lo que /me no ofrece, no se monta. */
export function routesFor(me: Me): ModuleRoute[] {
  return activeModules(me)
    .flatMap((module) => module.routes)
    .filter((route) => me.permissions.includes(route.permission));
}

/** Ítems de menú: de módulos activos, con el permiso del usuario Y ofrecidos por la navegación de /me. */
export function navigationFor(me: Me): (ModuleNavigation & { module: string })[] {
  return activeModules(me).flatMap((module) =>
    module.navigation
      .filter(
        (item) =>
          me.permissions.includes(item.permission) &&
          me.navigation.some(
            (offered) => offered.module === module.key && offered.key === item.key,
          ),
      )
      .map((item) => ({ ...item, module: module.key })),
  );
}
