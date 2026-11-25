import { useTranslation } from "@ceiba/i18n";
import { LoadingState, PageBody, PageFrame, PageHeader } from "@ceiba/ui";
import { useEffect, useId, useMemo, useState } from "react";
import { ContextBranchGate } from "../../../platform/context/context-branch-gate";
import { useMe } from "../../../platform/me/me-provider";
import type { Branch } from "../api/catalog";
import { AppointmentDetailPanel } from "../components/agenda/appointment-detail-panel";
import { NewAppointmentPanel } from "../components/agenda/new-appointment-panel";
import { AgendaDateTitle } from "../components/agenda-date-title";
import { AgendaDayFilters } from "../components/agenda-day-filters";
import { AgendaToolbar, WeekProfessionalPicker } from "../components/agenda-toolbar";
import { AgendaView, preloadAgendaView } from "../components/agenda-view/agenda-view";
import { AgendaDensityContext } from "../components/agenda-view/density";
import { useNarrowScreen } from "../components/agenda-view/use-narrow-screen";
import type { AgendaSlot } from "../components/agenda-view/types";
import { NewAppointmentFab } from "../components/new-appointment-fab";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { UpcomingArrivals } from "../components/upcoming-arrivals";
import { useAgendaDensity } from "../lib/use-agenda-density";
import { useAgendaPermissions } from "../lib/agenda-permissions";
import { addDays, mondayOf } from "../lib/agenda-time";
import { newAppointmentDefaults } from "../lib/new-appointment-defaults";
import { useAgendaScreen } from "../lib/use-agenda-screen";
import { useAgendaUrlState } from "../lib/use-agenda-url-state";
import { useMoveAppointment } from "../lib/use-move-appointment";
import { useStatusFilter } from "../lib/use-status-filter";

// The date is a calendar day, so it is formatted in UTC: no zone may move it to the neighboring day.
const shortDayFormat = new Intl.DateTimeFormat("es-NI", {
  day: "numeric",
  month: "long",
  timeZone: "UTC",
});

const canCreateFromSlot = (canCreate: boolean, narrow: boolean, mode: string) =>
  canCreate && !(narrow && mode === "resources");

type SidePanel =
  | { kind: "arrivals" }
  | { kind: "new"; slot: AgendaSlot | null }
  | { kind: "detail"; appointmentId: string }
  | null;

export function AgendaPage() {
  const { t } = useTranslation("appointments");
  // The branch comes only from the global selector: /me's permissions depend on the context's branch.
  return (
    <ContextBranchGate
      what={t("catalog.branchScope.agenda")}
      header={<PageHeader title={t("agenda.title")} />}
    >
      {(branch) => <BranchAgenda key={branch.id} branch={branch} />}
    </ContextBranchGate>
  );
}

function BranchAgenda({ branch }: { branch: Branch }) {
  const { t } = useTranslation("appointments");
  const { principal } = useMe();
  const permissions = useAgendaPermissions();
  const panelId = useId();
  // A phone draws the list: no calendar library, no density, and New appointment floats.
  const narrow = useNarrowScreen();
  useEffect(() => {
    if (!narrow) preloadAgendaView();
  }, [narrow]);
  // One side panel at a time. It floats over the agenda, so it only opens when asked for.
  const [panel, setPanel] = useState<SidePanel>(null);
  const closePanel = () => setPanel(null);
  const openNew = () => setPanel({ kind: "new", slot: null });
  const [density, setDensity] = useAgendaDensity(principal.id);

  const url = useAgendaUrlState(branch.time_zone, { canViewResources: permissions.readsResources });
  const { date, mode } = url;
  const isWeek = mode === "week";
  const screen = useAgendaScreen({
    branch,
    mode,
    date,
    weekProfessionalId: url.weekProfessionalId,
    offersFreeGaps: narrow,
  });
  const filter = useStatusFilter(screen.events, !isWeek);
  // The phone list offers free gaps: what the chips hide is still taken there.
  const blocks = useMemo(
    () => (narrow ? [...screen.blocks, ...filter.hiddenBusy] : screen.blocks),
    [narrow, screen.blocks, filter.hiddenBusy],
  );
  // A gap tapped on a phone books with the person whose list it is; a resource's gap names no one to book with.
  const booksFromSlot = canCreateFromSlot(permissions.canCreate, narrow, mode);
  const moveEvent = useMoveAppointment(branch.id, {
    changesProfessional: mode === "professionals",
  });

  const step = isWeek ? 7 : 1;
  const title = isWeek ? (
    t("agenda.weekTitle", {
      date: shortDayFormat.format(new Date(`${mondayOf(date)}T12:00:00Z`)),
    })
  ) : (
    <AgendaDateTitle date={date} today={screen.today} onChange={url.setDate} />
  );
  const selected =
    panel?.kind === "detail"
      ? screen.knownAppointments.find((item) => item.id === panel.appointmentId)
      : undefined;
  const { canCreate } = permissions;
  const newAppointment =
    panel?.kind === "new"
      ? newAppointmentDefaults({
          mode,
          slot: panel.slot,
          weekProfessionalId: screen.weekProfessionalId,
          professionals: screen.bookable,
        })
      : null;
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
          <div className="h-full overflow-hidden rounded-xl border">
            <AgendaDensityContext.Provider value={density}>
              <AgendaView
                mode={isWeek ? "week" : "day"}
                date={date}
                timeZone={branch.time_zone}
                resources={screen.viewResources}
                events={filter.shown}
                blocks={blocks}
                range={screen.range}
                stepMinutes={screen.stepMinutes}
                now={screen.nowLine}
                onSelectSlot={booksFromSlot ? (slot) => setPanel({ kind: "new", slot }) : undefined}
                onOpenEvent={(appointmentId) => setPanel({ kind: "detail", appointmentId })}
                onMoveEvent={moveEvent}
              />
            </AgendaDensityContext.Provider>
          </div>
        )}
      </QueryBoundary>
    );
  }

  return (
    <PageFrame>
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
            arrivalsCount={screen.arrivals.length}
            arrivalsOpen={panel?.kind === "arrivals"}
            onToggleArrivals={() =>
              setPanel((current) => (current?.kind === "arrivals" ? null : { kind: "arrivals" }))
            }
            arrivalsPanelId={panelId}
            onNewAppointment={canCreate && !narrow ? openNew : undefined}
          />
        }
      />
      {isWeek ? (
        <WeekProfessionalPicker
          professionals={screen.assigned}
          value={screen.weekProfessionalId}
          onChange={url.setWeekProfessional}
        />
      ) : (
        <AgendaDayFilters
          filter={filter}
          density={narrow ? null : density}
          onDensityChange={setDensity}
        />
      )}
      <PageBody className="overflow-hidden">{renderAgenda()}</PageBody>
      {narrow && canCreate ? <NewAppointmentFab onClick={openNew} /> : null}
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
      {panel?.kind === "new" && newAppointment ? (
        <NewAppointmentPanel
          key={newAppointment.key}
          id={panelId}
          branch={branch}
          professionals={screen.bookable}
          initialProfessionalId={newAppointment.professionalId}
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
          professionals={screen.bookable}
          professionalName={screen.professionalName}
          serviceLabel={screen.serviceLabel}
          onClose={closePanel}
        />
      ) : null}
    </PageFrame>
  );
}
