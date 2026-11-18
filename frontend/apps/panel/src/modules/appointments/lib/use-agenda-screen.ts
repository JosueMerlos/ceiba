import { useTranslation } from "@ceiba/i18n";
import { useEffect, useMemo, useState } from "react";
import { useMe } from "../../../platform/me/me-provider";
import { useCan } from "../../../platform/permissions/can";
import {
  useAgendaAppointments,
  useAgendaBranchSchedule,
  useAgendaProfessionals,
  useAgendaResources,
  useAgendaServiceNames,
  useOwnerAvailability,
  useProfessionalProfiles,
  type AgendaAppointment,
} from "../api/agenda";
import type { Branch } from "../api/catalog";
import type { AgendaViewEvent, AgendaViewResource } from "../components/agenda-view/types";
import {
  NO_RESOURCE,
  closedBlocks,
  mergeProfessionalColumns,
  openForProfessional,
  openForResource,
  timeRange,
  upcomingArrivals,
  visibleAppointments,
  type AgendaColumn,
  type BlockColumn,
} from "./agenda-model";
import { STATUS_TONE } from "./agenda-status";
import {
  addDays,
  mondayOf,
  shortClock,
  toWallClock,
  todayInZone,
  weekdayOf,
  type PlainDate,
} from "./agenda-time";

export type AgendaMode = "professionals" | "resources" | "week";

