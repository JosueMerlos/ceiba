import { ConfirmDialog, ToggleGroup, ToggleGroupItem } from "@ceiba/ui";
import { useState } from "react";
import { useContextBranch } from "../../../platform/context/use-context-branch";
import { useFormDialogLabels } from "../../../platform/ui/use-form-dialog-labels";
import type { Branch } from "../api/catalog";

/**
 * Which of the professional's branches a modal tab edits: the context's branch when it is one of them, otherwise the
 * first. Resolved on every render, so a branch just assigned or removed never leaves the tab on a stale one.
 */
export function useActiveBranch(branches: readonly Branch[]) {
  const { branch: contextBranch } = useContextBranch();
  const [chosen, setChosen] = useState<string | null>(null);
  const active =
    branches.find((item) => item.id === chosen) ??
    branches.find((item) => item.id === contextBranch?.id) ??
    branches[0] ??
    null;
  return { active, choose: setChosen };
}

/** One chip per branch; leaving a branch with unsaved changes asks first, like leaving a tab. */
export function BranchSwitcher({
  label,
  branches,
  value,
  dirty,
  onChange,
}: {
  label: string;
  branches: readonly Branch[];
  value: string;
  dirty: boolean;
  onChange(branchId: string): void;
}) {
  const labels = useFormDialogLabels();
  const [pending, setPending] = useState<string | null>(null);

  return (
    <>
      <ToggleGroup
        aria-label={label}
        value={value}
        onValueChange={(next) => (dirty ? setPending(next) : onChange(next))}
      >
        {branches.map((branch) => (
          <ToggleGroupItem key={branch.id} value={branch.id}>
            {branch.name}
          </ToggleGroupItem>
        ))}
      </ToggleGroup>
      <ConfirmDialog
        open={pending !== null}
        onOpenChange={(open) => {
          if (!open) setPending(null);
        }}
        {...labels.discard}
        onConfirm={() => {
          if (pending) onChange(pending);
          setPending(null);
        }}
      />
    </>
  );
}
