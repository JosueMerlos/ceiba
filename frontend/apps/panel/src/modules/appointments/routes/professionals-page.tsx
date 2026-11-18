import { useTranslation } from "@ceiba/i18n";
import { Button, PageHeader, toast } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useMemo } from "react";
import { Can, useCan } from "../../../platform/permissions/can";
import {
  useArchiveProfessional,
  useCreateProfessional,
  useProfessionalsQuery,
  type Professional,
} from "../api/professionals";
import { BranchPicker } from "../components/branch-picker";
import { CatalogAside } from "../components/catalog-aside";
import { EmptyState } from "../components/empty-state";
import { ProfessionalForm, type ProfessionalFormValues } from "../components/professional-form";
import { ProfessionalsTable } from "../components/professionals-table";
import { QueryBoundary } from "../components/query-boundary";
import { useEntityPanel } from "../lib/use-entity-panel";
import { useWorkingBranch } from "../lib/use-working-branch";
import { ProfessionalPanel } from "./professional-panel";

export function ProfessionalsPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const canManage = useCan()("appointments.professional.manage");
  const working = useWorkingBranch();

  const professionals = useProfessionalsQuery();
  const create = useCreateProfessional();
  const archive = useArchiveProfessional();
  const panel = useEntityPanel(professionals.data?.data ?? []);
  const { selected } = panel;
  const branchNames = useMemo(
    () => new Map(working.branches.map((branch) => [branch.id, branch.name])),
    [working.branches],
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
          <Can permission="appointments.professional.manage">
            <Button type="button" onClick={panel.openNew}>
              <Plus aria-hidden="true" />
              {t("catalog.professionals.new")}
            </Button>
          </Can>
        }
      />

      {working.needsChoice ? (
        <BranchPicker
          branches={working.branches}
          value={working.branch?.id ?? null}
          onChange={working.choose}
        />
      ) : null}

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
            onSelect={panel.select}
            onArchive={archiveProfessional}
          />
        )}
      </QueryBoundary>

      {panel.open ? (
        <CatalogAside
          id="professional-panel"
          title={selected ? selected.display_name : t("catalog.professionals.panelNewTitle")}
          onClose={panel.close}
        >
          {selected ? (
            <ProfessionalPanel
              professional={selected}
              branches={working.branches}
              workingBranch={working.branch}
            />
          ) : (
            <ProfessionalForm key="new" onSubmit={createProfessional} />
          )}
        </CatalogAside>
      ) : null}
    </>
  );
}
