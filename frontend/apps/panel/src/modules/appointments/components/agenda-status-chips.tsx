import { useTranslation } from "@ceiba/i18n";
import { cn } from "@ceiba/ui";
import type { AppointmentStatus, StatusTone } from "../lib/agenda-status";

export const TONE_DOT: Record<StatusTone, string> = {
  pending: "bg-[var(--appointment-pending-dot)]",
  confirmed: "bg-[var(--appointment-confirmed-dot)]",
  arrived: "bg-[var(--appointment-arrived-dot)]",
  done: "bg-[var(--appointment-done-dot)]",
  missed: "bg-[var(--appointment-missed-dot)]",
};

/** In the order a receptionist reads the day: what to confirm first, what is already over last. */
export const CHIP_TONES: readonly StatusTone[] = [
  "pending",
  "confirmed",
  "arrived",
  "missed",
  "done",
];

// Each chip is named after the status that gives its tone.
const TONE_STATUS: Record<StatusTone, AppointmentStatus> = {
  pending: "scheduled",
  confirmed: "confirmed",
  arrived: "checked_in",
  missed: "no_show",
  done: "completed",
};

interface AgendaStatusChipsProps {
  /** Appointments of each status on screen, filtered or not. */
  counts: Record<StatusTone, number>;
  hidden: ReadonlySet<StatusTone>;
  onToggle(tone: StatusTone): void;
  onShowAll(): void;
  className?: string;
}

const CHIP =
  "inline-flex h-8 shrink-0 items-center gap-1.5 rounded-full border px-3 text-[0.8125rem] font-semibold transition-colors outline-none focus-visible:ring-3 focus-visible:ring-ring/40";

/** The statuses' legend, which is also the filter: a chip pressed is a status shown. */
export function AgendaStatusChips({
  counts,
  hidden,
  onToggle,
  onShowAll,
  className,
}: AgendaStatusChipsProps) {
  const { t } = useTranslation("appointments");
  const visible = CHIP_TONES.reduce((sum, tone) => sum + (hidden.has(tone) ? 0 : counts[tone]), 0);
  return (
    <div
      role="group"
      aria-label={t("agenda.filters.label")}
      className={cn("flex flex-wrap gap-1.5", className)}
    >
      <button
        type="button"
        aria-pressed={hidden.size === 0}
        className={cn(
          CHIP,
          hidden.size === 0
            ? "border-foreground bg-foreground text-background"
            : "border-border bg-background text-foreground hover:bg-muted",
        )}
        onClick={onShowAll}
      >
        {t("agenda.filters.all")}
        <span className="tabular-nums opacity-70">{visible}</span>
      </button>
      {CHIP_TONES.map((tone) => {
        const pressed = !hidden.has(tone);
        return (
          <button
            key={tone}
            type="button"
            aria-pressed={pressed}
            className={cn(
              CHIP,
              pressed
                ? "border-border bg-background text-foreground hover:bg-muted"
                : "border-dashed border-border bg-transparent text-muted-foreground line-through decoration-1 hover:text-foreground",
            )}
            onClick={() => onToggle(tone)}
          >
            <span
              className={cn("size-[7px] rounded-full", TONE_DOT[tone], !pressed && "opacity-40")}
              aria-hidden="true"
            />
            {t(`agenda.status.${TONE_STATUS[tone]}`)}
            <span className="tabular-nums opacity-70">{counts[tone]}</span>
          </button>
        );
      })}
    </div>
  );
}
