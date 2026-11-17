import type { components } from "@ceiba/api-client";

type Slot = components["schemas"]["WeeklyScheduleSlot"];
export type SchedulePayload = components["schemas"]["WeeklyScheduleInput"];

/** One editable slot. `key` identifies the row in the UI only (a server id would change on every replace). */
export interface SlotDraft {
  key: string;
  weekday: number;
  start: string;
  end: string;
}

export type SlotProblem = "required" | "endBeforeStart" | "overlap";

/** The contract numbers Sunday 0 (Date#wday); the editor shows Monday first. */
export const WEEK_ORDER = [1, 2, 3, 4, 5, 6, 0] as const;

const HHMM = /^\d{2}:\d{2}$/;

export function toDrafts(slots: readonly Slot[]): SlotDraft[] {
  return slots.map((slot) => ({
    key: slot.id,
    weekday: slot.weekday,
    start: slot.starts_at_local,
    end: slot.ends_at_local,
  }));
}

/** The full weekly schedule in the order the API stores it (day, then start): the PUT replaces everything. */
export function toPayload(drafts: readonly SlotDraft[]): SchedulePayload {
  const slots = drafts
    .map(({ weekday, start, end }) => ({
      weekday,
      starts_at_local: start,
      ends_at_local: end,
    }))
    .sort((a, b) => a.weekday - b.weekday || a.starts_at_local.localeCompare(b.starts_at_local));
  return { slots };
}

/**
 * Problems the client can see before sending. Slots that merely touch (13:00 end, 13:00 start) are fine; slots with a
 * missing or reversed time are excluded from the overlap check so one mistake is reported once. Overlaps against the
 * same person's hours in other branches are only visible to the server.
 */
export function validateSlots(drafts: readonly SlotDraft[]): Map<string, SlotProblem> {
  const problems = new Map<string, SlotProblem>();
  const usable: SlotDraft[] = [];

  for (const slot of drafts) {
    if (!HHMM.test(slot.start) || !HHMM.test(slot.end)) problems.set(slot.key, "required");
    else if (slot.end <= slot.start) problems.set(slot.key, "endBeforeStart");
    else usable.push(slot);
  }

  for (const [index, a] of usable.entries()) {
    for (const b of usable.slice(index + 1)) {
      if (a.weekday === b.weekday && a.start < b.end && b.start < a.end) {
        problems.set(a.key, "overlap");
        problems.set(b.key, "overlap");
      }
    }
  }
  return problems;
}
