import { isApiError } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import { Button, LoadingState, PageHeader, toast } from "@ceiba/ui";
import { useEffect, useId, useState } from "react";
import { useSearchParams } from "react-router";
import { useContextSelection } from "../../../platform/context/context-provider";
import { apiErrorMessages } from "../../../platform/forms/api-error-messages";
import { useMe } from "../../../platform/me/me-provider";
import { useCan } from "../../../platform/permissions/can";
import type { AgendaAppointment } from "../api/agenda";
import { useRescheduleAppointment, useStatusAction } from "../api/agenda-mutations";
import type { Branch } from "../api/catalog";
import { AppointmentDetailPanel } from "../components/agenda/appointment-detail-panel";
import { NewAppointmentPanel } from "../components/agenda/new-appointment-panel";
import { AgendaLegend } from "../components/agenda-legend";
import { AgendaToolbar } from "../components/agenda-toolbar";
import { AgendaView, preloadAgendaView } from "../components/agenda-view/agenda-view";
import type { AgendaSlot } from "../components/agenda-view/types";
import { BranchPicker } from "../components/branch-picker";
import { QueryBoundary } from "../components/query-boundary";
import { UpcomingArrivals } from "../components/upcoming-arrivals";
import { availableActions, type StatusAction } from "../lib/agenda-actions";
import { NO_RESOURCE } from "../lib/agenda-model";
import { addDays, mondayOf, todayInZone, type PlainDate } from "../lib/agenda-time";
import { useAgendaScreen, type AgendaMode } from "../lib/use-agenda-screen";
import { useWorkingBranch } from "../lib/use-working-branch";

const PLAIN_DATE = /^\d{4}-\d{2}-\d{2}$/;
const MODES: readonly AgendaMode[] = ["professionals", "resources", "week"];
const WIDE_SCREEN_PX = 1280;

// The date is a calendar day, so it is formatted in UTC: no zone may move it to the neighboring day.
const dayFormat = new Intl.DateTimeFormat("es-NI", {
  weekday: "long",
  day: "numeric",
  month: "long",
  timeZone: "UTC",
});
const shortDayFormat = new Intl.DateTimeFormat("es-NI", {
  day: "numeric",
  month: "long",
  timeZone: "UTC",
});
const calendarDay = (day: PlainDate) => new Date(`${day}T12:00:00Z`);

type SidePanel =
  | { kind: "arrivals" }
  | { kind: "new"; slot: AgendaSlot | null }
  | { kind: "detail"; appointmentId: string }
  | null;

export function AgendaPage() {
  const { t } = useTranslation("appointments");
  const working = useWorkingBranch();
  const { context } = useMe();
  const { switchContext } = useContextSelection();

  // Permissions in /me depend on the branch in the context, so choosing one here changes the context itself.
  function chooseBranch(branchId: string) {
    switchContext({
      organization_id: context.organization?.id,
      company_id: context.company?.id,
      branch_id: branchId,
    });
  }

  if (working.needsChoice) {
    return (
      <>
        <PageHeader title={t("agenda.title")} />
        <BranchPicker branches={working.branches} value={null} onChange={chooseBranch} />
      </>
    );
  }
  return working.branch ? <BranchAgenda key={working.branch.id} branch={working.branch} /> : null;
}

