import { useTranslation } from "@ceiba/i18n";
import { Button, ContextPanel, LoadingState, PageHeader, toast } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { useMemo, useState } from "react";
import { Can, useCan } from "../../../platform/permissions/can";
import { AsidePortal } from "../../../platform/shell/aside-slot";
import {
  useArchiveProfessional,
  useCreateProfessional,
  useProfessionalsQuery,
  type Professional,
} from "../api/professionals";
import { BranchPicker } from "../components/branch-picker";
import { EmptyState } from "../components/empty-state";
import { ProfessionalForm, type ProfessionalFormValues } from "../components/professional-form";
import { ProfessionalsTable } from "../components/professionals-table";
import { QueryError } from "../components/query-error";
import { useWorkingBranch } from "../lib/use-working-branch";
import { ProfessionalPanel } from "./professional-panel";

type Panel = { kind: "professional"; id: string } | { kind: "new" } | null;

export function ProfessionalsPage() {
  const { t } = useTranslation(["appointments", "common"]);
  const canManage = useCan()("appointments.professional.manage");
  const working = useWorkingBranch();

  const [panel, setPanel] = useState<Panel>(null);
  const professionals = useProfessionalsQuery();
  const create = useCreateProfessional();
  const archive = useArchiveProfessional();

  const list = professionals.data?.data ?? [];
  const selected =
    panel?.kind === "professional" ? list.find((item) => item.id === panel.id) : undefined;
  const panelOpen = panel?.kind === "new" || selected !== undefined;
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
    setPanel({ kind: "professional", id: created.data.id });
  }

  return (
    <>
      <PageHeader
        title={t("catalog.professionals.title")}
        description={t("catalog.professionals.description")}
        actions={
          <Can permission="appointments.professional.manage">
            <Button type="button" onClick={() => setPanel({ kind: "new" })}>
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

      {professionals.isPending ? (
        <LoadingState label={t("common:loading")} />
      ) : professionals.isError ? (
        <QueryError error={professionals.error} onRetry={() => void professionals.refetch()} />
      ) : list.length === 0 ? (
        <EmptyState
          title={t("catalog.professionals.empty.title")}
          description={
            canManage
              ? t("catalog.professionals.empty.description")
              : t("catalog.professionals.empty.readOnlyDescription")
          }
          action={
            canManage
              ? {
                  label: t("catalog.professionals.empty.action"),
                  onClick: () => setPanel({ kind: "new" }),
                }
              : undefined
          }
        />
      ) : (
        <ProfessionalsTable
          professionals={list}
          branchNames={branchNames}
          selectedId={selected?.id ?? null}
          canManage={canManage}
          onSelect={(id) => setPanel({ kind: "professional", id })}
          onArchive={archiveProfessional}
        />
      )}

      {panelOpen ? (
        <AsidePortal>
          <ContextPanel
            id="professional-panel"
            open
            onOpenChange={(open) => (open ? undefined : setPanel(null))}
            title={selected ? selected.display_name : t("catalog.professionals.panelNewTitle")}
            closeLabel={t("catalog.closePanel")}
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
          </ContextPanel>
        </AsidePortal>
      ) : null}
    </>
  );
}
