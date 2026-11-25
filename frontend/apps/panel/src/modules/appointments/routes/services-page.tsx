import { formatCurrency, formatDuration, useTranslation } from "@ceiba/i18n";
import { Badge, Button, PageHeader, ToggleGroup, ToggleGroupItem, toast } from "@ceiba/ui";
import { useMemo, useState } from "react";
import { useContextBranch } from "../../../platform/context/use-context-branch";
import { useCan } from "../../../platform/permissions/can";
import {
  useArchiveService,
  useRestoreService,
  useServicesQuery,
  type Service,
  type ServiceFilter,
} from "../api/catalog";
import { useCatalogScope } from "../api/shared";
import { CatalogDetailPanel } from "../components/catalog-detail-panel";
import { EmptyState } from "../../../platform/ui/empty-state";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { CatalogHeaderActions } from "../components/catalog-header-actions";
import { ServiceDialog } from "../components/service-dialog";
import { ServicesTable } from "../components/services-table";
import { useEditingDialog } from "../lib/use-editing-dialog";
import { useEntityPanel } from "../lib/use-entity-panel";
import { ServiceOverrideSection } from "./service-override-section";

const FILTERS: readonly ServiceFilter[] = ["active", "paused", "archived"];
// Archived services can only be restored, which is managing: whoever just reads has no use for that view.
const MANAGE_ONLY_FILTERS: readonly ServiceFilter[] = ["archived"];

const statusOf = (service: Service) =>
  service.archived_at ? "archived" : service.active ? "active" : "paused";

export function ServicesPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const can = useCan();
  const canManage = can("appointments.service.manage");
  const canRead = can("appointments.service.read");
  const { currency } = useCatalogScope();
  // Under "All branches" the page shows the company's base values: overrides need one branch.
  const { branch } = useContextBranch();

  const [filter, setFilter] = useState<ServiceFilter>("active");
  const services = useServicesQuery(filter);
  const archive = useArchiveService();
  const restore = useRestoreService();

  const list = services.data?.data;
  const panel = useEntityPanel(list ?? []);
  const dialog = useEditingDialog(list ?? []);
  const { selected } = panel;
  const categories = useMemo(
    () =>
      [...new Set((list ?? []).flatMap((service) => service.category ?? []))].sort((a, b) =>
        a.localeCompare(b, "es"),
      ),
    [list],
  );

  const filters = FILTERS.filter((item) => canManage || !MANAGE_ONLY_FILTERS.includes(item));
  const archivedSelected = selected?.archived_at != null;

  const changeFilter = (next: string) => {
    setFilter(next as ServiceFilter);
    panel.close();
  };

  const archiveService = (service: Service) =>
    archive.mutate(service.id, { onSuccess: () => toast.success(t("catalog.services.archived")) });
  const restoreService = (service: Service) =>
    restore.mutate(service.id, { onSuccess: () => toast.success(t("catalog.services.restored")) });

  return (
    <>
      <PageHeader
        title={t("catalog.services.title")}
        description={t("catalog.services.description")}
        actions={
          <CatalogHeaderActions
            canManage={canManage}
            canEdit={canManage}
            newLabel={t("catalog.services.new")}
            onNew={dialog.openNew}
          />
        }
      />

      <ToggleGroup
        value={filter}
        onValueChange={changeFilter}
        aria-label={t("catalog.services.filtersLabel")}
        className="mb-4"
      >
        {filters.map((item) => (
          <ToggleGroupItem key={item} value={item}>
            {t(`catalog.services.filters.${item}`)}
          </ToggleGroupItem>
        ))}
      </ToggleGroup>

      <QueryBoundary
        query={services}
        isEmpty={(result) => result.data.length === 0}
        empty={<ServicesEmpty filter={filter} canManage={canManage} onAdd={dialog.openNew} />}
      >
        {(result) => (
          <ServicesTable
            services={result.data}
            selectedId={selected?.id ?? null}
            canManage={canManage}
            onSelect={panel.select}
            onArchive={archiveService}
            onRestore={restoreService}
          />
        )}
      </QueryBoundary>

      {selected ? (
        <CatalogDetailPanel
          id="service-panel"
          title={selected.name}
          onClose={panel.close}
          details={serviceDetails(selected, t)}
          footer={
            !canManage ? undefined : archivedSelected ? (
              <Button
                type="button"
                variant="outline"
                disabled={restore.isPending}
                onClick={() => restoreService(selected)}
              >
                {t("catalog.services.restore")}
              </Button>
            ) : (
              <Button type="button" variant="outline" onClick={() => dialog.openEdit(selected)}>
                {t("catalog.services.edit")}
              </Button>
            )
          }
        >
          {!archivedSelected && branch && canRead ? (
            <div className="border-t pt-4">
              <ServiceOverrideSection service={selected} branch={branch} />
            </div>
          ) : null}
        </CatalogDetailPanel>
      ) : null}

      {canManage ? (
        <ServiceDialog
          open={dialog.creating || dialog.edited !== undefined}
          onOpenChange={dialog.onOpenChange}
          service={dialog.edited}
          currency={currency}
          categories={categories}
        />
      ) : null}
    </>
  );
}

function serviceDetails(service: Service, t: ReturnType<typeof useTranslation>["t"]) {
  const status = statusOf(service);
  return [
    {
      label: t("catalog.services.detail.category"),
      value: service.category ?? t("catalog.services.detail.noCategory"),
    },
    {
      label: t("catalog.services.detail.duration"),
      value: formatDuration(service.duration_minutes),
    },
    {
      label: t("catalog.services.detail.bufferBefore"),
      value: formatDuration(service.buffer_before_minutes),
    },
    {
      label: t("catalog.services.detail.bufferAfter"),
      value: formatDuration(service.buffer_after_minutes),
    },
    {
      label: t("catalog.services.detail.price"),
      value: formatCurrency(service.price_minor / 100, service.currency),
    },
    {
      label: t("catalog.services.detail.status"),
      value: (
        <Badge variant={status === "active" ? "default" : "muted"}>
          {t(`catalog.services.status.${status}`)}
        </Badge>
      ),
    },
  ];
}

function ServicesEmpty({
  filter,
  canManage,
  onAdd,
}: {
  filter: ServiceFilter;
  canManage: boolean;
  onAdd(): void;
}) {
  const { t } = useTranslation("appointments");
  if (filter === "paused") {
    return (
      <EmptyState
        title={t("catalog.services.emptyPaused.title")}
        description={t("catalog.services.emptyPaused.description")}
      />
    );
  }
  if (filter === "archived") {
    return (
      <EmptyState
        title={t("catalog.services.emptyArchived.title")}
        description={t("catalog.services.emptyArchived.description")}
      />
    );
  }
  return (
    <EmptyState
      title={t("catalog.services.empty.title")}
      description={
        canManage
          ? t("catalog.services.empty.description")
          : t("catalog.services.empty.readOnlyDescription")
      }
      action={canManage ? { label: t("catalog.services.empty.action"), onClick: onAdd } : undefined}
    />
  );
}
