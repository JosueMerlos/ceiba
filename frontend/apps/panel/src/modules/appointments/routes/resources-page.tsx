import { useTranslation } from "@ceiba/i18n";
import { Badge, Button, PageHeader, toast } from "@ceiba/ui";
import { ContextBranchGate } from "../../../platform/context/context-branch-gate";
import { useCan } from "../../../platform/permissions/can";
import type { Branch } from "../api/catalog";
import { resourceOwnerApi } from "../api/owners";
import { useArchiveResource, useResourcesQuery, type Resource } from "../api/resources";
import { CatalogDetailPanel } from "../components/catalog-detail-panel";
import { EmptyState } from "../../../platform/ui/empty-state";
import { OwnerBranchReadSections } from "../components/owner-sections";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { CatalogHeaderActions } from "../components/catalog-header-actions";
import {
  EditResourceDialog,
  NewResourceDialog,
  useResourceSections,
} from "../components/resource-dialog";
import { ResourcesTable } from "../components/resources-table";
import { useEditingDialog } from "../lib/use-editing-dialog";
import { useEntityPanel } from "../lib/use-entity-panel";

/** Resources belong to a branch: under "All branches" (several of them) the page asks to pick one up top. */
export function ResourcesPage() {
  const { t } = useTranslation(["appointments", "common"]);
  return (
    <ContextBranchGate
      what={t("catalog.branchScope.resources")}
      header={
        <PageHeader
          title={t("catalog.resources.title")}
          description={t("catalog.resources.description")}
        />
      }
    >
      {(branch) => <BranchResources branch={branch} />}
    </ContextBranchGate>
  );
}

function BranchResources({ branch }: { branch: Branch }) {
  const { t } = useTranslation("appointments");
  const canManage = useCan()("appointments.resource.manage");
  const canEdit = useResourceSections().length > 0;

  const resources = useResourcesQuery(branch.id);
  const archive = useArchiveResource(branch.id);
  const list = resources.data?.data ?? [];
  const panel = useEntityPanel(list);
  const { selected } = panel;
  const dialog = useEditingDialog(list);

  return (
    <>
      <PageHeader
        title={t("catalog.resources.title")}
        description={t("catalog.resources.description")}
        actions={
          <CatalogHeaderActions
            canManage={canManage}
            canEdit={canEdit}
            newLabel={t("catalog.resources.new")}
            onNew={dialog.openNew}
          />
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
                ? { label: t("catalog.resources.empty.action"), onClick: dialog.openNew }
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
              <Button type="button" variant="outline" onClick={() => dialog.openEdit(selected)}>
                {t("catalog.resources.edit")}
              </Button>
            ) : undefined
          }
        >
          <OwnerBranchReadSections
            key={selected.id}
            api={resourceOwnerApi}
            ownerId={selected.id}
            branch={branch}
          />
        </CatalogDetailPanel>
      ) : null}

      {dialog.creating ? (
        <NewResourceDialog branch={branch} onOpenChange={dialog.onOpenChange} />
      ) : null}
      {dialog.edited ? (
        <EditResourceDialog
          branch={branch}
          resource={dialog.edited}
          onOpenChange={dialog.onOpenChange}
        />
      ) : null}
    </>
  );
}
