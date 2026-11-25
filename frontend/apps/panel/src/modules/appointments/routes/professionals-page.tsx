import { useTranslation } from "@ceiba/i18n";
import { Button, PageHeader, toast } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useMemo, useState } from "react";
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
import { ProfessionalsTable } from "../components/professionals-table";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { useEntityPanel } from "../lib/use-entity-panel";
import { ReadOnlyBadge } from "../components/read-only-badge";
import { ProfessionalDetail } from "./professional-detail";

type Editing = { kind: "new" } | { kind: "edit"; id: string } | null;

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
  const [editing, setEditing] = useState<Editing>(null);
  const edited = editing?.kind === "edit" ? list.find((item) => item.id === editing.id) : undefined;
  const branchNames = useMemo(
    () => new Map(branches.map((branch) => [branch.id, branch.name])),
    [branches],
  );

  const openNew = () => setEditing({ kind: "new" });
  const closeDialog = (open: boolean) => {
    if (!open) setEditing(null);
  };

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
          canManage ? (
            <Button type="button" onClick={openNew}>
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
                ? { label: t("catalog.professionals.empty.action"), onClick: openNew }
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
              <Button
                type="button"
                variant="outline"
                onClick={() => setEditing({ kind: "edit", id: selected.id })}
              >
                {t("catalog.professionals.edit")}
              </Button>
            ) : undefined
          }
        />
      ) : null}

      {editing?.kind === "new" ? (
        <NewProfessionalDialog branches={branches} onOpenChange={closeDialog} />
      ) : null}
      {edited ? (
        <EditProfessionalDialog
          professional={edited}
          branches={branches}
          onOpenChange={closeDialog}
        />
      ) : null}
    </>
  );
}
