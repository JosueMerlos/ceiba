import { useBranchesQuery, type components } from "@ceiba/api-client";
import { useMe } from "../me/me-provider";

type Branch = components["schemas"]["Branch"];

/**
 * The branch a branch-scoped screen works on, taken only from the global context selector. "All branches" in a
 * company with a single real branch still means that branch; with several, `needsChoice` asks the user to pick one
 * up there (the screen never offers its own picker).
 */
export function useContextBranch(): { branch: Branch | null; needsChoice: boolean } {
  const { context } = useMe();
  const branches = useBranchesQuery(context.organization?.id, context.company?.id);

  if (context.branch) return { branch: context.branch, needsChoice: false };
  const list = branches.data?.data ?? [];
  return {
    branch: list.length === 1 ? (list[0] ?? null) : null,
    needsChoice: list.length > 1,
  };
}
