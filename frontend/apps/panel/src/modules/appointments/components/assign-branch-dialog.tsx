import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@ceiba/ui";
import type { AssignConfirmation } from "../lib/use-orphan-time-offs";

/** Asks before giving a branch to someone whose pending absences will then follow them into it. */
export function AssignBranchDialog({
  confirmation,
  onCancel,
  onConfirm,
}: {
  confirmation: AssignConfirmation | null;
  onCancel(): void;
  onConfirm(confirmation: AssignConfirmation): void;
}) {
  const { t } = useTranslation(["appointments", "common"]);
  const branch = confirmation?.branch.name ?? "";
  return (
    <Dialog open={confirmation !== null} onOpenChange={(open) => (open ? undefined : onCancel())}>
      <DialogContent closeLabel={t("common:close")}>
        <DialogHeader>
          <DialogTitle>{t("catalog.professionalBranches.confirm.title", { branch })}</DialogTitle>
          <DialogDescription>
            {confirmation?.count == null
              ? t("catalog.professionalBranches.confirm.generic", { branch })
              : t("catalog.professionalBranches.confirm.description", {
                  count: confirmation.count,
                  branch,
                })}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onCancel}>
            {t("common:cancel")}
          </Button>
          <Button
            type="button"
            onClick={() => {
              if (confirmation) onConfirm(confirmation);
            }}
          >
            {t("catalog.professionalBranches.confirm.action")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
