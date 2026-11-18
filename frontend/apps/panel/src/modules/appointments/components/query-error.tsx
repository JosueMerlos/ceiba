import { useTranslation } from "@ceiba/i18n";
import { Button } from "@ceiba/ui";
import { describeError } from "../../../platform/errors/global-errors";

/** A query failed with something the global policy does not turn into a page (network, 5xx): say so and offer a retry. */
export function QueryError({ error, onRetry }: { error: unknown; onRetry(): void }) {
  const { t } = useTranslation(["appointments", "common", "errors"]);
  return (
    <div
      role="alert"
      className="grid justify-items-start gap-3 rounded-lg border border-destructive/30 bg-destructive/5 p-4"
    >
      <p className="text-sm font-medium text-destructive">{describeError(error, t)}</p>
      <Button type="button" variant="outline" size="sm" onClick={onRetry}>
        {t("common:retry")}
      </Button>
    </div>
  );
}
