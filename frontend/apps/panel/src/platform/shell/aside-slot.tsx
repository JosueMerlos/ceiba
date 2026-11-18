import { createContext, useContext, type ReactNode } from "react";
import { createPortal } from "react-dom";

// The layout owns the contextual panel's place (to the right of the sheet), but each screen decides what goes there.
// The shell publishes that place as a DOM node and screens portal their `ContextPanel` into it.
const AsideSlotContext = createContext<HTMLElement | null>(null);

export const AsideSlotProvider = AsideSlotContext.Provider;

/** Renders its children in the layout's contextual-panel slot. Outside the shell (no slot) it renders nothing. */
export function AsidePortal({ children }: { children: ReactNode }) {
  const slot = useContext(AsideSlotContext);
  return slot ? createPortal(children, slot) : null;
}
