import {
  Interaction,
  ResourceTimeline,
  TimeGrid,
  createCalendar,
  destroyCalendar,
  type Calendar,
} from "@event-calendar/core";
import "@event-calendar/core/index.css";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { initials } from "../../../../../platform/shell/initials";
import type { MinuteRange } from "../../../lib/agenda-model";
import {
  clockOfMinutes,
  clockOfWall,
  localDateToInstant,
  minutesBetweenWalls,
  minutesOfWall,
  nextMinute,
} from "../../../lib/agenda-time";
import { cardTier, SLOT_MINUTES, SLOT_WIDTH, type CardTier } from "../card-tier";
import { useAgendaViewDensity } from "../density";
import "../agenda-view.css";
import type { AgendaDensity, AgendaViewEvent, AgendaViewProps, AgendaViewResource } from "../types";

const WEEK_SLOT_HEIGHT_PX = 32;
const TWO_LINES_FROM_MINUTES = 45;
const THREE_LINES_FROM_MINUTES = 60;
// The day view opens scrolled to an hour before now, so the next arrivals are on screen.
const SCROLL_BEFORE_NOW_MINUTES = 60;

// Unmounting is asynchronous and removes the library's shared event listeners: a calendar mounted before the previous one
// finished leaving would stop receiving clicks, so mounts wait for pending unmounts.
let teardown: Promise<unknown> = Promise.resolve();

// What a new calendar draws until told otherwise.
const FULL_DAY: MinuteRange = { startMinute: 0, endMinute: 24 * 60 };

const VIEW = { day: "resourceTimelineDay", week: "timeGridWeek" } as const;

