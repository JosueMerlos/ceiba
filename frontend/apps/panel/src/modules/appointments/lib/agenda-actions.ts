import type { AgendaAppointment } from "./agenda-model";

export type AgendaAction =
  "confirm" | "check_in" | "complete" | "no_show" | "reschedule" | "cancel";
export type StatusAction = Exclude<AgendaAction, "reschedule" | "cancel">;

type Status = AgendaAppointment["status"];

const ACTIVE: readonly Status[] = ["scheduled", "confirmed"];

// Mirrors the backend's transition table so the panel only offers what can work; the API still decides.
const RULES: readonly { action: AgendaAction; from: readonly Status[]; own: boolean }[] = [
  { action: "confirm", from: ["scheduled"], own: true },
  { action: "check_in", from: ACTIVE, own: true },
  { action: "complete", from: ["checked_in"], own: true },
  { action: "no_show", from: ACTIVE, own: true },
  { action: "reschedule", from: ACTIVE, own: false },
  { action: "cancel", from: ACTIVE, own: false },
];

export function availableActions(
  appointment: Pick<AgendaAppointment, "status" | "starts_at">,
  { manage, own }: { manage: boolean; own: boolean },
  now: Date,
): AgendaAction[] {
  const started = Date.parse(appointment.starts_at) <= now.getTime();
  return RULES.filter(
    (rule) =>
      rule.from.includes(appointment.status) &&
      (manage || (own && rule.own)) &&
      (rule.action !== "no_show" || started),
  ).map((rule) => rule.action);
}

/** Starts overlapping the appointment itself: availability counts it as busy, yet moving it over itself is allowed. */
export function nearbyOwnStarts(
  appointment: Pick<AgendaAppointment, "starts_at" | "ends_at">,
  stepMinutes: number,
): string[] {
  const start = Date.parse(appointment.starts_at);
  const minutes = (Date.parse(appointment.ends_at) - start) / 60_000;
  const starts: string[] = [];
  for (let offset = stepMinutes - minutes; offset < minutes; offset += stepMinutes) {
    if (offset !== 0) starts.push(new Date(start + offset * 60_000).toISOString());
  }
  return starts;
}
