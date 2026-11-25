import { useTranslation } from "@ceiba/i18n";
import { toast } from "@ceiba/ui";
import { useCallback, useId, useState } from "react";
import { useCan } from "../../../platform/permissions/can";
import type { Branch } from "../api/catalog";
import {
  useProfessionalAssignment,
  useProfessionalScheduleQuery,
  usePutProfessionalSchedule,
  type Professional,
} from "../api/professionals";
import { useOrphanTimeOffs, type AssignConfirmation } from "../lib/use-orphan-time-offs";
import { AssignBranchDialog } from "./assign-branch-dialog";
import { BranchSwitcher, useActiveBranch } from "./branch-switcher";
import { IdleForm } from "./idle-form";
import { PanelSection, ScheduleSection, useOwnerAccess } from "./owner-sections";
import { ProfessionalBranches } from "./professional-branches";

interface ProfessionalScheduleTabProps {
  professional: Professional;
  /** Branches the user can see: a branch manager receives only theirs. */
  branches: readonly Branch[];
  /** The modal footer's form: it saves the weekly hours of the branch on screen. */
  formId: string;
  onDirtyChange(dirty: boolean): void;
  /** A creation step: with nothing changed, the footer just moves on (no request). */
  skipClean?: boolean;
  /** After the hours are saved, or when there was nothing to save in a creation step. */
  onDone?(): void;
}

/**
 * Where the professional works and their weekly hours there. The branch checkboxes apply at once (they are not part of
 * the footer's save); the footer saves the hours of the branch picked in the chips.
 */
export function ProfessionalScheduleTab({
  professional,
  branches,
  formId,
  onDirtyChange,
  skipClean = false,
  onDone,
}: ProfessionalScheduleTabProps) {
  const { t } = useTranslation("appointments");
  const canAssign = useCan()("appointments.professional.assign");
  const access = useOwnerAccess();
  const assignment = useProfessionalAssignment();
  const orphan = useOrphanTimeOffs(professional);
  const [confirming, setConfirming] = useState<AssignConfirmation | null>(null);
  const [dirty, setDirty] = useState(false);
  const editorOnlyId = useId();

  const assigned = branches.filter((branch) => professional.branch_ids.includes(branch.id));
  const { active, choose } = useActiveBranch(assigned);

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

  const trackDirty = useCallback(
    (next: boolean) => {
      setDirty(next);
      onDirtyChange(next);
    },
    [onDirtyChange],
  );

  // The footer submits the editor only when there are hours to save; otherwise an empty form takes its id.
  const editable = active !== null && access.scheduleManage;
  const idle = !editable || (skipClean && !dirty);

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
              choose(branchId);
              trackDirty(false);
            }}
          />
          <BranchSchedule
            key={active.id}
            professionalId={professional.id}
            branch={active}
            canManage={access.scheduleManage}
            formId={idle ? editorOnlyId : formId}
            onDirtyChange={trackDirty}
            onSaved={onDone}
          />
        </PanelSection>
      ) : null}

      {assigned.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("catalog.professionalBranches.none")}</p>
      ) : null}

      {idle ? <IdleForm id={formId} onSubmit={onDone} /> : null}

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

function BranchSchedule({
  professionalId,
  branch,
  canManage,
  formId,
  onDirtyChange,
  onSaved,
}: {
  professionalId: string;
  branch: Branch;
  canManage: boolean;
  formId: string;
  onDirtyChange(dirty: boolean): void;
  onSaved?(): void;
}) {
  const schedule = useProfessionalScheduleQuery(branch.id, professionalId);
  const save = usePutProfessionalSchedule(branch.id, professionalId);
  return (
    <ScheduleSection
      slots={schedule}
      save={save}
      canManage={canManage}
      formId={canManage ? formId : undefined}
      onDirtyChange={onDirtyChange}
      onSaved={onSaved}
    />
  );
}
