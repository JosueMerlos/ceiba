import { useTranslation } from "@ceiba/i18n";
import { LEGEND_STATUSES, STATUS_TONE, type StatusTone } from "../lib/agenda-status";

export const TONE_DOT: Record<StatusTone, string> = {
  pending: "bg-[var(--appointment-pending-dot)]",
  confirmed: "bg-[var(--appointment-confirmed-dot)]",
  arrived: "bg-[var(--appointment-arrived-dot)]",
  done: "bg-[var(--appointment-done-dot)]",
  missed: "bg-[var(--appointment-missed-dot)]",
};

export function AgendaLegend() {
  const { t } = useTranslation("appointments");
  return (
    <ul className="mt-4 flex flex-wrap gap-x-5 gap-y-1.5 text-xs text-muted-foreground">
      {LEGEND_STATUSES.map((status) => (
        <li key={status} className="flex items-center gap-1.5">
          <span
            className={`size-2 rounded-full ${TONE_DOT[STATUS_TONE[status]]}`}
            aria-hidden="true"
          />
          {t(`agenda.status.${status}`)}
        </li>
      ))}
      <li className="flex items-center gap-1.5">
        <span className="h-0.5 w-3.5 bg-destructive" aria-hidden="true" />
        {t("agenda.currentTime")}
      </li>
    </ul>
  );
}
