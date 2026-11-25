import { formatPlainDate, useTranslation } from "@ceiba/i18n";
import { cn } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useState, type ReactNode } from "react";
import {
  clockOfWall,
  minutesBetweenWalls,
  minutesOfWall,
  wallClockToInstant,
  type WallClock,
} from "../../../lib/agenda-time";
import { freeSlots, type FreeSlot } from "../free-slots";
import { EVERYONE, ProfessionalChips } from "../professional-chips";
import "../agenda-view.css";
import type { AgendaViewEvent, AgendaViewProps } from "../types";

type Row =
  | { kind: "day"; key: string; day: string }
  | { kind: "now"; key: string }
  | ({ kind: "free"; key: string } & FreeSlot)
  | { kind: "event"; key: string; event: AgendaViewEvent };

interface Timed {
  at: WallClock;
  row: Row;
}

/** The order a phone reads the day in: by time, the gaps among the appointments and the current time between them. */
function rowsOf({
  events,
  free,
  now,
  byDay,
}: {
  events: readonly AgendaViewEvent[];
  free: readonly FreeSlot[];
  now: WallClock | null;
  byDay: boolean;
}): Row[] {
  const timed: Timed[] = [
    ...events.map((event): Timed => ({
      at: event.start,
      row: { kind: "event", key: event.id, event },
    })),
    ...free.map((slot): Timed => ({
      at: slot.start,
      row: { kind: "free", key: `free-${slot.start}`, ...slot },
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
  const last = timed.at(-1);
  if (!nowPlaced && now && last && last.at.slice(0, 10) === now.slice(0, 10)) {
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
  const [chosen, setChosen] = useState(EVERYONE);
  const single = resources.length === 1 ? resources[0]?.id : undefined;
  const current = single ?? (resources.some((item) => item.id === chosen) ? chosen : EVERYONE);
  const showChips = mode === "day" && !single && resources.length > 0;
  const nameOf = (id: string) => resources.find((item) => item.id === id)?.title ?? "";

  const shown =
    current === EVERYONE ? events : events.filter((event) => event.resourceId === current);
  const free =
    mode === "day" && current !== EVERYONE
      ? freeSlots({
          resourceId: current,
          date,
          range,
          busy: [...events, ...blocks],
          minMinutes: stepMinutes,
          notBefore: now?.slice(0, 10) === date ? minutesOfWall(now) : 0,
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
            <span className="tabular-nums">{now ? clockOfWall(now) : null}</span>
            <span className="h-0.5 flex-1 bg-destructive" aria-hidden="true" />
          </div>
        );
      case "free": {
        const text = t("agenda.list.free", { duration: duration(row.minutes) });
        const content = (
          <>
            <span className="w-20 shrink-0 text-[0.8125rem] tabular-nums">
              {clockOfWall(row.start)}
            </span>
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
              time: clockOfWall(row.start),
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
          current === EVERYONE ? `${event.subtitle} · ${nameOf(event.resourceId)}` : event.subtitle;
        return (
          <button
            type="button"
            data-tone={event.tone}
            aria-label={[event.title, event.subtitle, event.meta].join(", ")}
            onClick={() => onOpenEvent?.(event.id)}
            className="agenda-card agenda-list__card"
          >
            <span className="flex w-20 shrink-0 flex-col gap-0.5 tabular-nums">
              <span className="font-bold">{clockOfWall(event.start)}</span>
              <span className="text-xs opacity-80">
                {duration(minutesBetweenWalls(event.start, event.end))}
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
        <ProfessionalChips
          resources={resources}
          events={events}
          value={current}
          onChange={setChosen}
        />
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
