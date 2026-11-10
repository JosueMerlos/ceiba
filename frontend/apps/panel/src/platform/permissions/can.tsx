import { useCallback, type ReactNode } from "react";
import { useMe } from "../me/me-provider";

/** Predicado sobre los permisos de /me. Solo REFLEJA: el backend es quien decide (05-module-system). */
export function useCan(): (permission: string) => boolean {
  const { permissions } = useMe();
  return useCallback((permission) => permissions.includes(permission), [permissions]);
}

type CanProps = { fallback?: ReactNode; children: ReactNode } & (
  { permission: string; any?: never } | { any: string[]; permission?: never }
);

/**
 * Muestra `children` solo si el usuario tiene el permiso (o alguno de `any`). Ocultar un botón NO es control de acceso:
 * la API vuelve a validar cada acción.
 *
 *   <Can permission="appointments.appointment.create"><NewAppointmentButton /></Can>
 */
export function Can({ permission, any, fallback = null, children }: CanProps) {
  const can = useCan();
  const allowed = permission !== undefined ? can(permission) : (any ?? []).some(can);
  return <>{allowed ? children : fallback}</>;
}
