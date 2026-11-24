import { useTranslation } from "@ceiba/i18n";
import {
  DatePicker,
  LoadingState,
  PageBody,
  PageFrame,
  PageHeader,
  ToggleGroup,
  ToggleGroupItem,
} from "@ceiba/ui";
import { Rows2, Rows4 } from "lucide-react";
import { useEffect, useId, useMemo, useState } from "react";
import { useContextSelection } from "../../../platform/context/context-provider";
import { useMe } from "../../../platform/me/me-provider";
import type { Branch } from "../api/catalog";
import { AppointmentDetailPanel } from "../components/agenda/appointment-detail-panel";
import { NewAppointmentPanel } from "../components/agenda/new-appointment-panel";
import { AgendaStatusChips, CHIP_TONES } from "../components/agenda-status-chips";
import { AgendaToolbar } from "../components/agenda-toolbar";
import { AgendaView, preloadAgendaView } from "../components/agenda-view/agenda-view";
import { AgendaDensityContext } from "../components/agenda-view/density";
import type { AgendaSlot } from "../components/agenda-view/types";
import { BranchPicker } from "../components/branch-picker";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { UpcomingArrivals } from "../components/upcoming-arrivals";
import { useAgendaDensity } from "../lib/use-agenda-density";
import { useAgendaPermissions } from "../lib/agenda-permissions";
import type { StatusTone } from "../lib/agenda-status";
import { addDays, mondayOf, type PlainDate } from "../lib/agenda-time";
import { newAppointmentDefaults } from "../lib/new-appointment-defaults";
import { useAgendaScreen } from "../lib/use-agenda-screen";
import { useAgendaUrlState } from "../lib/use-agenda-url-state";
import { useMoveAppointment } from "../lib/use-move-appointment";
import { useWorkingBranch } from "../lib/use-working-branch";

const calendarDay = (day: PlainDate) => new Date(`${day}T12:00:00Z`);

// The date is a calendar day, so it is formatted in UTC: no zone may move it to the neighboring day.
const dayFormat = new Intl.DateTimeFormat("es-NI", {
  weekday: "long",
  day: "numeric",
  month: "long",
  timeZone: "UTC",
});
const longDay = (day: PlainDate) => dayFormat.format(calendarDay(day)).replace(",", "");
const shortDayFormat = new Intl.DateTimeFormat("es-NI", {
  day: "numeric",
  month: "long",
  timeZone: "UTC",
});

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

const NO_TONES: ReadonlySet<StatusTone> = new Set();

function BranchAgenda({ branch }: { branch: Branch }) {
  const { t } = useTranslation(["appointments", "common"]);
  const { principal } = useMe();
  const permissions = useAgendaPermissions();
  const panelId = useId();
  useEffect(preloadAgendaView, []);
  // One side panel at a time. It floats over the agenda, so it only opens when asked for.
  const [panel, setPanel] = useState<SidePanel>(null);
  const closePanel = () => setPanel(null);
  const [density, setDensity] = useAgendaDensity(principal.id);
  // The statuses switched off with the chips; a filter of the screen, not of the data.
  const [hidden, setHidden] = useState(NO_TONES);

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

  const toneCounts = useMemo(() => {
    const counts = Object.fromEntries(CHIP_TONES.map((tone) => [tone, 0])) as Record<
      StatusTone,
      number
    >;
    for (const event of screen.events) counts[event.tone] += 1;
    return counts;
  }, [screen.events]);
  const shownEvents = useMemo(
    () =>
      isWeek || hidden.size === 0
        ? screen.events
        : screen.events.filter((event) => !hidden.has(event.tone)),
    [isWeek, hidden, screen.events],
  );
  function toggleTone(tone: StatusTone) {
    setHidden((current) => {
      const next = new Set(current);
      if (!next.delete(tone)) next.add(tone);
      return next;
    });
  }

  const step = isWeek ? 7 : 1;
  const title = isWeek ? (
    t("agenda.weekTitle", { date: shortDayFormat.format(calendarDay(mondayOf(date))) })
  ) : (
    <>
      <span className="sr-only">{t("agenda.dayTitlePrefix")} </span>
      <DatePicker
        value={date}
        onChange={(day) => {
          if (day) url.setDate(day);
        }}
        today={screen.today}
        formatDate={longDay}
        placeholder={t("agenda.chooseDay")}
        calendarLabel={t("common:fields.calendar")}
        previousMonthLabel={t("common:fields.previousMonth")}
        nextMonthLabel={t("common:fields.nextMonth")}
        loadErrorLabel={t("common:fields.calendarError")}
        retryLabel={t("common:retry")}
        className="-ml-2 h-auto w-auto max-w-full gap-2 border-0 bg-transparent px-2 py-0.5 font-display text-[length:inherit] font-[inherit] shadow-none hover:bg-muted md:text-[length:inherit] [&>span]:overflow-visible [&>span]:first-letter:uppercase [&>svg]:size-5"
      />
    </>
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
                events={shownEvents}
                blocks={screen.blocks}
                range={screen.range}
                stepMinutes={screen.stepMinutes}
                now={screen.nowLine}
                onSelectSlot={canCreate ? (slot) => setPanel({ kind: "new", slot }) : undefined}
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
      {isWeek ? null : (
        <div className="-mt-2 mb-3 flex flex-wrap items-center gap-2">
          <AgendaStatusChips
            counts={toneCounts}
            hidden={hidden}
            onToggle={toggleTone}
            onShowAll={() => setHidden(NO_TONES)}
          />
          <ToggleGroup
            value={density}
            onValueChange={(value) => {
              if (value === "comfortable" || value === "compact") setDensity(value);
            }}
            aria-label={t("agenda.density.label")}
            className="ml-auto flex-nowrap gap-0.5 rounded-[var(--button-radius)] bg-sidebar p-0.5"
          >
            <ToggleGroupItem
              value="comfortable"
              aria-label={t("agenda.density.comfortable")}
              title={t("agenda.density.comfortable")}
              className={DENSITY_ITEM}
            >
              <Rows2 aria-hidden="true" />
            </ToggleGroupItem>
            <ToggleGroupItem
              value="compact"
              aria-label={t("agenda.density.compact")}
              title={t("agenda.density.compact")}
              className={DENSITY_ITEM}
            >
              <Rows4 aria-hidden="true" />
            </ToggleGroupItem>
          </ToggleGroup>
        </div>
      )}
      <PageBody className="overflow-hidden">{renderAgenda()}</PageBody>
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

const DENSITY_ITEM =
  "size-8 justify-center rounded-[calc(var(--button-radius)-2px)] border-0 bg-transparent p-0 text-muted-foreground data-[state=on]:bg-background data-[state=on]:text-foreground data-[state=on]:shadow-xs [&_svg]:size-4";
