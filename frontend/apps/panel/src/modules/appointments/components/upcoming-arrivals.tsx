import { formatTime, useTranslation } from "@ceiba/i18n";
import { ContextPanel } from "@ceiba/ui";
import type { ReactNode } from "react";
import { AsidePortal } from "../../../platform/shell/aside-slot";
import { initials } from "../../../platform/shell/initials";
import type { AgendaAppointment } from "../api/agenda";
import { STATUS_TONE, type StatusTone } from "../lib/agenda-status";

const TONE_TAG: Record<StatusTone, string> = {
  pending: "bg-[var(--appointment-pending-bg)] text-[var(--appointment-pending-fg)]",
  confirmed: "bg-accent text-accent-foreground",
  arrived: "bg-[var(--appointment-arrived-bg)] text-[var(--appointment-arrived-fg)]",
  done: "bg-[var(--appointment-done-bg)] text-[var(--appointment-done-fg)]",
  missed: "bg-[var(--appointment-missed-bg)] text-[var(--appointment-missed-fg)]",
};

interface UpcomingArrivalsProps {
  id: string;
  arrivals: readonly AgendaAppointment[];
  timeZone: string;
  professionalName(id: string): string;
  serviceLabel(appointment: AgendaAppointment): string;
  onClose(): void;
  /** The direct action of each arrival. */
  renderAction?(appointment: AgendaAppointment): ReactNode;
}

/** Who is expected in the next hour, next to the agenda and without covering it. */
export function UpcomingArrivals({
  id,
  arrivals,
  timeZone,
  professionalName,
  serviceLabel,
  onClose,
  renderAction,
}: UpcomingArrivalsProps) {
  const { t } = useTranslation("appointments");
  return (
    <AsidePortal>
      <ContextPanel
        id={id}
        open
        onOpenChange={(open) => {
          if (!open) onClose();
        }}
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
                  {renderAction?.(arrival)}
                </li>
              );
            })}
          </ul>
        )}
      </ContextPanel>
    </AsidePortal>
  );
}
