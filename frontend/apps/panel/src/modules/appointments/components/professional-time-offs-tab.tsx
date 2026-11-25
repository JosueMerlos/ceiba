import { useTranslation } from "@ceiba/i18n";
import { useCallback, useId, useState } from "react";
import { useContextBranch } from "../../../platform/context/use-context-branch";
import type { Branch } from "../api/catalog";
import {
  useCreateProfessionalTimeOff,
  useDeleteProfessionalTimeOff,
  useProfessionalTimeOffsQuery,
  type Professional,
} from "../api/professionals";
import { DEFAULT_TIME_ZONE } from "../lib/time-zones";
import { useOrphanTimeOffs } from "../lib/use-orphan-time-offs";
import { BranchSwitcher, useActiveBranch } from "./branch-switcher";
import { IdleForm } from "./idle-form";
import { PanelSection, TimeOffsSection } from "./owner-sections";
import { TimeOffsList } from "./time-offs-list";

interface ProfessionalTimeOffsTabProps {
  professional: Professional;
  /** Branches the user can see: a branch manager receives only theirs. */
  branches: readonly Branch[];
  /** The modal footer's form: it adds the absence typed in for the branch on screen. */
  formId: string;
  onDirtyChange(dirty: boolean): void;
  /** A creation step: with the form empty, the footer just finishes (no request). */
  skipClean?: boolean;
  /** After an absence is added, or when there was nothing to add in a creation step. */
  onDone?(): void;
}

/** Absences per assigned branch (added one at a time from the footer, removed at once) and those left with no branch. */
export function ProfessionalTimeOffsTab({
  professional,
  branches,
  formId,
  onDirtyChange,
  skipClean = false,
  onDone,
}: ProfessionalTimeOffsTabProps) {
  const { t } = useTranslation("appointments");
  const { branch: contextBranch } = useContextBranch();
  const orphan = useOrphanTimeOffs(professional);
  const [dirty, setDirty] = useState(false);
  const formOnlyId = useId();

  const assigned = branches.filter((branch) => professional.branch_ids.includes(branch.id));
  const { active, choose } = useActiveBranch(assigned);
  const idle = active === null || (skipClean && !dirty);
  // Without a branch the pending absences are shown in the zone of the context's branch, or the company's first.
  const orphanZone = contextBranch?.time_zone ?? branches[0]?.time_zone ?? DEFAULT_TIME_ZONE;

  const trackDirty = useCallback(
    (next: boolean) => {
      setDirty(next);
      onDirtyChange(next);
    },
    [onDirtyChange],
  );

  return (
    <div className="grid gap-6">
      {orphan.visible ? (
        <PanelSection
          title={t("catalog.timeOffs.pendingTitle")}
          description={t("catalog.timeOffs.pendingDescription")}
        >
          <TimeOffsList
            timeOffs={orphan.timeOffs}
            timeZone={orphanZone}
            canManage={orphan.canRemove}
            onDelete={orphan.remove}
          />
          <p className="text-xs text-muted-foreground">
            {t("catalog.timeOffs.pendingZone", { zone: orphanZone })}
          </p>
        </PanelSection>
      ) : null}

      {active ? (
        <div className="grid gap-4">
          <BranchSwitcher
            label={t("catalog.timeOffs.title")}
            branches={assigned}
            value={active.id}
            dirty={dirty}
            onChange={(branchId) => {
              choose(branchId);
              trackDirty(false);
            }}
          />
          <p className="text-sm text-muted-foreground">
            {t("catalog.timeOffs.branchHint", { branch: active.name, timeZone: active.time_zone })}
          </p>
          <BranchTimeOffs
            key={active.id}
            professionalId={professional.id}
            branch={active}
            formId={idle ? formOnlyId : formId}
            onDirtyChange={trackDirty}
            onAdded={onDone}
          />
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">{t("catalog.professionalBranches.none")}</p>
      )}

      {/* The absence form keeps the footer's id; with nothing typed in a creation step, finishing must not validate it. */}
      {idle ? <IdleForm id={formId} onSubmit={onDone} /> : null}
    </div>
  );
}

function BranchTimeOffs({
  professionalId,
  branch,
  formId,
  onDirtyChange,
  onAdded,
}: {
  professionalId: string;
  branch: Branch;
  formId: string;
  onDirtyChange(dirty: boolean): void;
  onAdded?(): void;
}) {
  const timeOffs = useProfessionalTimeOffsQuery(branch.id, professionalId);
  const create = useCreateProfessionalTimeOff(branch.id, professionalId);
  const remove = useDeleteProfessionalTimeOff(branch.id, professionalId);
  return (
    <TimeOffsSection
      timeOffs={timeOffs}
      timeZone={branch.time_zone}
      canManage
      formId={formId}
      onDirtyChange={onDirtyChange}
      onCreate={async (values) => {
        await create.mutateAsync(values);
        onAdded?.();
      }}
      onDelete={(timeOff, options) => remove.mutate(timeOff.id, options)}
    />
  );
}
