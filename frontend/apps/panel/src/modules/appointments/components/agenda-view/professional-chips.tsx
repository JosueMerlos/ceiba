import { useTranslation } from "@ceiba/i18n";
import { cn } from "@ceiba/ui";
import { useMemo } from "react";
import { initials } from "../../../../platform/shell/initials";
import type { AgendaViewEvent, AgendaViewResource } from "./types";

/** The id of the «everyone» chip. */
export const EVERYONE = "";

interface ProfessionalChipsProps {
  resources: readonly AgendaViewResource[];
  events: readonly AgendaViewEvent[];
  value: string;
  onChange(id: string): void;
}

/** Whose day the phone list shows: everyone, or one person, each with their number of appointments. */
export function ProfessionalChips({ resources, events, value, onChange }: ProfessionalChipsProps) {
  const { t } = useTranslation("appointments");
  const counts = useMemo(() => {
    const byResource = new Map<string, number>();
    for (const { resourceId } of events) {
      byResource.set(resourceId, (byResource.get(resourceId) ?? 0) + 1);
    }
    return byResource;
  }, [events]);
  const chips = [
    { id: EVERYONE, title: t("agenda.list.all"), mark: "∑", count: events.length },
    ...resources.map(({ id, title }) => ({
      id,
      title,
      mark: initials(title),
      count: counts.get(id) ?? 0,
    })),
  ];
  return (
    <div
      role="group"
      aria-label={t("agenda.form.professional")}
      className="flex shrink-0 gap-1.5 overflow-x-auto border-b px-3 py-2 [scrollbar-width:none]"
    >
      {chips.map((chip) => {
        const pressed = chip.id === value;
        return (
          <button
            key={chip.id || "everyone"}
            type="button"
            aria-pressed={pressed}
            onClick={() => onChange(chip.id)}
            className={cn(
              "flex h-10 shrink-0 items-center gap-1.5 rounded-full border pr-3 pl-1 text-[0.8125rem] font-semibold whitespace-nowrap outline-none focus-visible:ring-3 focus-visible:ring-ring/40",
              pressed
                ? "border-foreground bg-foreground text-background"
                : "border-border bg-background text-foreground",
            )}
          >
            <span
              aria-hidden="true"
              className={cn(
                "grid size-[30px] place-items-center rounded-full text-[0.65rem] font-bold",
                pressed ? "bg-background text-foreground" : "bg-sidebar text-muted-foreground",
              )}
            >
              {chip.mark}
            </span>
            {chip.title}
            <span className="text-xs tabular-nums opacity-75">{chip.count}</span>
          </button>
        );
      })}
    </div>
  );
}