const DEFAULT_STEP_MINUTES = 15;
const CLOCK_TICK_MS = 60_000;
const MOVABLE = new Set<AgendaAppointment["status"]>(["scheduled", "confirmed"]);

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
  const settings = modules.find((item) => item.key === "appointments")?.settings as
    { slot_step_minutes?: number } | undefined;
  return settings?.slot_step_minutes ?? DEFAULT_STEP_MINUTES;
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
  const can = useCan();
  const now = useNow();
  const stepMinutes = useStepMinutes();
  const timeZone = branch.time_zone;
  const today = todayInZone(timeZone, now);

  const readsBranch = can("appointments.appointment.read");
  const canMove = can("appointments.appointment.update");
  const readsSchedules = can("appointments.schedule.read");
  const readsOwnSchedule = can("appointments.schedule.read_own");
  const readsAbsences = can("appointments.time_off.read");
  const readsResources = readsBranch && can("appointments.resource.read");

  const professionals = useAgendaProfessionals(can("appointments.professional.read"));
  const assigned = useMemo(
    () => (professionals.data ?? []).filter((item) => item.branch_ids.includes(branch.id)),
    [professionals.data, branch.id],
  );

  const isWeek = mode === "week";
  const days = useMemo(() => {
    if (!isWeek) return [date];
    const monday = mondayOf(date);
    return Array.from({ length: 7 }, (_, index) => addDays(monday, index));
  }, [isWeek, date]);

  // Staff look at one person's week; a professional's listing is already only theirs.
  const professionalId =
    isWeek && readsBranch ? (weekProfessionalId ?? assigned[0]?.id) : undefined;
  const appointments = useAgendaAppointments(branch.id, days[0]!, days.at(-1)!, {
    professionalId,
    enabled: !isWeek || !readsBranch || !!professionalId,
  });
  const todays = useAgendaAppointments(branch.id, today, today);

  const visible = useMemo(
    () => visibleAppointments(appointments.data?.data ?? []),
    [appointments.data],
  );
  const serviceNames = useAgendaServiceNames();

  const unknownProfessionals = useMemo(() => {
    const known = new Set((professionals.data ?? []).map((item) => item.id));
    const everyone = [...visible, ...(todays.data?.data ?? [])];
    return [...new Set(everyone.map((item) => item.professional_id))].filter(
      (id) => !known.has(id),
    );
  }, [professionals.data, visible, todays.data]);
  const profiles = useProfessionalProfiles(branch.id, unknownProfessionals);

  const professionalName = useMemo(() => {
    const names = new Map((professionals.data ?? []).map((item) => [item.id, item.display_name]));
    return (id: string) => names.get(id) ?? profiles[id] ?? t("agenda.professionalFallback");
  }, [professionals.data, profiles, t]);

  const resources = useAgendaResources(branch.id, readsResources);
  const activeResources = useMemo(
    () => (resources.data ?? []).filter((item) => item.active && !item.archived_at),
    [resources.data],
  );

  const columns = useMemo((): AgendaColumn[] => {
    if (mode === "resources") {
      const known = new Set(activeResources.map((item) => item.id));
      const unplaced = visible.some((item) => !item.resource_id || !known.has(item.resource_id));
      return [
        ...activeResources.map(({ id, name }) => ({ id, title: name })),
        ...(unplaced ? [{ id: NO_RESOURCE, title: t("agenda.noResource") }] : []),
      ];
    }
    return mergeProfessionalColumns({
      branchId: branch.id,
      professionals: professionals.data ?? [],
      appointments: visible,
      profiles,
      fallbackName: t("agenda.professionalFallback"),
    });
  }, [mode, activeResources, visible, branch.id, professionals.data, profiles, t]);

  const columnOf = useMemo(() => {
    const known = new Set(columns.map((column) => column.id));
    return (appointment: AgendaAppointment) => {
      if (mode !== "resources") return appointment.professional_id;
      const id = appointment.resource_id;
      return id && known.has(id) ? id : NO_RESOURCE;
    };
  }, [columns, mode]);

  const viewResources = useMemo((): AgendaViewResource[] => {
    const counts = new Map<string, number>();
    for (const item of visible) counts.set(columnOf(item), (counts.get(columnOf(item)) ?? 0) + 1);
    return columns.map(({ id, title }) => ({
      id,
      title,
      detail: t("agenda.appointmentCount", { count: counts.get(id) ?? 0 }),
    }));
  }, [columns, visible, columnOf, t]);

  const serviceLabel = useMemo(
    () => (appointment: AgendaAppointment) =>
      appointment.services
        .map((line) => serviceNames.get(line.service_id) ?? t("agenda.serviceFallback"))
        .join(", "),
    [serviceNames, t],
  );

  const events = useMemo(
    (): AgendaViewEvent[] =>
      visible.map((appointment) => {
        const range = t("agenda.timeRange", {
          start: shortClock(appointment.starts_at, timeZone),
          end: shortClock(appointment.ends_at, timeZone),
        });
        return {
          id: appointment.id,
          resourceId: columnOf(appointment),
          start: toWallClock(appointment.starts_at, timeZone),
          end: toWallClock(appointment.ends_at, timeZone),
          tone: STATUS_TONE[appointment.status],
          title: appointment.customer_name ?? t("agenda.customerFallback"),
          subtitle: serviceLabel(appointment),
          meta: t("agenda.cardMeta", { range, status: t(`agenda.status.${appointment.status}`) }),
          // A resource is assigned by the booking engine, so a drag cannot choose one.
          movable: canMove && mode !== "resources" && MOVABLE.has(appointment.status),
        };
      }),
    [visible, timeZone, columnOf, serviceLabel, canMove, mode, t],
  );

  // Loaded after the appointments so that shading never delays the first useful paint.
  const appointmentsReady = appointments.isSuccess;
  const branchSchedule = useAgendaBranchSchedule(branch.id, readsSchedules && appointmentsReady);
  const branchSlots = branchSchedule.data?.data ?? null;
  const columnIds = useMemo(() => columns.map((column) => column.id), [columns]);
  const professionalIds = mode === "resources" ? [] : columnIds;
  const resourceIds = useMemo(
    () => (mode === "resources" ? columnIds.filter((id) => id !== NO_RESOURCE) : []),
    [mode, columnIds],
  );
  const professionalAvailability = useOwnerAvailability(
    branch.id,
    "professional",
    professionalIds,
    appointmentsReady && (readsSchedules ? readsAbsences : readsOwnSchedule),
  );
  const resourceAvailability = useOwnerAvailability(
    branch.id,
    "resource",
    resourceIds,
    appointmentsReady && readsSchedules && readsAbsences,
  );

  const { blocks, range } = useMemo(() => {
    const blockColumns: BlockColumn[] = [];
    if (mode === "resources") {
      for (const id of resourceIds) {
        const owner = resourceAvailability.get(id);
        if (!owner || !branchSlots) continue;
        const openOn = (weekday: number) => openForResource(branchSlots, owner.slots, weekday);
        blockColumns.push({ id, openOn, timeOffs: owner.timeOffs });
      }
    } else {
      for (const id of professionalIds) {
        const owner = professionalAvailability.get(id);
        // Staff need the branch's hours too; a professional cannot read them and sees their own.
        if (!owner || (readsSchedules && !branchSlots)) continue;
        const openOn = (weekday: number) => openForProfessional(branchSlots, owner.slots, weekday);
        blockColumns.push({ id, openOn, timeOffs: owner.timeOffs });
      }
    }
    const openings = blockColumns.length
      ? days.flatMap((day) => blockColumns.flatMap((column) => column.openOn(weekdayOf(day))))
      : [];
    const hours = timeRange({ openings, appointments: visible, timeZone });
    return {
      blocks: closedBlocks({ columns: blockColumns, days, timeZone, range: hours }),
      range: hours,
    };
    // professionalIds is derived from columnIds.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    mode,
    columnIds,
    resourceIds,
    resourceAvailability,
    professionalAvailability,
    branchSlots,
    readsSchedules,
    days,
    visible,
    timeZone,
  ]);

  const arrivals = useMemo(
    () => upcomingArrivals(todays.data?.data ?? [], now),
    [todays.data, now],
  );

  return {
    appointments,
    all: appointments.data?.data ?? [],
    todays: todays.data?.data ?? [],
    resources: activeResources,
    visible,
    assigned,
    columns,
    viewResources,
    events,
    blocks,
    range,
    days,
    today,
    stepMinutes,
    weekProfessionalId: professionalId ?? null,
    readsBranch,
    readsResources,
    pendingCount: visible.filter((item) => item.status === "scheduled").length,
    nowLine: days.includes(today) ? toWallClock(now.toISOString(), timeZone) : null,
    arrivals,
    professionalName,
    serviceLabel,
  };
}
