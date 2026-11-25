import type { Branch } from "../api/catalog";
import { professionalOwnerApi, useOwnerReads, useOwnerWrites } from "../api/owners";
import type { Professional } from "../api/professionals";
import { useActiveBranch } from "./branch-switcher";
import { useOwnerAccess } from "./owner-sections";

/**
 * The branch the professional's hours and absences tabs work on, with its reads and writes. The modal holds it: its
 * footer needs to know whether the tab on screen has a form and what that form's save is waiting on.
 */
export function useProfessionalBranchTab(
  professional: Professional | null,
  /** Branches the user can see: a branch manager receives only theirs. */
  branches: readonly Branch[],
  /** The section on screen: only its query runs. */
  shown: "schedule" | "timeOffs" | null,
) {
  const access = useOwnerAccess();
  const assigned = branches.filter((branch) => professional?.branch_ids.includes(branch.id));
  const { active, choose } = useActiveBranch(assigned);
  const branchId = active?.id ?? "";
  const ownerId = professional?.id ?? "";
  const ready = active !== null && professional !== null;
  const reads = useOwnerReads(professionalOwnerApi, branchId, ownerId, {
    schedule: ready && shown === "schedule" && access.scheduleRead,
    timeOffs: ready && shown === "timeOffs",
  });
  const writes = useOwnerWrites(professionalOwnerApi, branchId, ownerId);
  return {
    assigned,
    active,
    choose,
    reads,
    writes,
    /**
     * Whether each tab has a form for the footer to submit: with no branch there is nothing to edit, and the form
     * exists only once its data loaded (hours the user cannot read are never shown).
     */
    editable: {
      schedule:
        active !== null && access.scheduleRead && access.scheduleManage && reads.schedule.isSuccess,
      timeOffs: active !== null && access.timeOffManage && reads.timeOffs.isSuccess,
    },
  };
}

export type ProfessionalBranchTab = ReturnType<typeof useProfessionalBranchTab>;
