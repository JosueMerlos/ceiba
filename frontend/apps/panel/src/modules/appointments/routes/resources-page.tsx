import { useTranslation } from "@ceiba/i18n";
import { Button, ContextPanel, LoadingState, PageHeader, toast } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useState } from "react";
import { Can, useCan } from "../../../platform/permissions/can";
import { AsidePortal } from "../../../platform/shell/aside-slot";
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
import { EmptyState } from "../components/empty-state";
import { QueryError } from "../components/query-error";
import { ResourceForm, type ResourceFormValues } from "../components/resource-form";
import { ResourcesTable } from "../components/resources-table";
import { useWorkingBranch } from "../lib/use-working-branch";
import { PanelSection, ScheduleSection, TimeOffsSection } from "./owner-sections";

type Panel = { kind: "resource"; id: string } | { kind: "new" } | null;

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
  const { t } = useTranslation(["appointments", "common"]);
  const can = useCan();
  const canManage = can("appointments.resource.manage");

  const [panel, setPanel] = useState<Panel>(null);
  const resources = useResourcesQuery(branch.id);
  const create = useCreateResource(branch.id);
  const update = useUpdateResource(branch.id);
  const archive = useArchiveResource(branch.id);

  const list = resources.data?.data ?? [];
  const selected =
    panel?.kind === "resource" ? list.find((item) => item.id === panel.id) : undefined;
  const panelOpen = panel?.kind === "new" || selected !== undefined;

  async function saveResource(values: ResourceFormValues) {
    if (selected) {
      await update.mutateAsync({ id: selected.id, body: values });
      return;
    }
    const created = await create.mutateAsync(values);
    setPanel({ kind: "resource", id: created.data.id });
  }

  return (
    <>
      <Can permission="appointments.resource.manage">
        <div className="mb-4">
          <Button type="button" onClick={() => setPanel({ kind: "new" })}>
            <Plus aria-hidden="true" />
            {t("catalog.resources.new")}
          </Button>
        </div>
      </Can>

      {resources.isPending ? (
        <LoadingState label={t("common:loading")} />
      ) : resources.isError ? (
        <QueryError error={resources.error} onRetry={() => void resources.refetch()} />
      ) : list.length === 0 ? (
        <EmptyState
          title={t("catalog.resources.empty.title")}
          description={
            canManage
              ? t("catalog.resources.empty.description")
              : t("catalog.resources.empty.readOnlyDescription")
          }
          action={
            canManage
              ? {
                  label: t("catalog.resources.empty.action"),
                  onClick: () => setPanel({ kind: "new" }),
                }
              : undefined
          }
        />
      ) : (
        <ResourcesTable
          resources={list}
          selectedId={selected?.id ?? null}
          canManage={canManage}
          onSelect={(id) => setPanel({ kind: "resource", id })}
          onArchive={(resource: Resource) =>
            archive.mutate(resource.id, {
              onSuccess: () => toast.success(t("catalog.resources.archived")),
            })
          }
        />
      )}

      {panelOpen ? (
        <AsidePortal>
          <ContextPanel
            id="resource-panel"
            open
            onOpenChange={(open) => (open ? undefined : setPanel(null))}
            title={selected ? selected.name : t("catalog.resources.panelNewTitle")}
            closeLabel={t("catalog.closePanel")}
          >
            <ResourceForm
              key={selected ? `${selected.id}:${selected.updated_at}` : "new"}
              resource={selected}
              readOnly={!canManage}
              onSubmit={saveResource}
            />
            {selected ? <ResourceSections resource={selected} branch={branch} /> : null}
          </ContextPanel>
        </AsidePortal>
      ) : null}
    </>
  );
}

function ResourceSections({ resource, branch }: { resource: Resource; branch: Branch }) {
  const { t } = useTranslation("appointments");
  const can = useCan();
  const canScheduleRead = can("appointments.schedule.read");
  const canScheduleManage = can("appointments.schedule.manage");
  const canTimeOffRead = can("appointments.time_off.read");
  const canTimeOffManage = can("appointments.time_off.manage");

  const schedule = useResourceScheduleQuery(branch.id, resource.id);
  const save = usePutResourceSchedule(branch.id, resource.id);
  const timeOffs = useResourceTimeOffsQuery(branch.id, resource.id);
  const create = useCreateResourceTimeOff(branch.id, resource.id);
  const remove = useDeleteResourceTimeOff(branch.id, resource.id);

  return (
    <>
      {canScheduleRead ? (
        <PanelSection
          title={t("catalog.schedule.title")}
          description={t("catalog.timeOffs.branchHint", {
            branch: branch.name,
            timeZone: branch.time_zone,
          })}
        >
          <ScheduleSection slots={schedule} save={save} canManage={canScheduleManage} />
        </PanelSection>
      ) : null}
      {canTimeOffRead ? (
        <PanelSection title={t("catalog.timeOffs.title")}>
          <TimeOffsSection
            timeOffs={timeOffs}
            timeZone={branch.time_zone}
            canManage={canTimeOffManage}
            onCreate={(values) => create.mutateAsync(values)}
            onDelete={(timeOff, options) => remove.mutate(timeOff.id, options)}
          />
        </PanelSection>
      ) : null}
    </>
  );
}
