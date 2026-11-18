import { useEffect, useMemo, useState } from "react";
import { useAgendaBranchSchedule, useOwnerAvailability } from "../api/agenda-availability";
import type { AgendaLens } from "./agenda-lens";
import {
  NO_RESOURCE,
  closedBlocks,
  timeRange,
  type AgendaAppointment,
  type AgendaColumn,
  type BlockColumn,
} from "./agenda-model";
import { useAgendaPermissions } from "./agenda-permissions";
import { weekdayOf, type PlainDate } from "./agenda-time";

const IDLE_TIMEOUT_MS = 1_500;
const IDLE_FALLBACK_MS = 200;

/** True once the browser is idle after `ready`: secondary data must not compete with the first paint and click. */
function useIdleAfter(ready: boolean) {
  const [idle, setIdle] = useState(false);
  useEffect(() => {
    if (!ready) return;
    const done = () => setIdle(true);
    if ("requestIdleCallback" in window) {
      const handle = window.requestIdleCallback(done, { timeout: IDLE_TIMEOUT_MS });
      return () => window.cancelIdleCallback(handle);
    }
    const timer = setTimeout(done, IDLE_FALLBACK_MS);
    return () => clearTimeout(timer);
  }, [ready]);
  return idle;
}

/** The hours to draw and what is closed in them. Until it is known, only the appointments decide the hours. */
export function useAgendaAvailability({
  branchId,
  timeZone,
  lens,
  columns,
  days,
  appointments,
  appointmentsReady,
}: {
  branchId: string;
  timeZone: string;
  lens: AgendaLens;
  columns: readonly AgendaColumn[];
  days: readonly PlainDate[];
  appointments: readonly AgendaAppointment[];
  appointmentsReady: boolean;
}) {
  const { readsSchedules, readsOwnSchedule, readsAbsences } = useAgendaPermissions();
  const idle = useIdleAfter(appointmentsReady);
  const ownerIds = useMemo(
    () => columns.map((column) => column.id).filter((id) => id !== NO_RESOURCE),
    [columns],
  );
  const canLoad = readsSchedules
    ? readsAbsences
    : readsOwnSchedule && lens.ownerKind === "professional";
  const branchSchedule = useAgendaBranchSchedule(branchId, readsSchedules && idle);
  const owners = useOwnerAvailability(branchId, lens.ownerKind, ownerIds, canLoad && idle);
  const branchSlots = branchSchedule.data?.data ?? null;

  return useMemo(() => {
    // Staff need the branch's hours too; a professional cannot read them and sees their own.
    const known = !readsSchedules || branchSlots;
    const blockColumns: BlockColumn[] = known
      ? ownerIds.flatMap((id) => {
          const owner = owners.get(id);
          if (!owner) return [];
          return {
            id,
            timeOffs: owner.timeOffs,
            openOn: (weekday: number) => lens.openOn(branchSlots, owner.slots, weekday),
          };
        })
      : [];
    const openings = days.flatMap((day) =>
      blockColumns.flatMap((column) => column.openOn(weekdayOf(day))),
    );
    const range = timeRange({ openings, appointments, timeZone });
    return { range, blocks: closedBlocks({ columns: blockColumns, days, timeZone, range }) };
  }, [readsSchedules, branchSlots, ownerIds, owners, lens, days, appointments, timeZone]);
}
