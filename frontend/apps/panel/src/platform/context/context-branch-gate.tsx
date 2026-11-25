import type { components } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import type { ReactNode } from "react";
import { EmptyState } from "../ui/empty-state";
import { QueryError } from "../ui/query-error";
import { ChooseBranchNotice } from "./choose-branch-notice";
import { useContextBranch } from "./use-context-branch";

type Branch = components["schemas"]["Branch"];

/**
 * Renders a branch-scoped screen for the context's branch. When there is none to work on it shows `header` and why:
 * pick one in the global selector (several branches), the branches failed to load (with a retry), or the company has
 * none yet. While the branches load it renders nothing.
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
  const { t } = useTranslation("common");
  const { branch, needsChoice, failed, noBranches } = useContextBranch();
  if (branch) return children(branch);

  let notice: ReactNode = null;
  if (needsChoice) notice = <ChooseBranchNotice what={what} />;
  else if (failed) notice = <QueryError error={failed.error} onRetry={failed.retry} />;
  else if (noBranches) {
    notice = (
      <EmptyState
        title={t("noBranches.title")}
        description={t("noBranches.description", { what })}
      />
    );
  }
  if (!notice) return null;
  return (
    <>
      {header}
      {notice}
    </>
  );
}
