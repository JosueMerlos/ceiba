import { useTranslation } from "@ceiba/i18n";
import { Button, PageHeader, toast } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { Can, useCan } from "../../../platform/permissions/can";
import type { Branch } from "../api/catalog";
import {
  useArchiveResource,
  useCreateResource,
  useCreateResourceTimeOff,
  useDeleteResourceTimeOff,
  usePutResourceSchedule,
  useResourceScheduleQuery,
  useResourcesQuery,
  useResourceTimeOffsQuery,
  useUpdateResource,
  type Resource,
} from "../api/resources";
import { BranchPicker } from "../components/branch-picker";
import { CatalogAside } from "../components/catalog-aside";
import { EmptyState } from "../components/empty-state";
import { OwnerBranchSections, useOwnerAccess } from "../components/owner-sections";
import { QueryBoundary } from "../components/query-boundary";
import { ResourceForm, type ResourceFormValues } from "../components/resource-form";
import { ResourcesTable } from "../components/resources-table";
import { useEntityPanel } from "../lib/use-entity-panel";
import { useWorkingBranch } from "../lib/use-working-branch";

/** Resources belong to a branch: with none chosen (company-level manager, several branches) the page asks for one. */
export function ResourcesPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const working = useWorkingBranch();
  return (
    <>
      <PageHeader
        title={t("catalog.resources.title")}
        description={t("catalog.resources.description")}
      />
      {working.needsChoice ? (
        <BranchPicker
          branches={working.branches}
          value={working.branch?.id ?? null}
          onChange={working.choose}
        />
      ) : null}
      {working.branch ? <BranchResources branch={working.branch} /> : null}
    </>
  );
}

function BranchResources({ branch }: { branch: Branch }) {
  const { t } = useTranslation("appointments");
  const canManage = useCan()("appointments.resource.manage");

  const resources = useResourcesQuery(branch.id);
  const create = useCreateResource(branch.id);
  const update = useUpdateResource(branch.id);
  const archive = useArchiveResource(branch.id);
  const panel = useEntityPanel(resources.data?.data ?? []);
  const { selected } = panel;

  async function saveResource(values: ResourceFormValues) {
    if (selected) {
      await update.mutateAsync({ id: selected.id, body: values });
      return;
    }
    const created = await create.mutateAsync(values);
    panel.select(created.data.id);
  }

  return (
    <>
      <Can permission="appointments.resource.manage">
        <div className="mb-4">
          <Button type="button" onClick={panel.openNew}>
            <Plus aria-hidden="true" />
            {t("catalog.resources.new")}
          </Button>
        </div>
      </Can>

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
                ? { label: t("catalog.resources.empty.action"), onClick: panel.openNew }
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

      {panel.open ? (
        <CatalogAside
          id="resource-panel"
          title={selected ? selected.name : t("catalog.resources.panelNewTitle")}
          onClose={panel.close}
        >
          <ResourceForm
            key={selected ? `${selected.id}:${selected.updated_at}` : "new"}
            resource={selected}
            readOnly={!canManage}
            onSubmit={saveResource}
          />
          {selected ? <ResourceSections resource={selected} branch={branch} /> : null}
        </CatalogAside>
      ) : null}
    </>
  );
}

function ResourceSections({ resource, branch }: { resource: Resource; branch: Branch }) {
  const access = useOwnerAccess();
  const schedule = useResourceScheduleQuery(branch.id, resource.id, {
    enabled: access.scheduleRead,
  });
  const saveSchedule = usePutResourceSchedule(branch.id, resource.id);
  const timeOffs = useResourceTimeOffsQuery(branch.id, resource.id, {
    enabled: access.timeOffRead,
  });
  const create = useCreateResourceTimeOff(branch.id, resource.id);
  const remove = useDeleteResourceTimeOff(branch.id, resource.id);

  return (
    <OwnerBranchSections
      branch={branch}
      access={access}
      data={{
        schedule,
        saveSchedule,
        timeOffs,
        createTimeOff: (values) => create.mutateAsync(values),
        deleteTimeOff: (timeOff, options) => remove.mutate(timeOff.id, options),
      }}
    />
  );
}
