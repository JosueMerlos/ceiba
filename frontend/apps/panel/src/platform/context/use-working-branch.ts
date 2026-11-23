import { useBranchesQuery } from "@ceiba/api-client";
import { useState } from "react";
import { useMe } from "../me/me-provider";

/**
 * The branch a branch-scoped platform screen works from: the context's, else the one picked on the page. A company with a
 * single branch needs no choice; `needsChoice` is true when the user must pick one.
 */
export function useWorkingBranch() {
  const { context } = useMe();
  const branches = useBranchesQuery(context.organization?.id, context.company?.id);
  const [chosenId, setChosenId] = useState<string | null>(null);

  const list = branches.data?.data ?? [];
  const branch =
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
