import { useState } from "react";

type PanelState = { kind: "entity"; id: string } | { kind: "new" } | null;

/**
 * Which context panel a catalog page shows: the selected row, the blank "new" form or none. The selection is kept as an
 * id and resolved against the current list, so a row that disappears (archived, filtered out) closes its panel.
 */
export function useEntityPanel<T extends { id: string }>(list: readonly T[]) {
  const [panel, setPanel] = useState<PanelState>(null);
  const selected = panel?.kind === "entity" ? list.find((item) => item.id === panel.id) : undefined;
  const isNew = panel?.kind === "new";

  return {
    selected,
    isNew,
    open: isNew || selected !== undefined,
    openNew: () => setPanel({ kind: "new" }),
    select: (id: string) => setPanel({ kind: "entity", id }),
    close: () => setPanel(null),
  };
}
