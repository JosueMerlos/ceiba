import { useTranslation } from "@ceiba/i18n";
import { cn } from "@ceiba/ui";
import { DRAWN_STATUSES, STATUS_TONE, type StatusTone } from "../lib/agenda-status";

const TONE_DOT: Record<StatusTone, string> = {
  pending: "bg-[var(--appointment-pending-dot)]",
  confirmed: "bg-[var(--appointment-confirmed-dot)]",
  arrived: "bg-[var(--appointment-arrived-dot)]",
  done: "bg-[var(--appointment-done-dot)]",
  missed: "bg-[var(--appointment-missed-dot)]",
};

const CHIP =
  "inline-flex h-8 shrink-0 items-center gap-1.5 rounded-full border px-3 text-[0.8125rem] font-semibold transition-colors outline-none focus-visible:ring-3 focus-visible:ring-ring/40";

interface AgendaStatusChipsProps {
  /** Appointments of each tone on screen, filtered or not. */
  counts: Record<StatusTone, number>;
  hidden: ReadonlySet<StatusTone>;
  onToggle(tone: StatusTone): void;
  onShowAll(): void;
  className?: string;
}

/** The statuses' legend, which is also the filter: a chip pressed is a status shown. */
export function AgendaStatusChips({
  counts,
  hidden,
  onToggle,
  onShowAll,
  className,
}: AgendaStatusChipsProps) {
  const { t } = useTranslation("appointments");
  const visible = DRAWN_STATUSES.reduce((sum, status) => {
    const tone = STATUS_TONE[status];
    return sum + (hidden.has(tone) ? 0 : counts[tone]);
  }, 0);
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
      {DRAWN_STATUSES.map((status) => {
        const tone = STATUS_TONE[status];
        const pressed = !hidden.has(tone);
        return (
          <button
            key={status}
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
            {t(`agenda.status.${status}`)}
            <span className="tabular-nums opacity-70">{counts[tone]}</span>
          </button>
        );
      })}
    </div>
  );
}
