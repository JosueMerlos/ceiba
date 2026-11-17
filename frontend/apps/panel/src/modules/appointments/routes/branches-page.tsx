import { useTranslation } from "@ceiba/i18n";
import {
  Badge,
  Button,
  ContextPanel,
  LoadingState,
  PageHeader,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useState } from "react";
import { Link, useNavigate } from "react-router";
import { useMe } from "../../../platform/me/me-provider";
import { Can, useCan } from "../../../platform/permissions/can";
import { AsidePortal } from "../../../platform/shell/aside-slot";
import {
  useBranchSchedulesQueries,
  useCompanyBranchesQuery,
  useCreateBranch,
} from "../api/catalog";
import { BranchForm, type BranchFormValues } from "../components/branch-form";
import { EmptyState } from "../components/empty-state";
import { QueryError } from "../components/query-error";
import { DEFAULT_TIME_ZONE } from "../lib/time-zones";

export function BranchesPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const { context } = useMe();
  const can = useCan();
  const navigate = useNavigate();
  const [creating, setCreating] = useState(false);
  const branches = useCompanyBranchesQuery();
  const create = useCreateBranch();

  const list = branches.data?.data ?? [];
  const schedules = useBranchSchedulesQueries(
    list.map((branch) => branch.id),
    { enabled: can("appointments.schedule.read") },
  );

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
            <Button type="button" onClick={() => setCreating(true)}>
              <Plus aria-hidden="true" />
              {t("catalog.branches.new")}
            </Button>
          </Can>
        }
      />

      {branches.isPending ? (
        <LoadingState label={t("common:loading")} />
      ) : branches.isError ? (
        <QueryError error={branches.error} onRetry={() => void branches.refetch()} />
      ) : list.length === 0 ? (
        <EmptyState
          title={t("catalog.branches.empty.title")}
          description={t("catalog.branches.empty.description")}
        />
      ) : (
        <Table>
          <TableHeader>
            <TableRow className="border-b">
              <TableHead>{t("catalog.branches.columns.name")}</TableHead>
              <TableHead>{t("catalog.branches.columns.timeZone")}</TableHead>
              <TableHead>{t("catalog.branches.columns.schedule")}</TableHead>
              <TableHead className="text-right">
                <span className="sr-only">{t("catalog.branches.scheduleLink")}</span>
              </TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {list.map((branch, index) => {
              const schedule = schedules[index];
              return (
                <TableRow key={branch.id}>
                  <TableCell className="font-medium">{branch.name}</TableCell>
                  <TableCell className="text-muted-foreground">{branch.time_zone}</TableCell>
                  <TableCell>
                    {schedule?.isSuccess ? (
                      schedule.data.data.length > 0 ? (
                        <Badge>{t("catalog.branches.scheduleStatus.configured")}</Badge>
                      ) : (
                        <Badge variant="muted">{t("catalog.branches.scheduleStatus.closed")}</Badge>
                      )
                    ) : null}
                  </TableCell>
                  <TableCell className="text-right">
                    <Button asChild variant="outline" size="sm">
                      <Link
                        to={`/branches/${branch.id}/schedule`}
                        aria-label={t("catalog.branches.scheduleLinkLabel", { name: branch.name })}
                      >
                        {t("catalog.branches.scheduleLink")}
                      </Link>
                    </Button>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}

      {creating ? (
        <AsidePortal>
          <ContextPanel
            id="branch-panel"
            open
            onOpenChange={(open) => (open ? undefined : setCreating(false))}
            title={t("catalog.branches.panelNewTitle")}
            closeLabel={t("catalog.closePanel")}
          >
            <BranchForm
              defaultTimeZone={context.branch?.time_zone ?? DEFAULT_TIME_ZONE}
              onSubmit={createBranch}
            />
          </ContextPanel>
        </AsidePortal>
      ) : null}
    </>
  );
}
