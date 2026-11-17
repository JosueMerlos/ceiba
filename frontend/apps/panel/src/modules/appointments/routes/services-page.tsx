import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  ContextPanel,
  LoadingState,
  PageHeader,
  ToggleGroup,
  ToggleGroupItem,
  toast,
} from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useState } from "react";
import { Can, useCan } from "../../../platform/permissions/can";
import { AsidePortal } from "../../../platform/shell/aside-slot";
import {
  useArchiveService,
  useCatalogScope,
  useCreateService,
  useRestoreService,
  useServicesQuery,
  useUpdateService,
  type Service,
  type ServiceFilter,
} from "../api/catalog";
import { BranchPicker } from "../components/branch-picker";
import { EmptyState } from "../components/empty-state";
import { QueryError } from "../components/query-error";
import { ServiceForm, type ServiceFormValues } from "../components/service-form";
import { ServicesTable } from "../components/services-table";
import { useWorkingBranch } from "../lib/use-working-branch";
import { ServiceOverrideSection } from "./service-override-section";

const FILTERS: readonly ServiceFilter[] = ["active", "paused", "archived"];

type Panel = { kind: "service"; id: string } | { kind: "new" } | null;

export function ServicesPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const can = useCan();
  const canManage = can("appointments.service.manage");
  const canRead = can("appointments.service.read");
  const { currency } = useCatalogScope();
  const working = useWorkingBranch();

  const [filter, setFilter] = useState<ServiceFilter>("active");
  const [panel, setPanel] = useState<Panel>(null);
  const services = useServicesQuery(filter);
  const create = useCreateService();
  const update = useUpdateService();
  const archive = useArchiveService();
  const restore = useRestoreService();

  const list = services.data?.data ?? [];
  const selected =
    panel?.kind === "service" ? list.find((item) => item.id === panel.id) : undefined;
  const panelOpen = panel?.kind === "new" || selected !== undefined;

  const changeFilter = (next: string) => {
    setFilter(next as ServiceFilter);
    setPanel(null);
  };

  const archiveService = (service: Service) =>
    archive.mutate(service.id, { onSuccess: () => toast.success(t("catalog.services.archived")) });
  const restoreService = (service: Service) =>
    restore.mutate(service.id, { onSuccess: () => toast.success(t("catalog.services.restored")) });

  async function saveService(values: ServiceFormValues) {
    if (selected) {
      await update.mutateAsync({ id: selected.id, body: values });
      return;
    }
    await create.mutateAsync({ ...values, buffer_before_minutes: 0, position: 0 });
    setPanel(null);
  }

  return (
    <>
      <PageHeader
        title={t("catalog.services.title")}
        description={t("catalog.services.description")}
        actions={
          <Can permission="appointments.service.manage">
            <Button type="button" onClick={() => setPanel({ kind: "new" })}>
              <Plus aria-hidden="true" />
              {t("catalog.services.new")}
            </Button>
          </Can>
        }
      />

      <ToggleGroup
        value={filter}
        onValueChange={changeFilter}
        aria-label={t("catalog.services.filtersLabel")}
        className="mb-4"
      >
        {FILTERS.map((item) => (
          <ToggleGroupItem key={item} value={item}>
            {t(`catalog.services.filters.${item}`)}
          </ToggleGroupItem>
        ))}
      </ToggleGroup>

      {working.needsChoice ? (
        <BranchPicker
          branches={working.branches}
          value={working.branch?.id ?? null}
          onChange={working.choose}
        />
      ) : null}

      {services.isPending ? (
        <LoadingState label={t("common:loading")} />
      ) : services.isError ? (
        <QueryError error={services.error} onRetry={() => void services.refetch()} />
      ) : list.length === 0 ? (
        <ServicesEmpty
          filter={filter}
          canManage={canManage}
          onAdd={() => setPanel({ kind: "new" })}
        />
      ) : (
        <ServicesTable
          services={list}
          selectedId={selected?.id ?? null}
          canManage={canManage}
          onSelect={(id) => setPanel({ kind: "service", id })}
          onArchive={archiveService}
          onRestore={restoreService}
        />
      )}

      {panelOpen ? (
        <AsidePortal>
          <ContextPanel
            id="service-panel"
            open
            onOpenChange={(open) => (open ? undefined : setPanel(null))}
            title={selected ? selected.name : t("catalog.services.panelNewTitle")}
            closeLabel={t("catalog.closePanel")}
          >
            <ServiceForm
              key={selected ? `${selected.id}:${selected.updated_at}` : "new"}
              service={selected}
              currency={selected?.currency ?? currency}
              readOnly={!canManage}
              onSubmit={saveService}
            />
            {selected && working.branch && canRead ? (
              <div className="border-t pt-4">
                <ServiceOverrideSection service={selected} branch={working.branch} />
              </div>
            ) : null}
          </ContextPanel>
        </AsidePortal>
      ) : null}
    </>
  );
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
