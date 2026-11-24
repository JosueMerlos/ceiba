import { formatClock, formatPlainDate, useTranslation } from "@ceiba/i18n";
import { cn } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useState, type ReactNode } from "react";
import { initials } from "../../../../../platform/shell/initials";
import { wallClockToInstant } from "../../../lib/agenda-time";
import { freeSlots } from "../free-slots";
import "../agenda-view.css";
import type { AgendaViewEvent, AgendaViewProps } from "../types";

const ALL = "";
const MINUTE_MS = 60_000;

const clock = (wall: string) => formatClock(wall.slice(11, 16));
const minutesBetween = (start: string, end: string) =>
  (Date.parse(`${end}Z`) - Date.parse(`${start}Z`)) / MINUTE_MS;

type Row =
  | { kind: "day"; key: string; day: string }
  | { kind: "now"; key: string }
  | { kind: "free"; key: string; start: string; minutes: number }
  | { kind: "event"; key: string; event: AgendaViewEvent };

/** The order a phone reads the day in: by time, the gaps among the appointments and the current time between them. */
function rowsOf({
  events,
  free,
  now,
  byDay,
}: {
  events: readonly AgendaViewEvent[];
  free: readonly { start: string; minutes: number }[];
  now: string | null;
  byDay: boolean;
}): Row[] {
  const timed = [
    ...events.map((event) => ({
      at: event.start,
      row: { kind: "event", key: event.id, event } as Row,
    })),
    ...free.map((slot) => ({
      at: slot.start,
      row: { kind: "free", key: `free-${slot.start}`, ...slot } as Row,
    })),
  ].sort((a, b) => a.at.localeCompare(b.at));
  const rows: Row[] = [];
  let nowPlaced = !now;
  let lastDay = "";
  for (const { at, row } of timed) {
    if (byDay && at.slice(0, 10) !== lastDay) {
      lastDay = at.slice(0, 10);
      rows.push({ kind: "day", key: `day-${lastDay}`, day: lastDay });
    }
    if (!nowPlaced && now && at > now) {
      rows.push({ kind: "now", key: "now" });
      nowPlaced = true;
    }
    rows.push(row);
  }
  if (!nowPlaced && now && timed.length > 0 && timed.at(-1)!.at.slice(0, 10) === now.slice(0, 10)) {
    rows.push({ kind: "now", key: "now" });
  }
  return rows;
}

