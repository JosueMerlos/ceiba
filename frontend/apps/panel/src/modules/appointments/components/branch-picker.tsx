import { useTranslation } from "@ceiba/i18n";
import { Label, Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@ceiba/ui";
import { useId } from "react";

interface BranchPickerProps {
  branches: readonly { id: string; name: string }[];
  value: string | null;
  onChange(id: string): void;
}

/** Page-level branch choice for managers who work at company level (no branch in the context). */
export function BranchPicker({ branches, value, onChange }: BranchPickerProps) {
  const { t } = useTranslation("appointments");
  const id = useId();
  return (
    <div className="mb-4 grid max-w-xs gap-1.5">
      <Label htmlFor={id}>{t("catalog.workingBranch.label")}</Label>
      <Select value={value ?? undefined} onValueChange={onChange}>
        <SelectTrigger id={id}>
          <SelectValue placeholder={t("catalog.workingBranch.placeholder")} />
        </SelectTrigger>
        <SelectContent>
          {branches.map((branch) => (
            <SelectItem key={branch.id} value={branch.id}>
              {branch.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {value ? null : (
        <p className="text-sm text-muted-foreground">{t("catalog.workingBranch.hint")}</p>
      )}
    </div>
  );
}
