import { useTranslation } from "@ceiba/i18n";
import { Button, PageHeader, toast } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useMemo } from "react";
import { useContextBranch } from "../../../platform/context/use-context-branch";
import { useCan } from "../../../platform/permissions/can";
import { useCompanyBranchesQuery } from "../api/catalog";
import {
  useArchiveProfessional,
  useCreateProfessional,
  useProfessionalsQuery,
  type Professional,
} from "../api/professionals";
import { CatalogAside } from "../components/catalog-aside";
import { EmptyState } from "../../../platform/ui/empty-state";
import { ProfessionalForm, type ProfessionalFormValues } from "../components/professional-form";
import { ProfessionalsTable } from "../components/professionals-table";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { useEntityPanel } from "../lib/use-entity-panel";
import { ReadOnlyBadge } from "../components/read-only-badge";
import { ProfessionalDetail } from "./professional-detail";
import { ProfessionalPanel } from "./professional-panel";

export function ProfessionalsPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const can = useCan();
  const canManage = can("appointments.professional.manage");
  // Whoever can change nothing of a professional gets the read view, not the editing panel.
  const canEdit =
    canManage ||
    can("appointments.professional.assign") ||
    can("appointments.schedule.manage") ||
    can("appointments.time_off.manage");
  const { branch: workingBranch } = useContextBranch();
  const branchesQuery = useCompanyBranchesQuery();
  const branches = useMemo(() => branchesQuery.data?.data ?? [], [branchesQuery.data]);

  const professionals = useProfessionalsQuery();
  const create = useCreateProfessional();
  const archive = useArchiveProfessional();
  const panel = useEntityPanel(professionals.data?.data ?? []);
  const { selected } = panel;
  const branchNames = useMemo(
    () => new Map(branches.map((branch) => [branch.id, branch.name])),
    [branches],
  );

  const archiveProfessional = (professional: Professional) =>
    archive.mutate(professional.id, {
      onSuccess: () => toast.success(t("catalog.professionals.archived")),
    });

  async function createProfessional(values: ProfessionalFormValues) {
    const created = await create.mutateAsync(values);
    // The new professional has no branch yet: open their panel so the next step (services, branch) is right there.
    panel.select(created.data.id);
  }

  return (
    <>
      <PageHeader
        title={t("catalog.professionals.title")}
        description={t("catalog.professionals.description")}
        actions={
          canManage ? (
            <Button type="button" onClick={panel.openNew}>
              <Plus aria-hidden="true" />
              {t("catalog.professionals.new")}
            </Button>
          ) : canEdit ? null : (
            <ReadOnlyBadge />
          )
        }
      />

      <QueryBoundary
        query={professionals}
        isEmpty={(result) => result.data.length === 0}
        empty={
          <EmptyState
            title={t("catalog.professionals.empty.title")}
            description={
              canManage
                ? t("catalog.professionals.empty.description")
                : t("catalog.professionals.empty.readOnlyDescription")
            }
            action={
              canManage
                ? { label: t("catalog.professionals.empty.action"), onClick: panel.openNew }
                : undefined
            }
          />
        }
      >
        {(result) => (
          <ProfessionalsTable
            professionals={result.data}
            branchNames={branchNames}
            selectedId={selected?.id ?? null}
            canManage={canManage}
            canEdit={canEdit}
            onSelect={panel.select}
            onArchive={archiveProfessional}
          />
        )}
      </QueryBoundary>

      {selected && !canEdit ? (
        <ProfessionalDetail
          professional={selected}
          branchNames={branchNames}
          workingBranch={workingBranch}
          onClose={panel.close}
        />
      ) : null}

      {panel.open && (canEdit || panel.isNew) ? (
        <CatalogAside
          id="professional-panel"
          title={selected ? selected.display_name : t("catalog.professionals.panelNewTitle")}
          onClose={panel.close}
        >
          {selected ? (
            <ProfessionalPanel
              professional={selected}
              branches={branches}
              workingBranch={workingBranch}
            />
          ) : (
            <ProfessionalForm key="new" onSubmit={createProfessional} />
          )}
        </CatalogAside>
      ) : null}
    </>
  );
}
