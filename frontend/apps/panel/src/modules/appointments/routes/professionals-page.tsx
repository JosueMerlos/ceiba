import { useTranslation } from "@ceiba/i18n";
import { Button, PageHeader, toast } from "@ceiba/ui";
import { useMemo } from "react";
import { useContextBranch } from "../../../platform/context/use-context-branch";
import { useCan } from "../../../platform/permissions/can";
import { useCompanyBranchesQuery } from "../api/catalog";
import {
  useArchiveProfessional,
  useProfessionalsQuery,
  type Professional,
} from "../api/professionals";
import { EmptyState } from "../../../platform/ui/empty-state";
import {
  EditProfessionalDialog,
  NewProfessionalDialog,
  useProfessionalSections,
} from "../components/professional-dialog";
import { ProfessionalDetail } from "../components/professional-detail";
import { ProfessionalsTable } from "../components/professionals-table";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { useEntityPanel } from "../lib/use-entity-panel";
import { CatalogHeaderActions } from "../components/catalog-header-actions";
import { useEditingDialog } from "../lib/use-editing-dialog";

export function ProfessionalsPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const canManage = useCan()("appointments.professional.manage");
  // Whoever can write no section of a professional only reads: no "Edit" in the detail.
  const canEdit = useProfessionalSections().length > 0;
  const { branch: workingBranch } = useContextBranch();
  const branchesQuery = useCompanyBranchesQuery();
  const branches = useMemo(() => branchesQuery.data?.data ?? [], [branchesQuery.data]);

  const professionals = useProfessionalsQuery();
  const list = professionals.data?.data ?? [];
  const archive = useArchiveProfessional();
  const panel = useEntityPanel(list);
  const { selected } = panel;
  const dialog = useEditingDialog(list);
  const branchNames = useMemo(
    () => new Map(branches.map((branch) => [branch.id, branch.name])),
    [branches],
  );

  const archiveProfessional = (professional: Professional) =>
    archive.mutate(professional.id, {
      onSuccess: () => toast.success(t("catalog.professionals.archived")),
    });

  return (
    <>
      <PageHeader
        title={t("catalog.professionals.title")}
        description={t("catalog.professionals.description")}
        actions={
          <CatalogHeaderActions
            canManage={canManage}
            canEdit={canEdit}
            newLabel={t("catalog.professionals.new")}
            onNew={dialog.openNew}
          />
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
                ? { label: t("catalog.professionals.empty.action"), onClick: dialog.openNew }
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

      {selected ? (
        <ProfessionalDetail
          professional={selected}
          branchNames={branchNames}
          workingBranch={workingBranch}
          onClose={panel.close}
          footer={
            canEdit ? (
              <Button type="button" variant="outline" onClick={() => dialog.openEdit(selected)}>
                {t("catalog.professionals.edit")}
              </Button>
            ) : undefined
          }
        />
      ) : null}

      {dialog.creating ? (
        <NewProfessionalDialog branches={branches} onOpenChange={dialog.onOpenChange} />
      ) : null}
      {dialog.edited ? (
        <EditProfessionalDialog
          professional={dialog.edited}
          branches={branches}
          onOpenChange={dialog.onOpenChange}
        />
      ) : null}
    </>
  );
}