function BranchAgenda({ branch }: { branch: Branch }) {
  const { t } = useTranslation("appointments");
  const can = useCan();
  const panelId = useId();
  useEffect(preloadAgendaView, []);
  const [params, setParams] = useSearchParams();
  // The sheet keeps one side panel at a time, and on wide screens it starts with the arrivals.
  const [panel, setPanel] = useState<SidePanel>(() =>
    window.innerWidth >= WIDE_SCREEN_PX ? { kind: "arrivals" } : null,
  );

  const requestedDate = params.get("date");
  const date =
    requestedDate && PLAIN_DATE.test(requestedDate) ? requestedDate : todayInZone(branch.time_zone);
  const requestedMode = params.get("view") as AgendaMode | null;
  const mode: AgendaMode =
    requestedMode && MODES.includes(requestedMode) ? requestedMode : "professionals";

  const screen = useAgendaScreen({ branch, mode, date, weekProfessionalId: params.get("pro") });
  const isWeek = mode === "week";
  const reschedule = useRescheduleAppointment(branch.id);
  const statusAction = useStatusAction(branch.id);
  const canCreate = can("appointments.appointment.create");
  const canManage = can("appointments.appointment.update");
  const canActOnOwn = can("appointments.appointment.update_own");
  const closePanel = () => setPanel(null);

  async function moveEvent(id: string, to: AgendaSlot) {
    const professionalChanged = mode === "professionals" && to.resourceId !== NO_RESOURCE;
    try {
      await reschedule.mutateAsync({
        id,
        key: crypto.randomUUID(),
        body: {
          starts_at: to.startsAt,
          ...(professionalChanged && to.resourceId ? { professional_id: to.resourceId } : {}),
        },
      });
      toast.success(t("agenda.detail.moved"));
      return true;
    } catch (error) {
      // The global handler announces everything except a 422, which here has no form to show it.
      if (isApiError(error) && error.status === 422) {
        toast.error(apiErrorMessages(error, t).join(" "));
      }
      return false;
    }
  }

  function arrivalAction(appointment: AgendaAppointment) {
    const action = availableActions(
      appointment,
      { manage: canManage, own: canActOnOwn },
      new Date(),
    ).find((item): item is StatusAction => item === "confirm" || item === "check_in");
    if (!action) return null;
    return (
      <Button
        type="button"
        variant="outline"
        size="sm"
        loading={statusAction.isPending && statusAction.variables?.id === appointment.id}
        onClick={() => statusAction.mutate({ id: appointment.id, action })}
      >
        {t(`agenda.actions.${action}`)}
      </Button>
    );
  }

  const selected =
    panel?.kind === "detail"
      ? [...screen.all, ...screen.todays].find((item) => item.id === panel.appointmentId)
      : undefined;

  function update(changes: Record<string, string>) {
    setParams((current) => {
      const next = new URLSearchParams(current);
      for (const [key, value] of Object.entries(changes)) next.set(key, value);
      return next;
    });
  }

  const step = isWeek ? 7 : 1;
  const title = isWeek
    ? t("agenda.weekTitle", { date: shortDayFormat.format(calendarDay(mondayOf(date))) })
    : t("agenda.dayTitle", { date: dayFormat.format(calendarDay(date)).replace(",", "") });

  return (
    <>
      <PageHeader
        title={title}
        description={t("agenda.summary", {
          count: screen.visible.length,
          pending: screen.pendingCount,
        })}
        actions={
          <AgendaToolbar
            mode={mode}
            onModeChange={(view) => update({ view })}
            canViewResources={screen.readsResources}
            onPrevious={() => update({ date: addDays(date, -step) })}
            onToday={() => update({ date: screen.today })}
            onNext={() => update({ date: addDays(date, step) })}
            weekProfessionals={screen.assigned}
            weekProfessionalId={screen.weekProfessionalId}
            onWeekProfessionalChange={(pro) => update({ pro })}
            arrivalsCount={screen.arrivals.length}
            arrivalsOpen={panel?.kind === "arrivals"}
            onToggleArrivals={() =>
              setPanel((current) => (current?.kind === "arrivals" ? null : { kind: "arrivals" }))
            }
            arrivalsPanelId={panelId}
            onNewAppointment={canCreate ? () => setPanel({ kind: "new", slot: null }) : undefined}
          />
        }
      />
      {screen.appointments.isPending &&
      isWeek &&
      !screen.weekProfessionalId &&
      screen.readsBranch ? (
        <LoadingState label={t("agenda.title")} />
      ) : (
        <QueryBoundary query={screen.appointments}>
          {() =>
            screen.columns.length === 0 && !isWeek ? (
              <p className="rounded-xl border border-dashed px-6 py-14 text-center text-muted-foreground">
                {t(screen.readsBranch ? "agenda.empty" : "agenda.emptyOwn")}
              </p>
            ) : (
              <>
                <div className="overflow-x-auto">
                  <AgendaView
                    mode={isWeek ? "week" : "day"}
                    date={date}
                    timeZone={branch.time_zone}
                    resources={screen.viewResources}
                    events={screen.events}
                    blocks={screen.blocks}
                    range={screen.range}
                    stepMinutes={screen.stepMinutes}
                    now={screen.nowLine}
                    onSelectSlot={canCreate ? (slot) => setPanel({ kind: "new", slot }) : undefined}
                    onOpenEvent={(appointmentId) => setPanel({ kind: "detail", appointmentId })}
                    onMoveEvent={moveEvent}
                  />
                </div>
                <AgendaLegend />
              </>
            )
          }
        </QueryBoundary>
      )}
      {panel?.kind === "arrivals" ? (
        <UpcomingArrivals
          id={panelId}
          arrivals={screen.arrivals}
          timeZone={branch.time_zone}
          professionalName={screen.professionalName}
          serviceLabel={screen.serviceLabel}
          onClose={closePanel}
          renderAction={arrivalAction}
        />
      ) : null}
      {panel?.kind === "new" ? (
        <NewAppointmentPanel
          key={panel.slot?.startsAt ?? "new"}
          id={panelId}
          branch={branch}
          professionals={screen.assigned}
          resources={screen.resources}
          date={date}
          slot={panel.slot}
          onClose={closePanel}
        />
      ) : null}
      {selected ? (
        <AppointmentDetailPanel
          key={selected.id}
          id={panelId}
          branch={branch}
          appointment={selected}
          professionals={screen.assigned}
          stepMinutes={screen.stepMinutes}
          professionalName={screen.professionalName}
          serviceLabel={screen.serviceLabel}
          onClose={closePanel}
        />
      ) : null}
    </>
  );
}
