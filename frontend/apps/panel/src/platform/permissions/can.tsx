import { useCallback, type ReactNode } from "react";
import { useMe } from "../me/me-provider";

/** Predicate over the /me permissions. It only MIRRORS them: the backend decides. */
export function useCan(): (permission: string) => boolean {
  const { permissions } = useMe();
  return useCallback((permission) => permissions.includes(permission), [permissions]);
}

type CanProps = { fallback?: ReactNode; children: ReactNode } & (
  { permission: string; any?: never } | { any: string[]; permission?: never }
);

/**
 * Renders `children` only if the user has the permission (or any of `any`). Hiding a button is NOT access control: the
 * API validates every action again.
 *
 *   <Can permission="appointments.appointment.create"><NewAppointmentButton /></Can>
 */
export function Can({ permission, any, fallback = null, children }: CanProps) {
  const can = useCan();
  const allowed = permission !== undefined ? can(permission) : (any ?? []).some(can);
  return <>{allowed ? children : fallback}</>;
}
