import type { AgendaSlot } from "../components/agenda-view/types";
import type { AgendaMode } from "./agenda-lens";

/**
 * Who a new appointment starts with: the professional whose column was clicked, or whose week is on screen, provided they
 * can be booked; otherwise the first one who can. The key changes with that origin, so a click in another column at the
 * same hour opens a fresh form instead of keeping the previous choice.
 */
export function newAppointmentDefaults({
  mode,
  slot,
  weekProfessionalId,
  professionals,
}: {
  mode: AgendaMode;
  slot: AgendaSlot | null;
  weekProfessionalId: string | null;
  professionals: readonly { id: string }[];
}) {
  const bookable = (id: string | null | undefined) =>
    id && professionals.some((person) => person.id === id) ? id : null;
  const fromOrigin =
    mode === "professionals"
      ? bookable(slot?.resourceId)
      : mode === "week"
        ? bookable(weekProfessionalId)
        : null;
  return {
    professionalId: fromOrigin ?? professionals[0]?.id ?? null,
    key: [mode, slot?.startsAt ?? "button", slot?.resourceId ?? "", fromOrigin ?? ""].join("|"),
  };
}
