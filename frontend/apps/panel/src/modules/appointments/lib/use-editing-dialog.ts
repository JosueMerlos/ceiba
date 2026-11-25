import { useState } from "react";

type Editing<T> = { kind: "new" } | { kind: "edit"; item: T } | null;

/**
 * Which create/edit modal of a catalog page is open. The edited record is read from the live list, so the modal
 * follows what a save refetches; until the list has it, the record the user picked stands in.
 */
export function useEditingDialog<T extends { id: string }>(list: readonly T[]) {
  const [editing, setEditing] = useState<Editing<T>>(null);
  const edited =
    editing?.kind === "edit"
      ? (list.find((item) => item.id === editing.item.id) ?? editing.item)
      : undefined;
  return {
    creating: editing?.kind === "new",
    edited,
    openNew: () => setEditing({ kind: "new" }),
    openEdit: (item: T) => setEditing({ kind: "edit", item }),
    onOpenChange: (open: boolean) => {
      if (!open) setEditing(null);
    },
  };
}