function element<K extends keyof HTMLElementTagNameMap>(tag: K, className: string, text?: string) {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function part(name: string, className: string, text: string) {
  const node = element("span", className, text);
  node.dataset.part = name;
  return node;
}

function cardShell(event: AgendaViewEvent) {
  const card = element("div", "agenda-card");
  card.dataset.tone = event.tone;
  card.title = [event.title, event.subtitle, event.meta].join(", ");
  return card;
}

/** The status dot and the customer's name, the first line of every card that has room for a name. */
function cardHeading(event: AgendaViewEvent) {
  const heading = element("span", "agenda-card__title");
  heading.append(
    element("span", "agenda-card__dot"),
    part("name", "agenda-card__name", event.title),
  );
  return heading;
}

/**
 * A day card shows what fits its width: name and service, the name, or the initials. Screen readers always get all of
 * it. With `eventClick` set, the library's event element is already the focusable button around it.
 */
function dayCard(event: AgendaViewEvent, tier: CardTier) {
  const card = cardShell(event);
  card.dataset.tier = tier;
  if (tier === "initials") {
    card.append(
      part("initials", "agenda-card__initials", initials(event.title)),
      element("span", "sr-only", event.title),
    );
  } else {
    card.append(cardHeading(event));
    if (tier === "full") card.append(part("service", "agenda-card__line", event.subtitle));
    else card.append(element("span", "sr-only", event.subtitle));
  }
  card.append(element("span", "sr-only", event.meta));
  return card;
}

// In the week the days are columns, so what fits depends on the appointment's height.
function weekCard(event: AgendaViewEvent) {
  const minutes = minutesBetweenWalls(event.start, event.end);
  const lines = minutes >= THREE_LINES_FROM_MINUTES ? 3 : minutes >= TWO_LINES_FROM_MINUTES ? 2 : 1;
  const card = cardShell(event);
  card.append(
    cardHeading(event),
    element("span", lines >= 2 ? "agenda-card__line" : "sr-only", event.subtitle),
    element("span", lines >= 3 ? "agenda-card__meta" : "sr-only", event.meta),
  );
  return card;
}

function rowHeader(resource: AgendaViewResource) {
  const header = element("span", "agenda-row");
  header.setAttribute("role", "group");
  header.setAttribute("aria-label", resource.title);
  const text = element("span", "agenda-row__text");
  text.append(
    element("span", "agenda-row__name", resource.title),
    element("span", "agenda-row__detail", resource.detail),
  );
  header.append(element("span", "agenda-row__avatar", initials(resource.title)), text);
  return header;
}

/** Where the current time sits in the day's hour header, in pixels from the first hour. */
function nowOffset(now: string, range: MinuteRange, density: AgendaDensity) {
  const minutes = minutesOfWall(now);
  if (minutes < range.startMinute || minutes > range.endMinute) return null;
  return ((minutes - range.startMinute) * SLOT_WIDTH[density]) / SLOT_MINUTES;
}

/** `@event-calendar/core` behind AgendaView. It runs in UTC and receives the branch's wall clock as floating times. */
export default function EventCalendarAdapter(props: AgendaViewProps) {
  const { mode, date, resources, events, blocks, range, stepMinutes, now } = props;
  const density = useAgendaViewDensity();
  const host = useRef<HTMLDivElement>(null);
  const [calendar, setCalendar] = useState<Calendar | null>(null);
  const drawnRange = useRef<MinuteRange>(FULL_DAY);
  // The library keeps the callbacks of the first render; they read the current props through this ref.
  const latest = useRef({ ...props, density });
  useLayoutEffect(() => {
    latest.current = { ...props, density };
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
    }));
    const closed = blocks.map((block, index) => ({
      id: `block-${index}`,
      resourceIds: [block.resourceId],
      start: block.start,
      end: block.end,
      display: "background" as const,
      classNames: ["agenda-block"],
    }));
    // The library's own indicator would read the time in UTC, where it runs; this one is the branch's wall clock.
    const line = now
      ? [
          {
            id: "now",
            resourceIds: resources.map((item) => item.id),
            start: now,
            end: nextMinute(now),
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
      createCalendar(target, [ResourceTimeline, TimeGrid, Interaction], {
        view: VIEW[latest.current.mode],
        date: latest.current.date,
        // Floating times in UTC: nothing the calendar computes can depend on the browser's zone or its DST jumps.
        timeZone: "UTC",
        locale: "es-NI",
        firstDay: 1,
        headerToolbar: { start: "", center: "", end: "" },
        allDaySlot: false,
        // The agenda's box has a fixed height; the calendar scrolls inside it and keeps its hour header in place.
        height: "100%",
        slotDuration: { minutes: SLOT_MINUTES },
        slotHeight: WEEK_SLOT_HEIGHT_PX,
        slotWidth: SLOT_WIDTH[latest.current.density],
        slotEventOverlap: false,
        eventDurationEditable: false,
        resourceLabelContent: ({ resource }: { resource: { id: unknown } }) => {
          const row = latest.current.resources.find((item) => item.id === String(resource.id));
          return { domNodes: row ? [rowHeader(row)] : [] };
        },
        eventContent: ({ event }: { event: Calendar.Event }) => {
          const current = latest.current;
          const card = current.events.find((item) => item.id === String(event.id));
          if (!card) return { domNodes: [] };
          if (current.mode === "week") return { domNodes: [weekCard(card)] };
          const tier = cardTier(minutesBetweenWalls(card.start, card.end), current.density);
          return { domNodes: [dayCard(card, tier)] };
        },
        eventClick: ({ event }: { event: Calendar.Event }) => {
          const id = String(event.id);
          if (latest.current.events.some((item) => item.id === id)) {
            latest.current.onOpenEvent?.(id);
          }
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
      drawnRange.current = FULL_DAY;
      const finished = instance;
      if (finished) teardown = teardown.then(() => destroyCalendar(finished));
    };
  }, []);

  // One effect per option: each change makes the library recompute the whole grid, so only what changed is sent.
  useEffect(() => {
    calendar?.setOption("view", VIEW[mode]);
  }, [calendar, mode]);
  useEffect(() => {
    calendar?.setOption("date", date);
  }, [calendar, date]);
  useEffect(() => {
    calendar?.setOption("snapDuration", { minutes: stepMinutes });
  }, [calendar, stepMinutes]);
  const { startMinute, endMinute } = range;
  useEffect(() => {
    if (!calendar) return;
    const start = clockOfMinutes(startMinute);
    const end = clockOfMinutes(endMinute);
    // The library fails on an empty range, so the new limits must never cross the ones on screen.
    if (startMinute >= drawnRange.current.endMinute) {
      calendar.setOption("slotMaxTime", end);
      calendar.setOption("slotMinTime", start);
    } else {
      calendar.setOption("slotMinTime", start);
      calendar.setOption("slotMaxTime", end);
    }
    drawnRange.current = { startMinute, endMinute };
  }, [calendar, startMinute, endMinute]);
  // Read once per day shown: a minute tick must not pull the agenda away from where the person scrolled.
  const nowAtOpen = useRef(now);
  useEffect(() => {
    nowAtOpen.current = latest.current.now;
  }, [date]);
  useEffect(() => {
    const opened = nowAtOpen.current;
    if (!calendar || !opened) return;
    const minute = Math.max(startMinute, minutesOfWall(opened) - SCROLL_BEFORE_NOW_MINUTES);
    calendar.setOption("scrollTime", clockOfMinutes(minute));
  }, [calendar, date, startMinute]);
  // Compared by content: a refetch or a late label lookup builds equal arrays, and redrawing them would replace the cards
  // under the pointer and swallow a click.
  const resourcesKey = JSON.stringify(calendarResources);
  // The cards' texts are read from `events` when drawn, so a change there must redraw them too.
  const eventsKey = JSON.stringify([calendarEvents, events]);
  const sentEvents = useRef<Calendar.EventInput[]>([]);
  useEffect(() => {
    calendar?.setOption("resources", JSON.parse(resourcesKey));
  }, [calendar, resourcesKey]);
  useEffect(() => {
    if (!calendar) return;
    sentEvents.current = JSON.parse(eventsKey)[0];
    calendar.setOption("events", sentEvents.current);
  }, [calendar, eventsKey]);
  const drawnDensity = useRef(density);
  useEffect(() => {
    if (!calendar) return;
    calendar.setOption("slotWidth", SLOT_WIDTH[density]);
    if (drawnDensity.current === density) return;
    drawnDensity.current = density;
    // A card's tier depends on the density, and the library only redraws card contents when the events are set again.
    calendar.setOption("events", [...sentEvents.current]);
  }, [calendar, density]);

  // The time of the now line, in the hour header. The library owns that header, so the label is placed after it draws.
  useEffect(() => {
    const target = host.current;
    if (!calendar || !target || mode !== "day" || !now) return;
    const offset = nowOffset(now, { startMinute, endMinute }, density);
    if (offset === null) return;
    const label = element("span", "agenda-now-label", clockOfWall(now));
    label.setAttribute("aria-hidden", "true");
    label.style.setProperty("--agenda-now-x", `${offset}px`);
    // The library may rebuild its header (another day, range or density): the label goes back whenever it is gone.
    const place = () => {
      if (label.isConnected) return;
      target.querySelector(".ec-timeline .ec-header")?.append(label);
    };
    const observer = new MutationObserver(place);
    observer.observe(target, { childList: true, subtree: true });
    place();
    return () => {
      observer.disconnect();
      label.remove();
    };
  }, [calendar, mode, now, startMinute, endMinute, density]);

  return <div ref={host} data-slot="agenda-view" data-density={density} className="agenda-view" />;
}
