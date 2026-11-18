import { useTranslation } from "@ceiba/i18n";
import { Button, toast } from "@ceiba/ui";
import { useCallback, useMemo, useState } from "react";
import { validationMessage } from "../../../../platform/forms/api-error-messages";
import type { AgendaAppointment, AgendaProfessional } from "../../api/agenda";
import { useRescheduleAppointment } from "../../api/agenda-mutations";
import type { Branch } from "../../api/catalog";
import { nearbyOwnStarts } from "../../lib/agenda-actions";
import { dayInZone, type PlainDate } from "../../lib/agenda-time";
import { createIdempotencyKeys } from "../../lib/idempotency-keys";
import { FormAlert } from "../form-alert";
import { DayAndTimeFields, ProfessionalField, useSlotSelection } from "./slot-fields";

interface RescheduleFormProps {
  branch: Branch;
  appointment: AgendaAppointment;
  professionals: readonly AgendaProfessional[];
  stepMinutes: number;
  onBack(): void;
  onDone(): void;
}

export function RescheduleForm({
  branch,
  appointment,
  professionals,
  stepMinutes,
  onBack,
  onDone,
}: RescheduleFormProps) {
  const { t } = useTranslation("appointments");
  const timeZone = branch.time_zone;
  const [keys] = useState(() => createIdempotencyKeys());
  const move = useRescheduleAppointment(branch.id);
  const serviceIds = useMemo(
    () => appointment.services.map((line) => line.service_id),
    [appointment.services],
  );
  const ownStarts = useCallback(
    (professionalId: string | null, day: PlainDate) =>
      professionalId === appointment.professional_id
        ? nearbyOwnStarts(appointment, stepMinutes).filter(
            (start) => dayInZone(start, timeZone) === day,
          )
        : [],
    [appointment, stepMinutes, timeZone],
  );
  const selection = useSlotSelection({
    branchId: branch.id,
    serviceIds,
    initial: {
      professionalId: appointment.professional_id,
      day: dayInZone(appointment.starts_at, timeZone),
    },
    extraStarts: ownStarts,
  });
  const invalid = validationMessage(move.error, t);

  function submit() {
    if (!selection.startsAt || !selection.professionalId) return;
    const body = { starts_at: selection.startsAt, professional_id: selection.professionalId };
    move.mutate(
      { id: appointment.id, key: keys.keyFor(body), body },
      {
        onSuccess: () => {
          keys.settle();
          toast.success(t("agenda.detail.moved"));
          onDone();
        },
      },
    );
  }

  return (
    <div className="grid gap-3">
      <ProfessionalField selection={selection} professionals={professionals} />
      <DayAndTimeFields
        selection={selection}
        timeZone={timeZone}
        dayLabel={t("agenda.detail.newDate")}
      />
      {invalid ? <FormAlert>{invalid}</FormAlert> : null}
      <Button
        type="button"
        disabled={!selection.startsAt}
        loading={move.isPending}
        onClick={submit}
      >
        {t("agenda.detail.move")}
      </Button>
      <Button type="button" variant="ghost" onClick={onBack}>
        {t("agenda.detail.back")}
      </Button>
    </div>
  );
}
