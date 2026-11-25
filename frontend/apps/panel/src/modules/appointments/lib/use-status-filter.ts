import { useMemo, useState } from "react";
import type { AgendaViewEvent } from "../components/agenda-view/types";
import type { AgendaBlock } from "./agenda-model";
import type { StatusTone } from "./agenda-status";

const NONE: ReadonlySet<StatusTone> = new Set();

/** The statuses switched off with the chips: a filter of the screen, not of the data. Off, everything shows. */
export function useStatusFilter(events: readonly AgendaViewEvent[], enabled: boolean) {
  const [hidden, setHidden] = useState(NONE);
  const counts = useMemo(() => {
    const byTone: Record<StatusTone, number> = {
      pending: 0,
      confirmed: 0,
      arrived: 0,
      done: 0,
      missed: 0,
    };
    for (const event of events) byTone[event.tone] += 1;
    return byTone;
  }, [events]);
  const shown = useMemo(
    () =>
      !enabled || hidden.size === 0 ? events : events.filter((event) => !hidden.has(event.tone)),
    [enabled, hidden, events],
  );
  // Hiding an appointment does not free its time: a screen that offers gaps still treats it as taken.
  const hiddenBusy = useMemo(
    (): AgendaBlock[] =>
      shown === events
        ? []
        : events
            .filter((event) => hidden.has(event.tone))
            .map(({ resourceId, start, end }) => ({ resourceId, start, end })),
    [shown, events, hidden],
  );
  return {
    counts,
    hidden,
    shown,
    hiddenBusy,
    toggle(tone: StatusTone) {
      setHidden((current) => {
        const next = new Set(current);
        if (!next.delete(tone)) next.add(tone);
        return next;
      });
    },
    showAll: () => setHidden(NONE),
  };
}