/** The agenda on a phone: one list per professional (or everyone), with the free gaps ready to book. */
export default function AgendaList({
  mode,
  date,
  timeZone,
  resources,
  events,
  blocks,
  range,
  stepMinutes,
  now,
  onSelectSlot,
  onOpenEvent,
}: AgendaViewProps) {
  const { t } = useTranslation("appointments");
  const [chosen, setChosen] = useState(ALL);
  const single = resources.length === 1 ? resources[0]!.id : null;
  const current = single ?? (resources.some((item) => item.id === chosen) ? chosen : ALL);
  const showChips = mode === "day" && !single && resources.length > 0;
  const nameOf = (id: string) => resources.find((item) => item.id === id)?.title ?? "";

  const shown = current === ALL ? events : events.filter((event) => event.resourceId === current);
  const free =
    mode === "day" && current !== ALL
      ? freeSlots({
          resourceId: current,
          date,
          range,
          busy: [...events, ...blocks],
          minMinutes: stepMinutes,
        })
      : [];
  const rows = rowsOf({ events: shown, free, now, byDay: mode === "week" });

  const duration = (minutes: number) => {
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    if (!hours) return t("agenda.list.minutes", { value: rest });
    return rest
      ? t("agenda.list.hoursMinutes", { hours, minutes: rest })
      : t("agenda.list.hours", { value: hours });
  };

  function renderRow(row: Row): ReactNode {
    switch (row.kind) {
      case "day":
        return (
          <h2 className="pt-2 text-sm font-semibold first-letter:uppercase">
            {formatPlainDate(row.day)}
          </h2>
        );
      case "now":
        return (
          <div className="my-0.5 flex items-center gap-2 text-xs font-bold text-destructive">
            <span className="sr-only">{t("agenda.currentTime")}</span>
            <span className="tabular-nums">{now ? clock(now) : null}</span>
            <span className="h-0.5 flex-1 bg-destructive" aria-hidden="true" />
          </div>
        );
      case "free": {
        const text = t("agenda.list.free", { duration: duration(row.minutes) });
        const content = (
          <>
            <span className="w-20 shrink-0 text-[0.8125rem] tabular-nums">{clock(row.start)}</span>
            <span className="flex-1 text-[0.8125rem]">{text}</span>
          </>
        );
        const look =
          "flex min-h-11 w-full items-center gap-3 rounded-xl border border-dashed border-border px-3 text-left text-muted-foreground";
        if (!onSelectSlot) return <div className={look}>{content}</div>;
        return (
          <button
            type="button"
            className={cn(
              look,
              "bg-background hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/40 outline-none",
            )}
            aria-label={t("agenda.list.freeAction", {
              duration: duration(row.minutes),
              time: clock(row.start),
              name: nameOf(current),
            })}
            onClick={() => {
              const startsAt = wallClockToInstant(row.start, timeZone);
              if (startsAt) onSelectSlot({ startsAt, resourceId: current });
            }}
          >
            {content}
            <Plus aria-hidden="true" className="size-4" />
          </button>
        );
      }
      case "event": {
        const { event } = row;
        const sub =
          current === ALL ? `${event.subtitle} · ${nameOf(event.resourceId)}` : event.subtitle;
        return (
          <button
            type="button"
            data-tone={event.tone}
            aria-label={[event.title, event.subtitle, event.meta].join(", ")}
            onClick={() => onOpenEvent?.(event.id)}
            className="agenda-card agenda-list__card"
          >
            <span className="flex w-20 shrink-0 flex-col gap-0.5 tabular-nums">
              <span className="font-bold">{clock(event.start)}</span>
              <span className="text-xs opacity-80">
                {duration(minutesBetween(event.start, event.end))}
              </span>
            </span>
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="agenda-card__title">
                <span className="agenda-card__dot" />
                <span className="agenda-card__name">{event.title}</span>
              </span>
              <span className="agenda-card__line">{sub}</span>
            </span>
          </button>
        );
      }
    }
  }

  return (
    <div data-slot="agenda-view" className="flex h-full min-h-0 flex-col">
      {showChips ? (
        <div
          role="tablist"
          aria-label={t("agenda.list.label")}
          className="flex shrink-0 gap-1.5 overflow-x-auto border-b px-3 py-2 [scrollbar-width:none]"
        >
          {[
            { id: ALL, title: t("agenda.list.all"), count: events.length },
            ...resources.map((item) => ({
              id: item.id,
              title: item.title,
              count: events.filter((event) => event.resourceId === item.id).length,
            })),
          ].map((item) => {
            const selected = item.id === current;
            return (
              <button
                key={item.id || "all"}
                type="button"
                role="tab"
                aria-selected={selected}
                onClick={() => setChosen(item.id)}
                className={cn(
                  "flex h-10 shrink-0 items-center gap-1.5 rounded-full border pr-3 pl-1 text-[0.8125rem] font-semibold whitespace-nowrap outline-none focus-visible:ring-3 focus-visible:ring-ring/40",
                  selected
                    ? "border-foreground bg-foreground text-background"
                    : "border-border bg-background text-foreground",
                )}
              >
                <span
                  aria-hidden="true"
                  className={cn(
                    "grid size-[30px] place-items-center rounded-full text-[0.65rem] font-bold",
                    selected ? "bg-background text-foreground" : "bg-sidebar text-muted-foreground",
                  )}
                >
                  {item.id ? initials(item.title) : "∑"}
                </span>
                {item.title}
                <span className="text-xs tabular-nums opacity-75">{item.count}</span>
              </button>
            );
          })}
        </div>
      ) : null}
      <ul
        aria-label={t("agenda.list.items")}
        className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto overscroll-contain px-3 pt-2 pb-24"
      >
        {rows.length === 0 ? (
          <li className="py-10 text-center text-muted-foreground">{t("agenda.list.empty")}</li>
        ) : (
          rows.map((row) => <li key={row.key}>{renderRow(row)}</li>)
        )}
      </ul>
    </div>
  );
}
