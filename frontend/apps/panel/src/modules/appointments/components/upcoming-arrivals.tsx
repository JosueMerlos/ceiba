import { formatTime, useTranslation } from "@ceiba/i18n";
import { Button } from "@ceiba/ui";
import { initials } from "../../../platform/shell/initials";
import type { AgendaAppointment } from "../api/agenda";
import { useStatusAction } from "../api/agenda-mutations";
import { appointmentActions } from "../lib/agenda-actions";
import { useAgendaPermissions } from "../lib/agenda-permissions";
import { STATUS_TONE, type StatusTone } from "../lib/agenda-status";
import { AgendaSidePanel } from "./agenda/agenda-side-panel";

const TONE_TAG: Record<StatusTone, string> = {
  pending: "bg-[var(--appointment-pending-bg)] text-[var(--appointment-pending-fg)]",
  confirmed: "bg-accent text-accent-foreground",
  arrived: "bg-[var(--appointment-arrived-bg)] text-[var(--appointment-arrived-fg)]",
  done: "bg-[var(--appointment-done-bg)] text-[var(--appointment-done-fg)]",
  missed: "bg-[var(--appointment-missed-bg)] text-[var(--appointment-missed-fg)]",
};

/** The one thing to do with someone about to arrive: confirm them, or mark that they are here. */
function ArrivalAction({
  branchId,
  appointment,
}: {
  branchId: string;
  appointment: AgendaAppointment;
}) {
  const { t } = useTranslation("appointments");
  const { appointment: permissions } = useAgendaPermissions();
  const statusAction = useStatusAction(branchId);
  const action = appointmentActions(appointment, permissions, new Date()).status[0];
  if (!action) return null;
  return (
    <Button
      type="button"
      variant="outline"
      size="sm"
      loading={statusAction.isPending}
      onClick={() => statusAction.mutate({ id: appointment.id, action })}
    >
      {t(`agenda.actions.${action}`)}
    </Button>
  );
}

interface UpcomingArrivalsProps {
  id: string;
  branchId: string;
  arrivals: readonly AgendaAppointment[];
  timeZone: string;
  professionalName(id: string): string;
  serviceLabel(appointment: AgendaAppointment): string;
  onClose(): void;
}

/** Who is expected in the next hour, next to the agenda and without covering it. */
export function UpcomingArrivals({
  id,
  branchId,
  arrivals,
  timeZone,
  professionalName,
  serviceLabel,
  onClose,
}: UpcomingArrivalsProps) {
  const { t } = useTranslation("appointments");
  return (
    <AgendaSidePanel
      id={id}
      onClose={onClose}
      title={t("agenda.upcoming.title")}
      closeLabel={t("agenda.upcoming.close")}
    >
      <p className="text-sm text-muted-foreground">{t("agenda.upcoming.hint")}</p>
      {arrivals.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("agenda.upcoming.none")}</p>
      ) : (
        <ul className="grid gap-3">
          {arrivals.map((arrival) => {
            const professional = professionalName(arrival.professional_id);
            return (
              <li key={arrival.id} className="grid gap-2.5 rounded-xl border p-3.5">
                <div className="flex items-center gap-2">
                  <span className="flex-1 font-display text-xl font-bold">
                    {formatTime(arrival.starts_at, timeZone)}
                  </span>
                  <span
                    className={`rounded-full px-2 py-0.5 text-xs ${TONE_TAG[STATUS_TONE[arrival.status]]}`}
                  >
                    {t(`agenda.status.${arrival.status}`)}
                  </span>
                </div>
                <div className="flex items-center gap-2.5">
                  <span
                    className="grid size-8 shrink-0 place-items-center rounded-full bg-sidebar text-[0.6875rem] font-bold text-muted-foreground"
                    aria-hidden="true"
                  >
                    {initials(professional)}
                  </span>
                  <span className="grid min-w-0 gap-0.5">
                    <span className="truncate font-semibold">
                      {arrival.customer_name ?? t("agenda.customerFallback")}
                    </span>
                    <span className="text-[0.8125rem] text-muted-foreground">
                      {t("agenda.upcoming.withProfessional", {
                        service: serviceLabel(arrival),
                        professional,
                      })}
                    </span>
                  </span>
                </div>
                <ArrivalAction branchId={branchId} appointment={arrival} />
              </li>
            );
          })}
        </ul>
      )}
    </AgendaSidePanel>
  );
}
