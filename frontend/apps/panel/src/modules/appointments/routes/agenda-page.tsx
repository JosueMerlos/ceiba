import { useTranslation } from "@ceiba/i18n";
import { LoadingState, PageHeader } from "@ceiba/ui";
import { useEffect, useId, useState } from "react";
import { useContextSelection } from "../../../platform/context/context-provider";
import { useMe } from "../../../platform/me/me-provider";
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
import { useAgendaPermissions } from "../lib/agenda-permissions";
import { addDays, mondayOf, type PlainDate } from "../lib/agenda-time";
import { useAgendaScreen } from "../lib/use-agenda-screen";
import { useAgendaUrlState } from "../lib/use-agenda-url-state";
import { useMoveAppointment } from "../lib/use-move-appointment";
import { useWorkingBranch } from "../lib/use-working-branch";

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
  const permissions = useAgendaPermissions();
  const panelId = useId();
  useEffect(preloadAgendaView, []);
  // The sheet keeps one side panel at a time, and on wide screens it starts with the arrivals.
  const [panel, setPanel] = useState<SidePanel>(() =>
    window.innerWidth >= WIDE_SCREEN_PX ? { kind: "arrivals" } : null,
  );
  const closePanel = () => setPanel(null);

  const url = useAgendaUrlState(branch.time_zone, { canViewResources: permissions.readsResources });
  const { date, mode } = url;
  const isWeek = mode === "week";
  const screen = useAgendaScreen({
    branch,
    mode,
    date,
    weekProfessionalId: url.weekProfessionalId,
  });
  const moveEvent = useMoveAppointment(branch.id, {
    changesProfessional: mode === "professionals",
  });

  const step = isWeek ? 7 : 1;
  const title = isWeek
    ? t("agenda.weekTitle", { date: shortDayFormat.format(calendarDay(mondayOf(date))) })
    : t("agenda.dayTitle", { date: dayFormat.format(calendarDay(date)).replace(",", "") });
  const selected =
    panel?.kind === "detail"
      ? screen.knownAppointments.find((item) => item.id === panel.appointmentId)
      : undefined;
  const { canCreate } = permissions;
  const emptyMessage = (
    <p className="rounded-xl border border-dashed px-6 py-14 text-center text-muted-foreground">
      {t(permissions.readsBranch ? "agenda.empty" : "agenda.emptyOwn")}
    </p>
  );

  function renderAgenda() {
    if (screen.weekWithoutProfessional) {
      return screen.professionalsLoading ? (
        <LoadingState label={t("agenda.title")} />
      ) : (
        emptyMessage
      );
    }
    return (
      <QueryBoundary
        query={screen.appointments}
        isEmpty={() => !isWeek && screen.columns.length === 0}
        empty={emptyMessage}
      >
        {() => (
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
        )}
      </QueryBoundary>
    );
  }

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
            onModeChange={url.setMode}
            canViewResources={permissions.readsResources}
            onPrevious={() => url.setDate(addDays(date, -step))}
            onToday={() => url.setDate(screen.today)}
            onNext={() => url.setDate(addDays(date, step))}
            weekProfessionals={screen.assigned}
            weekProfessionalId={screen.weekProfessionalId}
            onWeekProfessionalChange={url.setWeekProfessional}
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
      {renderAgenda()}
      {panel?.kind === "arrivals" ? (
        <UpcomingArrivals
          id={panelId}
          branchId={branch.id}
          arrivals={screen.arrivals}
          timeZone={branch.time_zone}
          professionalName={screen.professionalName}
          serviceLabel={screen.serviceLabel}
          onClose={closePanel}
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
