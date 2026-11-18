import { useTranslation } from "@ceiba/i18n";
import { toast } from "@ceiba/ui";
import { validationMessage } from "../../../platform/forms/api-error-messages";
import { useRescheduleAppointment } from "../api/agenda-mutations";
import type { AgendaSlot } from "../components/agenda-view/types";

/** Moves an appointment dragged on the calendar. Resolves false when refused, so the card goes back to its place. */
export function useMoveAppointment(
  branchId: string,
  { changesProfessional }: { changesProfessional: boolean },
) {
  const { t } = useTranslation("appointments");
  const reschedule = useRescheduleAppointment(branchId);

  return async function move(id: string, to: AgendaSlot) {
    try {
      await reschedule.mutateAsync({
        id,
        key: crypto.randomUUID(),
        body: {
          starts_at: to.startsAt,
          ...(changesProfessional && to.resourceId ? { professional_id: to.resourceId } : {}),
        },
      });
      toast.success(t("agenda.detail.moved"));
      return true;
    } catch (error) {
      // A drag has no form: this is the only place to show a 422. Anything else the global handler already announced.
      const invalid = validationMessage(error, t);
      if (invalid) toast.error(invalid);
      return false;
    }
  };
}
