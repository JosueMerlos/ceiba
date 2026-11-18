import { useMe } from "../../../platform/me/me-provider";
import { useState } from "react";
import { useCompanyBranchesQuery, type Branch } from "../api/catalog";

/**
 * The branch a branch-scoped screen works on: the one in the context, else the one the user picks on the page. A company
 * with a single branch needs no choice. `needsChoice` is true when the user must pick one (more than one, none chosen).
 */
export function useWorkingBranch() {
  const { context } = useMe();
  const branches = useCompanyBranchesQuery();
  const [chosenId, setChosenId] = useState<string | null>(null);

  const list: Branch[] = branches.data?.data ?? [];
  const branch: Branch | null =
    context.branch ??
    list.find((item) => item.id === chosenId) ??
    (list.length === 1 ? (list[0] ?? null) : null);

  return {
    branch,
    branches: list,
    needsChoice: !context.branch && list.length > 1,
    choose: setChosenId,
  };
}
