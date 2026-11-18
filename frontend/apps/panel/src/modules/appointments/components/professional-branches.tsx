import { useTranslation } from "@ceiba/i18n";
import { Checkbox, Label } from "@ceiba/ui";
import { useId } from "react";

interface ProfessionalBranchesProps {
  branches: readonly { id: string; name: string }[];
  assignedIds: readonly string[];
  /** `appointments.professional.assign`; the caller decides. */
  canAssign: boolean;
  onAssign(branchId: string): void;
  onUnassign(branchId: string): void;
}

/** One checkbox per branch: ticking assigns at once, unticking removes at once (each is its own request). */
export function ProfessionalBranches({
  branches,
  assignedIds,
  canAssign,
  onAssign,
  onUnassign,
}: ProfessionalBranchesProps) {
  const { t } = useTranslation("appointments");
  const groupId = useId();
  if (branches.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">{t("catalog.professionalBranches.empty")}</p>
    );
  }
  return (
    <div className="grid gap-2">
      {branches.map((branch) => {
        const id = `${groupId}-${branch.id}`;
        const assigned = assignedIds.includes(branch.id);
        return (
          <div key={branch.id} className="flex items-center gap-2.5">
            <Checkbox
              id={id}
              checked={assigned}
              disabled={!canAssign}
              onCheckedChange={() => (assigned ? onUnassign(branch.id) : onAssign(branch.id))}
            />
            <Label htmlFor={id} className="font-normal">
              {branch.name}
            </Label>
          </div>
        );
      })}
    </div>
  );
}
