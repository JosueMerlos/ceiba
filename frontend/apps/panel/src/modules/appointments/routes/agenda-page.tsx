import { useTranslation } from "@ceiba/i18n";
import { LoadingState, PageHeader } from "@ceiba/ui";
import { useId, useState } from "react";
import { useSearchParams } from "react-router";
import { useContextSelection } from "../../../platform/context/context-provider";
import { useMe } from "../../../platform/me/me-provider";
import { useCan } from "../../../platform/permissions/can";
import type { Branch } from "../api/catalog";
import { AgendaLegend } from "../components/agenda-legend";
import { AgendaToolbar } from "../components/agenda-toolbar";
import { AgendaView } from "../components/agenda-view/agenda-view";
import { BranchPicker } from "../components/branch-picker";
import { QueryBoundary } from "../components/query-boundary";
import { UpcomingArrivals } from "../components/upcoming-arrivals";
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
  const arrivalsPanelId = useId();
  const [params, setParams] = useSearchParams();
  const [arrivalsOpen, setArrivalsOpen] = useState(() => window.innerWidth >= WIDE_SCREEN_PX);

  const requestedDate = params.get("date");
  const date =
    requestedDate && PLAIN_DATE.test(requestedDate) ? requestedDate : todayInZone(branch.time_zone);
  const requestedMode = params.get("view") as AgendaMode | null;
  const mode: AgendaMode =
    requestedMode && MODES.includes(requestedMode) ? requestedMode : "professionals";

  const screen = useAgendaScreen({ branch, mode, date, weekProfessionalId: params.get("pro") });
  const isWeek = mode === "week";

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
            arrivalsOpen={arrivalsOpen}
            onToggleArrivals={() => setArrivalsOpen((open) => !open)}
            arrivalsPanelId={arrivalsPanelId}
            onNewAppointment={can("appointments.appointment.create") ? () => {} : undefined}
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
                  />
                </div>
                <AgendaLegend />
              </>
            )
          }
        </QueryBoundary>
      )}
      {arrivalsOpen ? (
        <UpcomingArrivals
          id={arrivalsPanelId}
          arrivals={screen.arrivals}
          timeZone={branch.time_zone}
          professionalName={screen.professionalName}
          serviceLabel={screen.serviceLabel}
          onClose={() => setArrivalsOpen(false)}
        />
      ) : null}
    </>
  );
}
