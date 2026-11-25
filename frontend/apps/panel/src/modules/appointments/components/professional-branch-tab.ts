import type { Branch } from "../api/catalog";
import { professionalOwnerApi, useOwnerWrites } from "../api/owners";
import type { Professional } from "../api/professionals";
import { useActiveBranch } from "./branch-switcher";
import { useOwnerAccess } from "./owner-sections";

/**
 * The branch the professional's hours and absences tabs work on, and the writes for it. The modal holds it: its footer
 * needs to know whether the tab on screen has a form and what that form's save is waiting on.
 */
export function useProfessionalBranchTab(
  professional: Professional | null,
  /** Branches the user can see: a branch manager receives only theirs. */
  branches: readonly Branch[],
) {
  const access = useOwnerAccess();
  const assigned = branches.filter((branch) => professional?.branch_ids.includes(branch.id));
  const { active, choose } = useActiveBranch(assigned);
  const writes = useOwnerWrites(professionalOwnerApi, active?.id ?? "", professional?.id ?? "");
  return {
    assigned,
    active,
    choose,
    writes,
    /** Whether each tab has a form for the footer to submit: with no branch there is nothing to edit. */
    editable: {
      schedule: active !== null && access.scheduleManage,
      timeOffs: active !== null && access.timeOffManage,
    },
  };
}

export type ProfessionalBranchTab = ReturnType<typeof useProfessionalBranchTab>;
