import { useTranslation } from "@ceiba/i18n";
import { EmptyState } from "../ui/empty-state";

/**
 * What a branch-scoped screen shows under "All branches": the branch is chosen in the global context selector, never
 * on the page, so the notice points there and offers no control of its own.
 */
export function ChooseBranchNotice({ what }: { what: string }) {
  const { t } = useTranslation("common");
  return (
    <EmptyState
      title={t("chooseBranch.title")}
      description={t("chooseBranch.description", { what })}
    />
  );
}
