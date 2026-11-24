import { formatTime, useTranslation } from "@ceiba/i18n";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useMe } from "../../../platform/me/me-provider";
import {
  useAgendaAppointments,
  useAgendaProfessionals,
  useAgendaResources,
  useAgendaServiceNames,
  useProfessionalProfiles,
  type AgendaAppointment,
} from "../api/agenda";
import type { Branch } from "../api/catalog";
import { appointmentActions } from "./agenda-actions";
import { toCalendarEvents, toCalendarResources } from "./agenda-calendar";
import { AGENDA_LENSES, type AgendaMode } from "./agenda-lens";
import {
  NO_RESOURCE,
  mergeProfessionalColumns,
  upcomingArrivals,
  visibleAppointments,
  type AgendaColumn,
} from "./agenda-model";
import { useAgendaPermissions } from "./agenda-permissions";
import {
  addDays,
  mondayOf,
  toWallClock,
  todayInZone,
  type PlainDate,
} from "./agenda-time";
import { useAgendaAvailability } from "./use-agenda-availability";

const DEFAULT_STEP_MINUTES = 15;
const CLOCK_TICK_MS = 60_000;
const WEEK_DAYS = 7;

function useNow() {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), CLOCK_TICK_MS);
    return () => clearInterval(timer);
  }, []);
  return now;
}

function useStepMinutes() {
  const { modules } = useMe();
  const step = modules.find((item) => item.key === "appointments")?.settings.slot_step_minutes;
  return typeof step === "number" ? step : DEFAULT_STEP_MINUTES;
}

interface AgendaScreenOptions {
  branch: Branch;
  mode: AgendaMode;
  date: PlainDate;
  weekProfessionalId: string | null;
}

/** Everything the agenda page draws, derived from the API and from what this user may read. */
export function useAgendaScreen({ branch, mode, date, weekProfessionalId }: AgendaScreenOptions) {
  const { t } = useTranslation("appointments");
  const permissions = useAgendaPermissions();
  const now = useNow();
  const stepMinutes = useStepMinutes();
  const timeZone = branch.time_zone;
  const today = todayInZone(timeZone, now);
  const lens = AGENDA_LENSES[mode];
  const isWeek = mode === "week";
  const { readsBranch } = permissions;

  const professionals = useAgendaProfessionals(permissions.readsProfessionals);
  const assigned = useMemo(
    () => (professionals.data ?? []).filter((item) => item.branch_ids.includes(branch.id)),
    [professionals.data, branch.id],
  );

  const days = useMemo(() => {
    if (!isWeek) return [date];
    const monday = mondayOf(date);
    return Array.from({ length: WEEK_DAYS }, (_, index) => addDays(monday, index));
  }, [isWeek, date]);

  // Staff look at one person's week; a professional's listing is already only theirs.
  const professionalId =
    isWeek && readsBranch ? (weekProfessionalId ?? assigned[0]?.id) : undefined;
  const appointments = useAgendaAppointments(branch.id, days[0]!, days.at(-1)!, {
    professionalId,
    enabled: !isWeek || !readsBranch || !!professionalId,
  });
  const todays = useAgendaAppointments(branch.id, today, today);
  const all = appointments.data?.data;
  const todaysAll = todays.data?.data;
  const visible = useMemo(() => visibleAppointments(all ?? []), [all]);

  const unknownProfessionals = useMemo(() => {
    const known = new Set((professionals.data ?? []).map((item) => item.id));
    const everyone = [...visible, ...(todaysAll ?? [])];
    return [...new Set(everyone.map((item) => item.professional_id))].filter(
      (id) => !known.has(id),
    );
  }, [professionals.data, visible, todaysAll]);
  const profiles = useProfessionalProfiles(branch.id, unknownProfessionals);

  const professionalName = useMemo(() => {
    const names = new Map((professionals.data ?? []).map((item) => [item.id, item.display_name]));
    return (id: string) => names.get(id) ?? profiles.get(id) ?? t("agenda.professionalFallback");
  }, [professionals.data, profiles, t]);

  const resources = useAgendaResources(branch.id, permissions.readsResources);
  const activeResources = useMemo(
    () => (resources.data ?? []).filter((item) => item.active && !item.archived_at),
    [resources.data],
  );

  const columns = useMemo((): AgendaColumn[] => {
    if (professionalId) return [{ id: professionalId, title: professionalName(professionalId) }];
    if (lens.ownerKind === "professional") {
      return mergeProfessionalColumns({
        branchId: branch.id,
        professionals: professionals.data ?? [],
        appointments: visible,
        nameOf: professionalName,
      });
    }
    const known = new Set(activeResources.map((item) => item.id));
    const unplaced = visible.some((item) => !item.resource_id || !known.has(item.resource_id));
    return [
      ...activeResources.map(({ id, name }) => ({ id, title: name })),
      ...(unplaced ? [{ id: NO_RESOURCE, title: t("agenda.noResource") }] : []),
    ];
  }, [
    professionalId,
    lens,
    branch.id,
    professionals.data,
    visible,
    professionalName,
    activeResources,
    t,
  ]);

  const serviceNames = useAgendaServiceNames();
  const serviceLabel = useCallback(
    (appointment: AgendaAppointment) =>
      appointment.services
        .map((line) => serviceNames.get(line.service_id) ?? t("agenda.serviceFallback"))
        .join(", "),
    [serviceNames, t],
  );

  const events = useMemo(() => {
    const clock = (iso: string) => formatTime(iso, timeZone);
    return toCalendarEvents({
      appointments: visible,
      columns,
      lens,
      timeZone,
      canMove: (appointment) =>
        appointmentActions(appointment, permissions.appointment, new Date()).canReschedule,
      labelsOf: (appointment) => ({
        title: appointment.customer_name ?? t("agenda.customerFallback"),
        subtitle: serviceLabel(appointment),
        meta: t("agenda.cardMeta", {
          range: t("agenda.timeRange", {
            start: clock(appointment.starts_at),
            end: clock(appointment.ends_at),
          }),
          status: t(`agenda.status.${appointment.status}`),
        }),
      }),
    });
  }, [visible, columns, lens, timeZone, permissions.appointment, serviceLabel, t]);

  const viewResources = useMemo(
    () => toCalendarResources(columns, events, (count) => t("agenda.appointmentCount", { count })),
    [columns, events, t],
  );

  const { blocks, range } = useAgendaAvailability({
    branchId: branch.id,
    timeZone,
    lens,
    columns,
    days,
    appointments: visible,
    appointmentsReady: appointments.isSuccess,
  });

  const arrivals = useMemo(() => upcomingArrivals(todaysAll ?? [], now), [todaysAll, now]);

  return {
    appointments,
    knownAppointments: [...(all ?? []), ...(todaysAll ?? [])],
    visible,
    assigned,
    /** Who can take a new or moved appointment: assigned to the branch and not paused. */
    bookable: assigned.filter((person) => person.active),
    resources: activeResources,
    columns,
    viewResources,
    events,
    blocks,
    range,
    today,
    stepMinutes,
    weekProfessionalId: professionalId ?? null,
    /** The week view needs a person and the branch has nobody (or the list has not arrived). */
    weekWithoutProfessional: isWeek && readsBranch && !professionalId,
    professionalsLoading: professionals.isLoading,
    pendingCount: visible.filter((item) => item.status === "scheduled").length,
    nowLine: days.includes(today) ? toWallClock(now.toISOString(), timeZone) : null,
    arrivals,
    professionalName,
    serviceLabel,
  };
}
