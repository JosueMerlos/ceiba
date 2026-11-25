import { useBranchesQuery, type components } from "@ceiba/api-client";
import { useMe } from "../me/me-provider";

type Branch = components["schemas"]["Branch"];

interface ContextBranch {
  branch: Branch | null;
  needsChoice: boolean;
  /** The company's branches failed to load: there is no branch to work on until a retry succeeds. */
  failed: { error: unknown; retry(): void } | null;
  /** The company has no branch at all. */
  noBranches: boolean;
}

/**
 * The branch a branch-scoped screen works on, taken only from the global context selector. "All branches" in a
 * company with a single real branch still means that branch; with several, `needsChoice` asks the user to pick one
 * up there (the screen never offers its own picker).
 */
export function useContextBranch(): ContextBranch {
  const { context } = useMe();
  const branches = useBranchesQuery(context.organization?.id, context.company?.id);

  if (context.branch) {
    return { branch: context.branch, needsChoice: false, failed: null, noBranches: false };
  }
  const list = branches.data?.data ?? [];
  return {
    branch: list.length === 1 ? (list[0] ?? null) : null,
    needsChoice: list.length > 1,
    failed: branches.isError
      ? { error: branches.error, retry: () => void branches.refetch() }
      : null,
    noBranches: branches.isSuccess && list.length === 0,
  };
}
