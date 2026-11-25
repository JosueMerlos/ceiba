import { useTranslation } from "@ceiba/i18n";
import { Badge, Button, PageHeader, toast } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useState } from "react";
import { ChooseBranchNotice } from "../../../platform/context/choose-branch-notice";
import { useContextBranch } from "../../../platform/context/use-context-branch";
import { useCan } from "../../../platform/permissions/can";
import type { Branch } from "../api/catalog";
import {
  useArchiveResource,
  useResourceScheduleQuery,
  useResourcesQuery,
  useResourceTimeOffsQuery,
  type Resource,
} from "../api/resources";
import { CatalogDetailPanel } from "../components/catalog-detail-panel";
import { EmptyState } from "../../../platform/ui/empty-state";
import { NO_WRITES, OwnerBranchSections, useOwnerAccess } from "../components/owner-sections";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { ReadOnlyBadge } from "../components/read-only-badge";
import {
  EditResourceDialog,
  NewResourceDialog,
  useResourceSections,
} from "../components/resource-dialog";
import { ResourcesTable } from "../components/resources-table";
import { useEntityPanel } from "../lib/use-entity-panel";

/** Resources belong to a branch: under "All branches" (several of them) the page asks to pick one up top. */
export function ResourcesPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const { branch, needsChoice } = useContextBranch();
  return (
    <>
      {needsChoice ? (
        <>
          <PageHeader
            title={t("catalog.resources.title")}
            description={t("catalog.resources.description")}
          />
          <ChooseBranchNotice what={t("catalog.branchScope.resources")} />
        </>
      ) : null}
      {branch ? <BranchResources branch={branch} /> : null}
    </>
  );
}

type Editing = { kind: "new" } | { kind: "edit"; id: string } | null;

function BranchResources({ branch }: { branch: Branch }) {
  const { t } = useTranslation("appointments");
  const canManage = useCan()("appointments.resource.manage");
  const canEdit = useResourceSections().length > 0;

  const resources = useResourcesQuery(branch.id);
  const archive = useArchiveResource(branch.id);
  const list = resources.data?.data ?? [];
  const panel = useEntityPanel(list);
  const { selected } = panel;
  const [editing, setEditing] = useState<Editing>(null);
  const edited = editing?.kind === "edit" ? list.find((item) => item.id === editing.id) : undefined;
  const openNew = () => setEditing({ kind: "new" });
  const closeDialog = (open: boolean) => {
    if (!open) setEditing(null);
  };

  return (
    <>
      <PageHeader
        title={t("catalog.resources.title")}
        description={t("catalog.resources.description")}
        actions={
          canManage ? (
            <Button type="button" onClick={openNew}>
              <Plus aria-hidden="true" />
              {t("catalog.resources.new")}
            </Button>
          ) : canEdit ? null : (
            <ReadOnlyBadge />
          )
        }
      />

      <QueryBoundary
        query={resources}
        isEmpty={(result) => result.data.length === 0}
        empty={
          <EmptyState
            title={t("catalog.resources.empty.title")}
            description={
              canManage
                ? t("catalog.resources.empty.description")
                : t("catalog.resources.empty.readOnlyDescription")
            }
            action={
              canManage
                ? { label: t("catalog.resources.empty.action"), onClick: openNew }
                : undefined
            }
          />
        }
      >
        {(result) => (
          <ResourcesTable
            resources={result.data}
            selectedId={selected?.id ?? null}
            canManage={canManage}
            onSelect={panel.select}
            onArchive={(resource: Resource) =>
              archive.mutate(resource.id, {
                onSuccess: () => toast.success(t("catalog.resources.archived")),
              })
            }
          />
        )}
      </QueryBoundary>

      {selected ? (
        <CatalogDetailPanel
          id="resource-panel"
          title={selected.name}
          onClose={panel.close}
          details={[
            {
              label: t("catalog.resources.columns.kind"),
              value: t(`catalog.resources.kinds.${selected.kind}`),
            },
            {
              label: t("catalog.resources.columns.status"),
              value: (
                <Badge variant={selected.active ? "default" : "muted"}>
                  {t(`catalog.resources.status.${selected.active ? "active" : "paused"}`)}
                </Badge>
              ),
            },
          ]}
          footer={
            canEdit ? (
              <Button
                type="button"
                variant="outline"
                onClick={() => setEditing({ kind: "edit", id: selected.id })}
              >
                {t("catalog.resources.edit")}
              </Button>
            ) : undefined
          }
        >
          <ResourceSections key={selected.id} resource={selected} branch={branch} />
        </CatalogDetailPanel>
      ) : null}

      {editing?.kind === "new" ? (
        <NewResourceDialog branch={branch} open onOpenChange={closeDialog} />
      ) : null}
      {edited ? (
        <EditResourceDialog branch={branch} resource={edited} open onOpenChange={closeDialog} />
      ) : null}
    </>
  );
}

/** Hours and absences of the resource, read only: changing them happens in the modal. */
function ResourceSections({ resource, branch }: { resource: Resource; branch: Branch }) {
  const access = useOwnerAccess();
  const schedule = useResourceScheduleQuery(branch.id, resource.id, {
    enabled: access.scheduleRead,
  });
  const timeOffs = useResourceTimeOffsQuery(branch.id, resource.id, {
    enabled: access.timeOffRead,
  });

  return (
    <OwnerBranchSections
      branch={branch}
      access={{ ...access, scheduleManage: false, timeOffManage: false }}
      data={{
        schedule,
        timeOffs,
        ...NO_WRITES,
      }}
    />
  );
}
