import { useTranslation } from "@ceiba/i18n";
import { toast } from "@ceiba/ui";
import { useState } from "react";
import { useCan } from "../../../platform/permissions/can";
import type { Branch } from "../api/catalog";
import { useProfessionalAssignment, type Professional } from "../api/professionals";
import { useOrphanTimeOffs, type AssignConfirmation } from "../lib/use-orphan-time-offs";
import { AssignBranchDialog } from "./assign-branch-dialog";
import { BranchSwitcher } from "./branch-switcher";
import { PanelSection, useOwnerAccess } from "./owner-sections";
import { OwnerScheduleTab } from "./owner-tabs";
import type { ProfessionalBranchTab } from "./professional-branch-tab";
import { ProfessionalBranches } from "./professional-branches";

interface ProfessionalScheduleTabProps {
  professional: Professional;
  /** Branches the user can see: a branch manager receives only theirs. */
  branches: readonly Branch[];
  branchTab: ProfessionalBranchTab;
  /** The modal's unsaved state: switching branch with changes asks first. */
  dirty: boolean;
  /** The modal footer's form: it saves the weekly hours of the branch on screen. */
  formId: string;
  onDirtyChange(dirty: boolean): void;
  onSaved?(): void;
}

/**
 * Where the professional works and their weekly hours there. The branch checkboxes apply at once (they are not part of
 * the footer's save); the footer saves the hours of the branch picked in the chips.
 */
export function ProfessionalScheduleTab({
  professional,
  branches,
  branchTab,
  dirty,
  formId,
  onDirtyChange,
  onSaved,
}: ProfessionalScheduleTabProps) {
  const { t } = useTranslation("appointments");
  const canAssign = useCan()("appointments.professional.assign");
  const access = useOwnerAccess();
  const assignment = useProfessionalAssignment();
  const orphan = useOrphanTimeOffs(professional);
  const [confirming, setConfirming] = useState<AssignConfirmation | null>(null);
  const { active, assigned } = branchTab;

  const assign = (branch: Branch) =>
    assignment.mutate(
      { branchId: branch.id, professionalId: professional.id, assign: true },
      { onSuccess: () => toast.success(t("catalog.professionalBranches.assignedDone")) },
    );

  function requestAssign(branchId: string) {
    const branch = branches.find((item) => item.id === branchId);
    if (!branch) return;
    const confirmation = orphan.confirmationFor(branch);
    if (confirmation) setConfirming(confirmation);
    else assign(branch);
  }

  return (
    <div className="grid gap-6">
      <section className="grid gap-3">
        <h3 className="text-sm font-semibold">{t("catalog.professionalBranches.title")}</h3>
        <ProfessionalBranches
          branches={branches}
          assignedIds={professional.branch_ids}
          canAssign={canAssign && !orphan.loading}
          onAssign={requestAssign}
          onUnassign={(branchId) =>
            assignment.mutate({ branchId, professionalId: professional.id, assign: false })
          }
        />
      </section>

      {active && access.scheduleRead ? (
        <PanelSection
          title={t("catalog.schedule.title")}
          description={t("catalog.timeOffs.branchHint", {
            branch: active.name,
            timeZone: active.time_zone,
          })}
        >
          <BranchSwitcher
            label={t("catalog.schedule.title")}
            branches={assigned}
            value={active.id}
            dirty={dirty}
            onChange={(branchId) => {
              branchTab.choose(branchId);
              onDirtyChange(false);
            }}
          />
          <OwnerScheduleTab
            key={active.id}
            slots={branchTab.reads.schedule}
            writes={branchTab.writes}
            formId={branchTab.editable.schedule ? formId : undefined}
            onDirtyChange={onDirtyChange}
            onSaved={onSaved}
          />
        </PanelSection>
      ) : null}

      {assigned.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("catalog.professionalBranches.none")}</p>
      ) : null}

      <AssignBranchDialog
        confirmation={confirming}
        onCancel={() => setConfirming(null)}
        onConfirm={({ branch }) => {
          assign(branch);
          setConfirming(null);
        }}
      />
    </div>
  );
}
