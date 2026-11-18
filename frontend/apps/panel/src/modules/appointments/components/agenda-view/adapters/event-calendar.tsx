import {
  Interaction,
  ResourceTimeGrid,
  TimeGrid,
  createCalendar,
  destroyCalendar,
  type Calendar,
} from "@event-calendar/core";
import "@event-calendar/core/index.css";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { initials } from "../../../../../platform/shell/initials";
import type { MinuteRange } from "../../../lib/agenda-model";
import { clockOfMinutes, localDateToInstant } from "../../../lib/agenda-time";
import "../agenda-view.css";
import type { AgendaViewEvent, AgendaViewProps, AgendaViewResource } from "../types";

const NOW_MINUTE_MS = 60_000;
const SLOT_HEIGHT_PX = 32;
const TWO_LINES_FROM_MINUTES = 45;
const THREE_LINES_FROM_MINUTES = 60;

// Unmounting is asynchronous and removes the library's shared event listeners: a calendar mounted before the previous one
// finished leaving would stop receiving clicks, so mounts wait for pending unmounts.
let teardown: Promise<unknown> = Promise.resolve();

type CalendarOption = Parameters<Calendar["setOption"]>[0];

const VIEW = { day: "resourceTimeGridDay", week: "timeGridWeek" } as const;

