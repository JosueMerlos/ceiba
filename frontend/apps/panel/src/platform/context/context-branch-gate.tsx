import type { components } from "@ceiba/api-client";
import type { ReactNode } from "react";
import { ChooseBranchNotice } from "./choose-branch-notice";
import { useContextBranch } from "./use-context-branch";

type Branch = components["schemas"]["Branch"];

/**
 * Renders a branch-scoped screen for the context's branch. Under "All branches" with several branches it shows
 * `header` and the notice to pick one in the global selector; while the branches load it renders nothing.
 */
export function ContextBranchGate({
  what,
  header,
  children,
}: {
  /** What needs a branch, for the notice ("the agenda", "the resources"). */
  what: string;
  header?: ReactNode;
  children(branch: Branch): ReactNode;
}) {
  const { branch, needsChoice } = useContextBranch();
  if (needsChoice) {
    return (
      <>
        {header}
        <ChooseBranchNotice what={what} />
      </>
    );
  }
  return branch ? children(branch) : null;
}
