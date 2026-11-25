import { useTranslation } from "@ceiba/i18n";
import { Badge } from "@ceiba/ui";
import { Lock } from "lucide-react";

/** Tells whoever only reads a catalog why there is nothing to click: shown in place of the page's actions. */
export function ReadOnlyBadge() {
  const { t } = useTranslation("appointments");
  return (
    <Badge variant="muted" className="self-center">
      <Lock aria-hidden="true" />
      {t("catalog.readOnlyBadge")}
    </Badge>
  );
}