function element<K extends keyof HTMLElementTagNameMap>(tag: K, className: string, text?: string) {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

const minutesBetween = (start: string, end: string) =>
  (Date.parse(`${end}Z`) - Date.parse(`${start}Z`)) / NOW_MINUTE_MS;

// Plain content: with `eventClick` set, the library's event element is already the focusable button around it.
function appointmentCard(event: AgendaViewEvent) {
  const card = element("div", "agenda-card");
  card.dataset.tone = event.tone;
  const heading = element("span", "agenda-card__title");
  heading.append(
    element("span", "agenda-card__dot"),
    element("span", "agenda-card__name", event.title),
  );
  card.append(heading);
  // What fits depends on the height of the appointment; screen readers always get all of it.
  const minutes = minutesBetween(event.start, event.end);
  const line = element("span", "agenda-card__line", event.subtitle);
  const meta = element("span", "agenda-card__meta", event.meta);
  if (minutes < TWO_LINES_FROM_MINUTES) {
    line.className = "sr-only";
    meta.className = "sr-only";
  } else if (minutes < THREE_LINES_FROM_MINUTES) {
    meta.className = "sr-only";
  }
  card.append(line, meta);
  return card;
}

function columnHeader(resource: AgendaViewResource) {
  const header = element("span", "agenda-column");
  header.setAttribute("role", "group");
  header.setAttribute("aria-label", resource.title);
  const text = element("span", "agenda-column__text");
  text.append(
    element("span", "agenda-column__name", resource.title),
    element("span", "agenda-column__detail", resource.detail),
  );
  header.append(element("span", "agenda-column__avatar", initials(resource.title)), text);
  return header;
}

/** `@event-calendar/core` behind AgendaView. It runs in UTC and receives the branch's wall clock as floating times. */
export default function EventCalendarAdapter(props: AgendaViewProps) {
  const { mode, date, resources, events, blocks, range, stepMinutes, now } = props;
  const host = useRef<HTMLDivElement>(null);
  const [calendar, setCalendar] = useState<Calendar | null>(null);
  const applied = useRef(new Map<string, unknown>());
  const drawnRange = useRef<MinuteRange>({ startMinute: 0, endMinute: 24 * 60 });
  // The library keeps the callbacks of the first render; they read the current props through this ref.
  const latest = useRef(props);
  useLayoutEffect(() => {
    latest.current = props;
  });

  const calendarEvents = useMemo(() => {
    const cards = events.map((event) => ({
      id: event.id,
      resourceIds: [event.resourceId],
      start: event.start,
      end: event.end,
      title: event.title,
      startEditable: event.movable,
      durationEditable: false,
      extendedProps: { card: event },
    }));
    const closed = blocks.map((block, index) => ({
      id: `block-${index}`,
      resourceIds: [block.resourceId],
      start: block.start,
      end: block.end,
      display: "background" as const,
      classNames: ["agenda-block"],
    }));
    const line = now
      ? [
          {
            id: "now",
            resourceIds: resources.map((item) => item.id),
            start: now,
            end: new Date(Date.parse(`${now}Z`) + NOW_MINUTE_MS).toISOString().slice(0, 19),
            display: "background" as const,
            classNames: ["agenda-now"],
          },
        ]
      : [];
    return [...closed, ...line, ...cards];
  }, [events, blocks, now, resources]);

  const calendarResources = useMemo(
    () => resources.map(({ id, title }) => ({ id, title })),
    [resources],
  );

  useEffect(() => {
    if (!host.current) return;
    const toSlot = (start: Date, resource?: { id: unknown } | null) => {
      const startsAt = localDateToInstant(start, latest.current.timeZone);
      return startsAt ? { startsAt, resourceId: resource ? String(resource.id) : null } : null;
    };
    const target = host.current;
    const create = () =>
      createCalendar(target, [ResourceTimeGrid, TimeGrid, Interaction], {
        view: VIEW[latest.current.mode],
        date: latest.current.date,
        // Floating times in UTC: nothing the calendar computes can depend on the browser's zone or its DST jumps.
        timeZone: "UTC",
        locale: "es-NI",
        firstDay: 1,
        headerToolbar: { start: "", center: "", end: "" },
        allDaySlot: false,
        height: "auto",
        slotDuration: "00:30",
        slotHeight: SLOT_HEIGHT_PX,
        slotEventOverlap: false,
        eventDurationEditable: false,
        resourceLabelContent: ({ resource }: { resource: { id: unknown } }) => {
          const column = latest.current.resources.find((item) => item.id === String(resource.id));
          return { domNodes: column ? [columnHeader(column)] : [] };
        },
        eventContent: ({ event }: { event: Calendar.Event }) => {
          const card = event.extendedProps?.card as AgendaViewEvent | undefined;
          return { domNodes: card ? [appointmentCard(card)] : [] };
        },
        eventClick: ({ event }: { event: Calendar.Event }) => {
          if (event.extendedProps?.card) latest.current.onOpenEvent?.(String(event.id));
        },
        dateClick: ({ date: clicked, resource }: { date: Date; resource?: { id: unknown } }) => {
          const slot = toSlot(clicked, resource);
          if (slot) latest.current.onSelectSlot?.(slot);
        },
        eventDrop: (info: {
          event: Calendar.Event;
          newResource?: { id: unknown } | null;
          oldEvent: Calendar.Event;
          revert(): void;
        }) => {
          const resourceId = info.newResource ?? { id: info.oldEvent.resourceIds?.[0] };
          const slot = toSlot(info.event.start as Date, resourceId);
          const move = latest.current.onMoveEvent;
          if (!slot || !move) return info.revert();
          void move(String(info.event.id), slot).then((moved) => {
            if (!moved) info.revert();
          });
        },
      });
    let instance: Calendar | null = null;
    let unmounted = false;
    void teardown.then(() => {
      if (unmounted) return;
      instance = create();
      setCalendar(instance);
    });
    return () => {
      unmounted = true;
      setCalendar(null);
      const finished = instance;
      if (finished) teardown = teardown.then(() => destroyCalendar(finished));
    };
  }, []);

  useEffect(() => {
    if (!calendar) {
      applied.current.clear();
      return;
    }
    // Every option makes the library recompute the whole grid, so only what really changed is sent.
    const apply = (name: CalendarOption, value: unknown) => {
      if (applied.current.get(name) === value) return;
      applied.current.set(name, value);
      calendar.setOption(name, value as never);
    };
    apply("view", VIEW[mode]);
    apply("date", date);
    apply("snapDuration", `00:${String(stepMinutes).padStart(2, "0")}`);
    // An empty range makes the library fail, so the new limits must never cross the old ones.
    const limits: [CalendarOption, string][] = [
      ["slotMinTime", clockOfMinutes(range.startMinute)],
      ["slotMaxTime", clockOfMinutes(range.endMinute)],
    ];
    const movesPastEnd = range.startMinute >= drawnRange.current.endMinute;
    for (const [name, value] of movesPastEnd ? limits.reverse() : limits) apply(name, value);
    drawnRange.current = range;
    apply("resources", calendarResources);
    apply("events", calendarEvents);
  }, [calendar, mode, date, stepMinutes, range, calendarResources, calendarEvents]);

  return <div ref={host} data-slot="agenda-view" className="agenda-view" />;
}
