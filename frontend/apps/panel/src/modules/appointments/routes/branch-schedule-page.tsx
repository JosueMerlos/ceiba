import { isApiError } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import { LoadingState, PageHeader, toast } from "@ceiba/ui";
import { ArrowLeft } from "lucide-react";
import { useState } from "react";
import { Link, useParams } from "react-router";
import { describeError } from "../../../platform/errors/global-errors";
import { NotFoundPage } from "../../../platform/errors/status-pages";
import { useCan } from "../../../platform/permissions/can";
import {
  useBranchScheduleQuery,
  useCompanyBranchesQuery,
  usePutBranchSchedule,
} from "../api/catalog";
import { EmptyState } from "../components/empty-state";
import { QueryError } from "../components/query-error";
import { WeeklyScheduleEditor } from "../components/weekly-schedule-editor";

export function BranchSchedulePage() {
  const { branchId } = useParams();
  const branches = useCompanyBranchesQuery();
  const { t } = useTranslation(["appointments", "common"]);

  if (branches.isPending) return <LoadingState label={t("common:loading")} />;
  if (branches.isError) {
    return <QueryError error={branches.error} onRetry={() => void branches.refetch()} />;
  }
  // The branch must belong to the working company: any other id is "not found", like the API would answer.
  const branch = branches.data.data.find((item) => item.id === branchId);
  if (!branch) return <NotFoundPage />;
  return (
    <BranchScheduleScreen
      branchId={branch.id}
      branchName={branch.name}
      timeZone={branch.time_zone}
    />
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
  const { t } = useTranslation(["appointments", "common", "errors"]);
  const canManage = useCan()("appointments.schedule.manage");
  const schedule = useBranchScheduleQuery(branchId);
  const put = usePutBranchSchedule(branchId);
  const [serverMessages, setServerMessages] = useState<string[]>([]);

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

      {schedule.isPending ? (
        <LoadingState label={t("common:loading")} />
      ) : schedule.isError ? (
        <QueryError error={schedule.error} onRetry={() => void schedule.refetch()} />
      ) : (
        <div className="grid gap-6">
          {schedule.data.data.length === 0 ? (
            <EmptyState
              title={t("catalog.branchSchedule.empty.title")}
              description={t("catalog.branchSchedule.empty.description")}
            />
          ) : null}
          <WeeklyScheduleEditor
            key={schedule.data.data.map((slot) => slot.id).join(",")}
            slots={schedule.data.data}
            readOnly={!canManage}
            saving={put.isPending}
            serverMessages={serverMessages}
            onSave={(payload) =>
              put.mutate(payload, {
                onSuccess: () => {
                  setServerMessages([]);
                  toast.success(t("catalog.schedule.saved"));
                },
                onError: (error) =>
                  setServerMessages(
                    isApiError(error) && error.status === 422
                      ? error.errors.length > 0
                        ? error.errors.map((item) => item.message)
                        : [error.title]
                      : [describeError(error, t)],
                  ),
              })
            }
          />
        </div>
      )}
    </>
  );
}
