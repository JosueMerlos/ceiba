import { useCallback } from "react";
import { useSearchParams } from "react-router";
import { AGENDA_MODES, type AgendaMode } from "./agenda-lens";
import { isPlainDate, todayInZone, type PlainDate } from "./agenda-time";

/** What the agenda shows lives in the URL, so a view can be reloaded or shared. Whatever is not valid there is ignored. */
export function useAgendaUrlState(
  timeZone: string,
  { canViewResources }: { canViewResources: boolean },
) {
  const [params, setParams] = useSearchParams();

  const update = useCallback(
    (key: string, value: string) =>
      setParams((current) => {
        const next = new URLSearchParams(current);
        next.set(key, value);
        return next;
      }),
    [setParams],
  );

  const requestedDate = params.get("date");
  const requestedMode = AGENDA_MODES.find((mode) => mode === params.get("view"));
  const allowed = requestedMode !== "resources" || canViewResources;

  return {
    date: requestedDate && isPlainDate(requestedDate) ? requestedDate : todayInZone(timeZone),
    mode: requestedMode && allowed ? requestedMode : ("professionals" as AgendaMode),
    weekProfessionalId: params.get("pro"),
    setDate: (date: PlainDate) => update("date", date),
    setMode: (mode: AgendaMode) => update("view", mode),
    setWeekProfessional: (id: string) => update("pro", id),
  };
}
