import { Button } from "@ceiba/ui";
import { Plus } from "lucide-react";
import { ReadOnlyBadge } from "./read-only-badge";

/**
 * The header action of a catalog page: "New" for whoever manages it; nothing for whoever only edits some sections of
 * existing records; the read-only badge for whoever can change nothing.
 */
export function CatalogHeaderActions({
  canManage,
  canEdit,
  newLabel,
  onNew,
}: {
  canManage: boolean;
  canEdit: boolean;
  newLabel: string;
  onNew(): void;
}) {
  if (canManage) {
    return (
      <Button type="button" onClick={onNew}>
        <Plus aria-hidden="true" />
        {newLabel}
      </Button>
    );
  }
  return canEdit ? null : <ReadOnlyBadge />;
}
