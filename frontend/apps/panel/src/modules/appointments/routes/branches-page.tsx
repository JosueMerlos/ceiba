import { useTranslation } from "@ceiba/i18n";
import { Button, PageHeader } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useNavigate } from "react-router";
import { useMe } from "../../../platform/me/me-provider";
import { Can, useCan } from "../../../platform/permissions/can";
import {
  useBranchSchedulesQueries,
  useCompanyBranchesQuery,
  useCreateBranch,
} from "../api/catalog";
import { BranchForm, type BranchFormValues } from "../components/branch-form";
import { BranchesTable, type BranchScheduleStatus } from "../components/branches-table";
import { CatalogAside } from "../components/catalog-aside";
import { EmptyState } from "../components/empty-state";
import { QueryBoundary } from "../components/query-boundary";
import { useEntityPanel } from "../lib/use-entity-panel";
import { DEFAULT_TIME_ZONE } from "../lib/time-zones";

export function BranchesPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const { context } = useMe();
  const can = useCan();
  const navigate = useNavigate();
  const branches = useCompanyBranchesQuery();
  const create = useCreateBranch();
  const list = branches.data?.data ?? [];
  const panel = useEntityPanel(list);
  const schedules = useBranchSchedulesQueries(
    list.map((branch) => branch.id),
    { enabled: can("appointments.schedule.read") },
  );
  const scheduleStatuses = schedules.map((schedule): BranchScheduleStatus => {
    if (!schedule.isSuccess) return null;
    return schedule.data.data.length > 0 ? "configured" : "closed";
  });

  async function createBranch(values: BranchFormValues) {
    const created = await create.mutateAsync(values);
    // A branch is born without hours (closed): the next step is always to set them.
    await navigate(`/branches/${created.data.id}/schedule`);
  }

  return (
    <>
      <PageHeader
        title={t("catalog.branches.title")}
        description={t("catalog.branches.description")}
        actions={
          <Can permission="platform.branch.create">
            <Button type="button" onClick={panel.openNew}>
              <Plus aria-hidden="true" />
              {t("catalog.branches.new")}
            </Button>
          </Can>
        }
      />

      <QueryBoundary
        query={branches}
        isEmpty={(result) => result.data.length === 0}
        empty={
          <EmptyState
            title={t("catalog.branches.empty.title")}
            description={t("catalog.branches.empty.description")}
          />
        }
      >
        {(result) => <BranchesTable branches={result.data} scheduleStatuses={scheduleStatuses} />}
      </QueryBoundary>

      {panel.open ? (
        <CatalogAside
          id="branch-panel"
          title={t("catalog.branches.panelNewTitle")}
          onClose={panel.close}
        >
          <BranchForm
            defaultTimeZone={context.branch?.time_zone ?? DEFAULT_TIME_ZONE}
            onSubmit={createBranch}
          />
        </CatalogAside>
      ) : null}
    </>
  );
}
