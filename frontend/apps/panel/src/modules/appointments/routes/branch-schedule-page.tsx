import { useTranslation } from "@ceiba/i18n";
import { PageHeader } from "@ceiba/ui";
import { ArrowLeft } from "lucide-react";
import { Link, useParams } from "react-router";
import { NotFoundPage } from "../../../platform/errors/status-pages";
import { useCan } from "../../../platform/permissions/can";
import {
  useBranchScheduleQuery,
  useCompanyBranchesQuery,
  usePutBranchSchedule,
} from "../api/catalog";
import { EmptyState } from "../../../platform/ui/empty-state";
import { ScheduleSection } from "../components/owner-sections";
import { QueryBoundary } from "../../../platform/ui/query-boundary";

export function BranchSchedulePage() {
  const { branchId } = useParams();
  const branches = useCompanyBranchesQuery();

  return (
    <QueryBoundary query={branches}>
      {({ data: list }) => {
        // The branch must belong to the working company: any other id is "not found", like the API would answer.
        const branch = list.find((item) => item.id === branchId);
        if (!branch) return <NotFoundPage />;
        return (
          <BranchScheduleScreen
            branchId={branch.id}
            branchName={branch.name}
            timeZone={branch.time_zone}
          />
        );
      }}
    </QueryBoundary>
  );
}

function BranchScheduleScreen({
  branchId,
  branchName,
  timeZone,
}: {
  branchId: string;
  branchName: string;
  timeZone: string;
}) {
  const { t } = useTranslation("appointments");
  const canManage = useCan()("appointments.schedule.manage");
  const schedule = useBranchScheduleQuery(branchId);
  const put = usePutBranchSchedule(branchId);

  return (
    <>
      <PageHeader
        title={t("catalog.branchSchedule.title", { branch: branchName })}
        description={t("catalog.schedule.description", { branch: branchName, timeZone })}
        actions={
          <Link
            to="/branches"
            className="inline-flex items-center gap-1.5 text-sm font-medium text-muted-foreground hover:text-foreground"
          >
            <ArrowLeft className="size-4" aria-hidden="true" />
            {t("catalog.branchSchedule.back")}
          </Link>
        }
      />

      <div className="grid gap-6">
        {schedule.isSuccess && schedule.data.data.length === 0 ? (
          <EmptyState
            title={t("catalog.branchSchedule.empty.title")}
            description={t("catalog.branchSchedule.empty.description")}
          />
        ) : null}
        <ScheduleSection slots={schedule} save={put} canManage={canManage} />
      </div>
    </>
  );
}
